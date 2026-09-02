typeset -g ZSH="${ZSH:-$HOME/.oh-my-zsh}"
typeset -g ZSH_CACHE_DIR="$XDG_CACHE_HOME/oh-my-zsh"
typeset -g ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

command mkdir -p -- "$ZSH_CACHE_DIR" "${ZSH_COMPDUMP:h}"

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    z
    extract
    tmux
)

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
    source "$ZSH/oh-my-zsh.sh"
else
    zstyle ":completion:*" menu select
    autoload -Uz compinit
    compinit -d "$ZSH_COMPDUMP"
fi
