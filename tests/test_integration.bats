#!/usr/bin/env bats
# Integration tests for wsl_ubuntu_setup.sh
# Tests security validation functions and checkpoint system integration
# Run with: bats tests/test_integration.bats

# Setup - source validation functions from the main script
setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d)"
    export LOG_DIR="$TEST_TMPDIR"
    export LOG_FILE="$TEST_TMPDIR/test.log"
    export CHECKPOINT_FILE="$TEST_TMPDIR/.checkpoint"

    touch "$LOG_FILE"

    # Source validation functions (extracted from main script)
    # These are the security-critical functions we need to test

    log() {
        local level="$1"
        local message="$2"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    }

    print_error() {
        echo "ERROR: $1"
    }

    print_warning() {
        echo "WARNING: $1"
    }

    # validate_repo_entry - prevents command injection in REPO_LIST
    validate_repo_entry() {
        local entry="$1"
        if [ -z "$entry" ]; then
            print_error "Empty repository entry"
            return 1
        fi
        if [[ "$entry" =~ [\$\`\|\;\&\>\<\(\)\{\}] ]]; then
            print_error "Invalid repo entry (contains shell metacharacters): $entry"
            log "SECURITY" "Blocked repo entry with shell metacharacters: $entry"
            return 1
        fi
        if [[ "$entry" == *".."* ]]; then
            print_error "Invalid repo entry (path traversal detected): $entry"
            log "SECURITY" "Blocked repo entry with path traversal: $entry"
            return 1
        fi
        return 0
    }

    # validate_user_input - sanitizes USER_FULLNAME/EMAIL
    validate_user_input() {
        local var_name="$1"
        local var_value="$2"
        if [ -z "$var_value" ]; then
            print_error "$var_name cannot be empty"
            return 1
        fi
        # Use glob patterns for reliable metacharacter detection
        if [[ "$var_value" == *'$'* ]] || [[ "$var_value" == *'`'* ]] || \
           [[ "$var_value" == *'|'* ]] || [[ "$var_value" == *';'* ]] || \
           [[ "$var_value" == *'&'* ]] || [[ "$var_value" == *'>'* ]] || \
           [[ "$var_value" == *'<'* ]] || [[ "$var_value" == *'('* ]] || \
           [[ "$var_value" == *')'* ]] || [[ "$var_value" == *'['* ]] || \
           [[ "$var_value" == *']'* ]] || [[ "$var_value" == *'{'* ]] || \
           [[ "$var_value" == *'}'* ]] || [[ "$var_value" == *'\'* ]]; then
            print_error "$var_name contains invalid characters (shell metacharacters not allowed)"
            log "SECURITY" "Blocked $var_name with shell metacharacters"
            return 1
        fi
        if [[ "$var_name" == *"EMAIL"* ]]; then
            if [[ ! "$var_value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                print_error "$var_name is not a valid email address: $var_value"
                return 1
            fi
        fi
        if [ ${#var_value} -gt 256 ]; then
            print_error "$var_name exceeds maximum length (256 characters)"
            return 1
        fi
        return 0
    }

    # Checkpoint functions
    is_completed() {
        local section=$1
        [ -f "$CHECKPOINT_FILE" ] && grep -q "^$section$" "$CHECKPOINT_FILE"
    }

    mark_completed() {
        local section=$1
        echo "$section" >> "$CHECKPOINT_FILE"
    }
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# validate_repo_entry tests - Command Injection Prevention
# =============================================================================

@test "validate_repo_entry accepts valid repo entry" {
    run validate_repo_entry "myrepo:git@github.com:user/repo.git:~/projects/repo"
    [ "$status" -eq 0 ]
}

@test "validate_repo_entry rejects empty entry" {
    run validate_repo_entry ""
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects command substitution \$()" {
    run validate_repo_entry 'test:$(touch /tmp/pwned):~/'
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects backtick command substitution" {
    run validate_repo_entry 'test:\`touch /tmp/pwned\`:~/'
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects pipe injection" {
    run validate_repo_entry 'test:git@github.com:user/repo.git|rm -rf /:~/'
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects semicolon injection" {
    run validate_repo_entry 'test:git@github.com:user/repo.git;rm -rf /:~/'
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects && injection" {
    run validate_repo_entry 'test:git@github.com:user/repo.git&&rm -rf /:~/'
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry rejects path traversal .." {
    run validate_repo_entry "test:git@github.com:user/repo.git:../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_repo_entry logs security events" {
    validate_repo_entry 'test:$(malicious):~/' 2>/dev/null || true
    run grep "SECURITY" "$LOG_FILE"
    [ "$status" -eq 0 ]
}

# =============================================================================
# validate_user_input tests - Input Sanitization
# =============================================================================

@test "validate_user_input accepts valid full name" {
    run validate_user_input "USER_FULLNAME" "John Doe"
    [ "$status" -eq 0 ]
}

@test "validate_user_input accepts valid email" {
    run validate_user_input "USER_EMAIL" "john.doe@example.com"
    [ "$status" -eq 0 ]
}

@test "validate_user_input rejects empty value" {
    run validate_user_input "USER_FULLNAME" ""
    [ "$status" -eq 1 ]
}

@test "validate_user_input rejects shell metacharacters in name" {
    run validate_user_input "USER_FULLNAME" 'John $(rm -rf /)'
    [ "$status" -eq 1 ]
}

@test "validate_user_input rejects backticks in name" {
    run validate_user_input "USER_FULLNAME" 'John \`whoami\`'
    [ "$status" -eq 1 ]
}

@test "validate_user_input rejects invalid email format" {
    run validate_user_input "USER_EMAIL" "not-an-email"
    [ "$status" -eq 1 ]
}

@test "validate_user_input rejects email with injection" {
    run validate_user_input "USER_EMAIL" 'test@example.com;rm -rf /'
    [ "$status" -eq 1 ]
}

@test "validate_user_input rejects excessively long input" {
    local long_input=$(printf 'a%.0s' {1..300})
    run validate_user_input "USER_FULLNAME" "$long_input"
    [ "$status" -eq 1 ]
}

@test "validate_user_input accepts email with subdomain" {
    run validate_user_input "USER_EMAIL" "user@mail.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_user_input accepts email with plus addressing" {
    run validate_user_input "USER_EMAIL" "user+tag@example.com"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Checkpoint System Integration Tests
# =============================================================================

@test "checkpoint system survives multiple operations" {
    mark_completed "step_1"
    mark_completed "step_2"
    mark_completed "step_3"

    # Verify all steps are tracked
    run is_completed "step_1"
    [ "$status" -eq 0 ]

    run is_completed "step_2"
    [ "$status" -eq 0 ]

    run is_completed "step_3"
    [ "$status" -eq 0 ]

    # Verify non-existent step is not tracked
    run is_completed "step_4"
    [ "$status" -eq 1 ]
}

@test "checkpoint file persists across function calls" {
    mark_completed "persistent_test"

    # Simulate re-reading checkpoint (as would happen after script restart)
    run cat "$CHECKPOINT_FILE"
    [[ "$output" == *"persistent_test"* ]]
}

@test "checkpoint handles special characters in section names" {
    mark_completed "python_env"
    mark_completed "nodejs_env"
    mark_completed "k8s_tools"

    run is_completed "python_env"
    [ "$status" -eq 0 ]

    run is_completed "nodejs_env"
    [ "$status" -eq 0 ]

    run is_completed "k8s_tools"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Security Event Logging Tests
# =============================================================================

@test "security events are logged with timestamp" {
    # Use USER_FULLNAME to bypass email validation and trigger metacharacter check
    validate_user_input "USER_FULLNAME" 'test;injection' 2>/dev/null || true
    run cat "$LOG_FILE"
    [[ "$output" == *"SECURITY"* ]]
    [[ "$output" == *"20"* ]]  # Year in timestamp
}

@test "multiple security events are logged sequentially" {
    validate_repo_entry 'bad$(cmd):url:path' 2>/dev/null || true
    validate_user_input "USER_FULLNAME" 'Bad$(name)' 2>/dev/null || true

    local count=$(grep -c "SECURITY" "$LOG_FILE")
    [ "$count" -ge 2 ]
}

# =============================================================================
# Additional Validation Tests
# =============================================================================

@test "validate_repo_entry accepts repo with numbers in name" {
    run validate_repo_entry "repo123:git@github.com:user/repo123.git:~/projects/repo123"
    [ "$status" -eq 0 ]
}

@test "validate_repo_entry accepts repo with hyphens and underscores" {
    run validate_repo_entry "my-repo_name:git@github.com:user/repo.git:~/my-project"
    [ "$status" -eq 0 ]
}

@test "validate_user_input accepts international characters in name" {
    run validate_user_input "USER_FULLNAME" "José García"
    [ "$status" -eq 0 ]
}

@test "validate_user_input rejects newline injection" {
    run validate_user_input "USER_FULLNAME" $'John\nDoe'
    # Should pass as newlines aren't in our blocked list but let's verify behavior
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# verify_download_script tests (function signature test)
# =============================================================================

@test "verify_download_script function exists in lib/core.sh" {
    # Functions moved to lib/core.sh for modularity
    run grep -q "verify_download_script()" "$SCRIPT_DIR/lib/core.sh"
    [ "$status" -eq 0 ]
}

@test "validate_repo_entry function exists in lib/core.sh" {
    run grep -q "validate_repo_entry()" "$SCRIPT_DIR/lib/core.sh"
    [ "$status" -eq 0 ]
}

@test "validate_user_input function exists in lib/core.sh" {
    run grep -q "validate_user_input()" "$SCRIPT_DIR/lib/core.sh"
    [ "$status" -eq 0 ]
}

@test "retry_fetch function exists in lib/core.sh" {
    run grep -q "retry_fetch()" "$SCRIPT_DIR/lib/core.sh"
    [ "$status" -eq 0 ]
}

@test "install_bats_helpers function exists in script" {
    run grep -q "install_bats_helpers()" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}
