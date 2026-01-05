# === PERSONAL CONFIGURATION ===

# Claude Code Shortcuts
alias cl="claude --dangerously-skip-permissions"
alias clc="claude --dangerously-skip-permissions -c"

# Claude Code Usage Shortcuts
alias clu="ccusage daily"
alias cluw="ccusage weekly"
alias clum="ccusage monthly"
alias clm="ccusage monthly"

# Development Environment
export EDITOR="code"
export BROWSER="firefox"

# Productivity
alias proj="cd ~/projects"
alias reload="source ~/.zshrc"
alias c="clear"
alias h="history"
alias path='echo -e ${PATH//:/\\n}'

# System Monitoring
alias meminfo="free -m -l -t"
alias psmem="ps auxf | sort -nr -k 4"
alias pscpu="ps auxf | sort -nr -k 3"
alias cpuinfo="lscpu"
alias diskusage="df -H"

# Fast Navigation
personal() { cd ~/projects/personal; }
experiments() { cd ~/projects/experiments; }
thoughts() { cd ~/thoughts; }
scripts() { cd ~/scripts; }
work() {
    case "$1" in
        "personal") cd ~/projects/personal ;;
        "experiments") cd ~/projects/experiments ;;
        "") cd ~/projects ;;
        *) cd ~/projects/"$1" ;;
    esac
}

# SSH Jumphost shortcut (if configured)
if [ -n "$COMPANY_JUMPHOST" ]; then
    alias jumpy="ssh $COMPANY_JUMPHOST"
fi
