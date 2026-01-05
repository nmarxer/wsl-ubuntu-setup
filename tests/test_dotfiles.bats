#!/usr/bin/env bats
# BATS tests for dotfiles structure and syntax
# Run with: bats tests/

# Setup
setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
}

# =============================================================================
# Dotfiles existence tests
# =============================================================================

@test "dotfiles directory exists" {
    [ -d "$DOTFILES_DIR" ]
}

@test "zshrc exists" {
    [ -f "$DOTFILES_DIR/zshrc" ]
}

@test "zshrc.d directory exists" {
    [ -d "$DOTFILES_DIR/zshrc.d" ]
}

@test "aliases.zsh exists" {
    [ -f "$DOTFILES_DIR/zshrc.d/aliases.zsh" ]
}

@test "functions.zsh exists" {
    [ -f "$DOTFILES_DIR/zshrc.d/functions.zsh" ]
}

@test "personal.zsh exists" {
    [ -f "$DOTFILES_DIR/zshrc.d/personal.zsh" ]
}

@test "tmux.zsh exists" {
    [ -f "$DOTFILES_DIR/zshrc.d/tmux.zsh" ]
}

@test "tmux.conf exists" {
    [ -f "$DOTFILES_DIR/tmux.conf" ]
}

@test "PowerShell profile exists" {
    [ -f "$DOTFILES_DIR/Microsoft.PowerShell_profile.ps1" ]
}

# =============================================================================
# Zsh syntax validation
# =============================================================================

@test "zshrc has valid syntax" {
    run zsh -n "$DOTFILES_DIR/zshrc"
    [ "$status" -eq 0 ]
}

@test "aliases.zsh has valid syntax" {
    run zsh -n "$DOTFILES_DIR/zshrc.d/aliases.zsh"
    [ "$status" -eq 0 ]
}

@test "functions.zsh has valid syntax" {
    run zsh -n "$DOTFILES_DIR/zshrc.d/functions.zsh"
    [ "$status" -eq 0 ]
}

@test "personal.zsh has valid syntax" {
    run zsh -n "$DOTFILES_DIR/zshrc.d/personal.zsh"
    [ "$status" -eq 0 ]
}

@test "tmux.zsh has valid syntax" {
    run zsh -n "$DOTFILES_DIR/zshrc.d/tmux.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Content validation
# =============================================================================

@test "zshrc sources zshrc.d files" {
    run grep -q "zshrc.d" "$DOTFILES_DIR/zshrc"
    [ "$status" -eq 0 ]
}

@test "zshrc configures Oh My Posh" {
    run grep -q "oh-my-posh" "$DOTFILES_DIR/zshrc"
    [ "$status" -eq 0 ]
}

@test "aliases.zsh defines modern CLI aliases" {
    run grep -q "eza" "$DOTFILES_DIR/zshrc.d/aliases.zsh"
    [ "$status" -eq 0 ]
}

@test "functions.zsh defines mkcd function" {
    run grep -q "mkcd()" "$DOTFILES_DIR/zshrc.d/functions.zsh"
    [ "$status" -eq 0 ]
}

@test "tmux.conf has Catppuccin theme" {
    run grep -q "catppuccin" "$DOTFILES_DIR/tmux.conf"
    [ "$status" -eq 0 ]
}

@test "tmux.conf has Windows clipboard integration" {
    run grep -q "clip.exe" "$DOTFILES_DIR/tmux.conf"
    [ "$status" -eq 0 ]
}

@test "PowerShell profile configures Oh My Posh" {
    run grep -q "oh-my-posh" "$DOTFILES_DIR/Microsoft.PowerShell_profile.ps1"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Security checks
# =============================================================================

@test "no hardcoded secrets in dotfiles" {
    # Check for common secret patterns
    run grep -rE "(password|secret|api_key|token)\s*=" "$DOTFILES_DIR" 2>/dev/null
    # Should find no matches or only comments
    [ "$status" -eq 1 ] || [[ "$output" == *"#"* ]]
}

@test "no private keys in dotfiles" {
    run grep -r "PRIVATE KEY" "$DOTFILES_DIR" 2>/dev/null
    [ "$status" -eq 1 ]
}
