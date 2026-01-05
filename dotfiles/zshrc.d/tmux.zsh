# === TMUX AUTO-START ===
# Automatically start tmux when opening a new shell

# Conditions to skip tmux:
# - Already inside tmux
# - Running in VS Code integrated terminal
# - Running in non-interactive mode
# - tmux not installed

if command -v tmux &> /dev/null && \
   [ -z "$TMUX" ] && \
   [ -z "$VSCODE_INJECTION" ] && \
   [ -z "$VSCODE_GIT_ASKPASS_NODE" ] && \
   [[ $- == *i* ]]; then

    # Try to attach to existing session, or create new one
    if tmux has-session -t main 2>/dev/null; then
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main
    fi
fi

# Tmux shortcuts
alias ta="tmux attach -t"
alias tl="tmux list-sessions"
alias tn="tmux new-session -s"
alias tk="tmux kill-session -t"
alias tka="tmux kill-server"
