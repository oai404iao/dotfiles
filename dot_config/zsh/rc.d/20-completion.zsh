zstyle ":completion:*" menu select

typeset completion_cache="$XDG_CACHE_HOME/zsh"
[[ -d "$completion_cache" ]] || command mkdir -p -- "$completion_cache"

autoload -Uz compinit
compinit -d "$completion_cache/zcompdump"

unset completion_cache
