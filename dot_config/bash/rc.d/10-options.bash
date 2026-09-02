shopt -s autocd
shopt -s checkwinsize
shopt -s histappend

HISTCONTROL="ignoreboth:erasedups"
HISTFILE="$XDG_STATE_HOME/bash/history"
HISTSIZE=10000
HISTFILESIZE=10000

[ -d "${HISTFILE%/*}" ] || command mkdir -p -- "${HISTFILE%/*}"
history -r "$HISTFILE" 2>/dev/null || true
