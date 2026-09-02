setopt auto_cd
setopt extended_glob
setopt interactive_comments

setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt share_history

HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=10000
SAVEHIST=10000

[[ -d "${HISTFILE:h}" ]] || command mkdir -p -- "${HISTFILE:h}"
