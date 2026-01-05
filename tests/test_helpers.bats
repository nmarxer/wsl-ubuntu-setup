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
