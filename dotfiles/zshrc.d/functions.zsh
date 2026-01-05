# === USEFUL FUNCTIONS ===

mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.tar)       tar xf $1      ;;
            *.zip)       unzip $1       ;;
            *.7z)        7z x $1        ;;
            *)           echo "Unsupported format" ;;
        esac
    fi
}

killp() { kill -9 $(lsof -t -i:$1); }
groot() { cd $(git rev-parse --show-toplevel); }
fcd() { local dir=$(fd --type d | fzf); [ -n "$dir" ] && cd "$dir"; }
fv() { local file=$(fd --type f | fzf); [ -n "$file" ] && ${EDITOR:-vim} "$file"; }
backup() { cp "$1"{,.bak-$(date +%Y%m%d-%H%M%S)}; }

venv() {
    if [ -d "venv" ]; then
        source venv/bin/activate
    else
        python3 -m venv venv && source venv/bin/activate
    fi
}

docker-nuke() {
    docker stop $(docker ps -aq) 2>/dev/null
    docker rm $(docker ps -aq) 2>/dev/null
    docker rmi $(docker images -q) 2>/dev/null
    docker volume prune -f
    docker network prune -f
    docker system prune -af --volumes
}

clean-node-modules() { find . -name "node_modules" -type d -prune -exec rm -rf '{}' +; }
weather() { curl -s "wttr.in/${1:-}?format=v2"; }
qr() { curl -s "qrenco.de/$1"; }

gitsum() {
    echo "📊 Git Repository Summary"
    echo "========================"
    echo "📁 Repo: $(basename $(git rev-parse --show-toplevel))"
    echo "🌿 Branch: $(git branch --show-current)"
    echo "📝 Commits: $(git rev-list --count HEAD)"
    echo "👥 Contributors: $(git shortlog -sn | wc -l)"
    echo "📅 Last commit: $(git log -1 --format=%cd --date=relative)"
    echo ""
    echo "🔝 Top contributors:"
    git shortlog -sn | head -5
}
