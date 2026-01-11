#!/usr/bin/env bats
# BATS tests for wsl_ubuntu_setup.sh helper functions
# Run with: bats tests/

# Setup - source only the helper functions we need to test
setup() {
    # Create temp directory for test artifacts
    export TEST_TMPDIR="$(mktemp -d)"
    export LOG_DIR="$TEST_TMPDIR"
    export LOG_FILE="$TEST_TMPDIR/test.log"
    export CHECKPOINT_FILE="$TEST_TMPDIR/.checkpoint"

    # Create log file
    touch "$LOG_FILE"

    # Source helper functions (extract from main script)
    # We define them inline to avoid sourcing the full script with set -e

    command_exists() {
        command -v "$1" &> /dev/null
    }

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
    # Cleanup temp directory
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# command_exists tests
# =============================================================================

@test "command_exists returns 0 for existing command (bash)" {
    run command_exists bash
    [ "$status" -eq 0 ]
}

@test "command_exists returns 0 for existing command (ls)" {
    run command_exists ls
    [ "$status" -eq 0 ]
}

@test "command_exists returns 1 for non-existent command" {
    run command_exists nonexistent_command_xyz_12345
    [ "$status" -eq 1 ]
}

@test "command_exists returns 1 for empty string" {
    run command_exists ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# is_completed / mark_completed tests
# =============================================================================

@test "is_completed returns 1 for uncompleted section" {
    run is_completed "test_section"
    [ "$status" -eq 1 ]
}

@test "mark_completed creates checkpoint file" {
    mark_completed "test_section"
    [ -f "$CHECKPOINT_FILE" ]
}

@test "mark_completed adds section to checkpoint" {
    mark_completed "test_section"
    run grep -q "^test_section$" "$CHECKPOINT_FILE"
    [ "$status" -eq 0 ]
}

@test "is_completed returns 0 after mark_completed" {
    mark_completed "test_section"
    run is_completed "test_section"
    [ "$status" -eq 0 ]
}

@test "is_completed returns 1 for different section" {
    mark_completed "section_a"
    run is_completed "section_b"
    [ "$status" -eq 1 ]
}

@test "multiple sections can be marked completed" {
    mark_completed "section_1"
    mark_completed "section_2"
    mark_completed "section_3"

    run is_completed "section_1"
    [ "$status" -eq 0 ]

    run is_completed "section_2"
    [ "$status" -eq 0 ]

    run is_completed "section_3"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Checkpoint file edge cases
# =============================================================================

@test "is_completed handles missing checkpoint file" {
    rm -f "$CHECKPOINT_FILE"
    run is_completed "any_section"
    [ "$status" -eq 1 ]
}

@test "is_completed handles empty checkpoint file" {
    touch "$CHECKPOINT_FILE"
    run is_completed "any_section"
    [ "$status" -eq 1 ]
}

@test "is_completed does partial matching correctly" {
    # Should NOT match "shell" when only "shell_config" is completed
    mark_completed "shell_config"
    run is_completed "shell"
    [ "$status" -eq 1 ]
}

@test "is_completed matches exact section names" {
    mark_completed "python_env"
    run is_completed "python_env"
    [ "$status" -eq 0 ]

    # Should not match similar names
    run is_completed "python"
    [ "$status" -eq 1 ]

    run is_completed "python_env_extra"
    [ "$status" -eq 1 ]
}

# =============================================================================
# copy_or_download_dotfile tests
# =============================================================================

# Setup copy_or_download_dotfile function for testing
setup_dotfile_helper() {
    export SCRIPT_DIR="$TEST_TMPDIR/repo"
    mkdir -p "$SCRIPT_DIR/dotfiles"

    # Mock print functions
    print_success() { echo "SUCCESS: $1"; }
    print_error() { echo "ERROR: $1"; }
    print_info() { echo "INFO: $1"; }

    # Define the copy_or_download_dotfile function
    copy_or_download_dotfile() {
        local src_name="$1"
        local dst_path="$2"
        shift 2

        local force=false
        local chmod_mode=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --force) force=true; shift ;;
                --chmod) chmod_mode="$2"; shift 2 ;;
                *) shift ;;
            esac
        done

        local dotfiles_dir="$SCRIPT_DIR/dotfiles"
        local github_base="https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main/dotfiles"
        local local_src="$dotfiles_dir/$src_name"
        local github_url="$github_base/$src_name"

        if [ -f "$dst_path" ] && [ "$force" = false ]; then
            print_info "$dst_path already exists, skipping"
            return 0
        fi

        local dst_dir
        dst_dir=$(dirname "$dst_path")
        [ -d "$dst_dir" ] || mkdir -p "$dst_dir"

        if [ -f "$local_src" ]; then
            cp "$local_src" "$dst_path"
            [ -n "$chmod_mode" ] && chmod "$chmod_mode" "$dst_path"
            print_success "$(basename "$dst_path") installed from repo"
            return 0
        elif curl -fsSL "$github_url" -o "$dst_path" 2>/dev/null; then
            [ -n "$chmod_mode" ] && chmod "$chmod_mode" "$dst_path"
            print_success "$(basename "$dst_path") downloaded from GitHub"
            return 0
        else
            print_error "Could not install $(basename "$dst_path") (local not found, download failed)"
            return 1
        fi
    }
}

@test "copy_or_download_dotfile uses local file when available" {
    setup_dotfile_helper

    # Create local dotfile
    echo "local content" > "$SCRIPT_DIR/dotfiles/test.conf"

    # Run function
    run copy_or_download_dotfile "test.conf" "$TEST_TMPDIR/dest/test.conf"

    [ "$status" -eq 0 ]
    [[ "$output" == *"installed from repo"* ]]
    [ -f "$TEST_TMPDIR/dest/test.conf" ]
    [ "$(cat "$TEST_TMPDIR/dest/test.conf")" = "local content" ]
}

@test "copy_or_download_dotfile creates destination directory" {
    setup_dotfile_helper

    echo "content" > "$SCRIPT_DIR/dotfiles/test.conf"

    run copy_or_download_dotfile "test.conf" "$TEST_TMPDIR/deep/nested/dir/test.conf"

    [ "$status" -eq 0 ]
    [ -d "$TEST_TMPDIR/deep/nested/dir" ]
    [ -f "$TEST_TMPDIR/deep/nested/dir/test.conf" ]
}

@test "copy_or_download_dotfile skips existing file without --force" {
    setup_dotfile_helper

    mkdir -p "$TEST_TMPDIR/dest"
    echo "existing" > "$TEST_TMPDIR/dest/test.conf"
    echo "new content" > "$SCRIPT_DIR/dotfiles/test.conf"

    run copy_or_download_dotfile "test.conf" "$TEST_TMPDIR/dest/test.conf"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists, skipping"* ]]
    [ "$(cat "$TEST_TMPDIR/dest/test.conf")" = "existing" ]
}

@test "copy_or_download_dotfile overwrites with --force" {
    setup_dotfile_helper

    mkdir -p "$TEST_TMPDIR/dest"
    echo "existing" > "$TEST_TMPDIR/dest/test.conf"
    echo "new content" > "$SCRIPT_DIR/dotfiles/test.conf"

    run copy_or_download_dotfile "test.conf" "$TEST_TMPDIR/dest/test.conf" --force

    [ "$status" -eq 0 ]
    [[ "$output" == *"installed from repo"* ]]
    [ "$(cat "$TEST_TMPDIR/dest/test.conf")" = "new content" ]
}

@test "copy_or_download_dotfile applies chmod mode" {
    setup_dotfile_helper

    echo "content" > "$SCRIPT_DIR/dotfiles/test.conf"

    run copy_or_download_dotfile "test.conf" "$TEST_TMPDIR/dest/test.conf" --chmod 600

    [ "$status" -eq 0 ]
    # Check permissions (should be rw-------)
    local perms=$(stat -c %a "$TEST_TMPDIR/dest/test.conf")
    [ "$perms" = "600" ]
}

@test "copy_or_download_dotfile fails gracefully when file not found locally and no network" {
    setup_dotfile_helper

    # No local file, and curl will fail for non-existent GitHub file
    run copy_or_download_dotfile "nonexistent.conf" "$TEST_TMPDIR/dest/nonexistent.conf"

    # Should fail (curl will fail for non-existent file)
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not install"* ]]
}

# =============================================================================
# PATH setup tests (verify environment variables are set correctly)
# =============================================================================

@test "pyenv PATH setup pattern works" {
    # Simulate pyenv already installed
    mkdir -p "$TEST_TMPDIR/.pyenv/bin"
    export PYENV_ROOT="$TEST_TMPDIR/.pyenv"

    # This is the pattern used in install_python_env
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

    # Verify PATH contains pyenv
    [[ "$PATH" == *"$PYENV_ROOT/bin"* ]]
}

@test "nvm PATH setup pattern works" {
    # Simulate nvm directory
    mkdir -p "$TEST_TMPDIR/.nvm"
    export NVM_DIR="$TEST_TMPDIR/.nvm"

    # Create a mock nvm.sh
    echo 'export NVM_LOADED=true' > "$NVM_DIR/nvm.sh"

    # This is the pattern used in install_nodejs_env
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

    # Verify nvm was sourced
    [ "$NVM_LOADED" = "true" ]
}

@test "Go PATH setup pattern works" {
    # Simulate Go installation
    mkdir -p "$TEST_TMPDIR/go/bin"
    export GOROOT="$TEST_TMPDIR/go"
    export GOPATH="$TEST_TMPDIR/gopath"
    export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

    # Verify PATH contains Go
    [[ "$PATH" == *"$GOROOT/bin"* ]]
    [[ "$PATH" == *"$GOPATH/bin"* ]]
}

@test "Bun PATH setup pattern works" {
    # Simulate Bun installation
    mkdir -p "$TEST_TMPDIR/.bun/bin"
    export BUN_INSTALL="$TEST_TMPDIR/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    # Verify PATH contains Bun
    [[ "$PATH" == *"$BUN_INSTALL/bin"* ]]
}

# =============================================================================
# SCRIPT_DIR detection tests
# =============================================================================

@test "SCRIPT_DIR detection with BASH_SOURCE works for local execution" {
    # When script is run locally, BASH_SOURCE[0] should resolve to the script path
    # This test verifies the pattern works

    # Create a test script
    mkdir -p "$TEST_TMPDIR/test_repo"
    cat > "$TEST_TMPDIR/test_repo/test_script.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$SCRIPT_DIR"
EOF
    chmod +x "$TEST_TMPDIR/test_repo/test_script.sh"

    # Run it
    run "$TEST_TMPDIR/test_repo/test_script.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMPDIR/test_repo" ]
}

@test "SCRIPT_DIR fallback needed when script is piped" {
    # When script is piped (curl | bash), BASH_SOURCE[0] may not work correctly
    # This test documents the behavior

    cat > "$TEST_TMPDIR/piped_script.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "/tmp")"
echo "$SCRIPT_DIR"
EOF

    # Simulate piped execution
    run bash < "$TEST_TMPDIR/piped_script.sh"

    [ "$status" -eq 0 ]
    # When piped, SCRIPT_DIR will not be the original location
    # This is expected behavior - the script handles it with GitHub fallback
}
