# === MANDATORY ALIASES ===

# Smart navigation (cd is replaced by zoxide)
# cd now learns from your navigation and supports fuzzy matching
# Examples: cd proj → jumps to ~/projects if visited before
alias ..='cd ..'
alias ...='cd ../...'
alias ....='cd ../../..'
alias ~='cd ~'
alias cdi='zi'  # Interactive zoxide selection with fzf

# Modern listings (eza)
alias ls='eza --icons --git'
alias la='eza -a --icons --git'
alias ll='eza -lagh --icons --git --group-directories-first'
alias lt='eza --tree --level=2 --icons'
alias tree='eza --tree --icons'

# File viewing (bat)
alias cat='batcat'
alias less='batcat --paging=always'

# Modern search
alias find='fd'
alias grep='rg'

# System
alias top='btop'
alias du='ncdu'
alias ps='btop'

# Safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Development
alias python='python3'
alias pip='pip3'
alias myip='curl ifconfig.me'
alias ports='netstat -tulanp'
alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'

# Windows Integration
alias winhome='cd /mnt/c/Users/$USER'
alias explorer='explorer.exe'
alias code='code.exe'
