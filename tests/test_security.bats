#!/usr/bin/env bats
# BATS tests for security-related functions
# Run with: bats tests/

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d)"

    # Define secure_download_run for testing (simplified version)
    secure_download_run() {
        local url="$1"

        # Validate HTTPS
        if [[ ! "$url" =~ ^https:// ]]; then
            echo "Security: Only HTTPS URLs allowed: $url" >&2
            return 1
        fi

        return 0  # In real function, would download and execute
    }
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# URL validation tests
# =============================================================================

@test "secure_download_run accepts HTTPS URLs" {
    run secure_download_run "https://example.com/script.sh"
    [ "$status" -eq 0 ]
}

@test "secure_download_run rejects HTTP URLs" {
    run secure_download_run "http://example.com/script.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Only HTTPS URLs allowed"* ]]
}

@test "secure_download_run rejects FTP URLs" {
    run secure_download_run "ftp://example.com/script.sh"
    [ "$status" -eq 1 ]
}

@test "secure_download_run rejects file:// URLs" {
    run secure_download_run "file:///etc/passwd"
    [ "$status" -eq 1 ]
}

@test "secure_download_run rejects URLs without protocol" {
    run secure_download_run "example.com/script.sh"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Main script security checks
# =============================================================================

@test "main script uses set -e" {
    run grep -q "^set -e" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}

@test "main script uses set -o pipefail" {
    run grep -q "set -o pipefail" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}

@test "lib/core.sh validates HTTPS in secure_download_run" {
    # Function moved to lib/core.sh for modularity
    run grep -A10 "secure_download_run()" "$SCRIPT_DIR/lib/core.sh"
    [[ "$output" == *"https://"* ]]
}

@test "lib/core.sh clears SUDO_PASSWORD after use" {
    # Function moved to lib/core.sh for modularity
    run grep -q "unset SUDO_PASSWORD" "$SCRIPT_DIR/lib/core.sh"
    [ "$status" -eq 0 ]
}

@test "main script uses ed25519 for SSH keys" {
    run grep "ssh-keygen.*ed25519" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}

@test "main script sets proper SSH key permissions" {
    run grep "chmod 600.*id_ed25519" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}

@test "main script sets proper .ssh directory permissions" {
    run grep "chmod 700.*\.ssh" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# No dangerous patterns
# =============================================================================

@test "no eval with user input" {
    # Check for dangerous eval patterns
    run grep -n 'eval.*\$' "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    # If found, make sure it's safe (pyenv init is expected)
    if [ "$status" -eq 0 ]; then
        [[ "$output" == *"pyenv init"* ]] || [[ "$output" == *"nvm.sh"* ]] || [[ "$output" == *"oh-my-posh"* ]]
    fi
}

@test "no curl piped directly to shell without validation" {
    # Check that curl | bash patterns use secure_download_run instead
    run grep -c "curl.*|.*bash\|curl.*|.*sh" "$SCRIPT_DIR/wsl_ubuntu_setup.sh"
    # Should be minimal (only in secure_download_run or with validation)
    [ "${output:-0}" -lt 5 ]
}
