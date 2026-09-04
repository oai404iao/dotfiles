# Shared POSIX login environment. Keep this file public and secret-free.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

export XDG_CONFIG_HOME
export XDG_CACHE_HOME
export XDG_DATA_HOME
export XDG_STATE_HOME

toolchains_profile="$XDG_CONFIG_HOME/shell/toolchains.sh"
if [ -r "$toolchains_profile" ]; then
    . "$toolchains_profile"
fi
unset toolchains_profile

# niri-session may inherit an English interactive shell, so clear category
# overrides before it imports the Chinese login environment.
unset LC_ALL LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT
unset LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME
LANG="zh_CN.UTF-8"
LANGUAGE="zh_CN:zh"
LC_ALL="zh_CN.UTF-8"
export LANG
export LANGUAGE
export LC_ALL

# Keep Pi configuration and mutable sessions in their XDG locations.
: "${PI_CODING_AGENT_DIR:=$XDG_CONFIG_HOME/pi/agent}"
: "${PI_CODING_AGENT_SESSION_DIR:=$XDG_STATE_HOME/pi/agent/sessions}"
export PI_CODING_AGENT_DIR
export PI_CODING_AGENT_SESSION_DIR

case ":${PATH-}:" in
    *":$PI_CODING_AGENT_DIR/bin:"*) ;;
    *) PATH="$PI_CODING_AGENT_DIR/bin${PATH:+:$PATH}" ;;
esac
export PATH

case "${PATH-}" in
    "$HOME/.local/bin" | "$HOME/.local/bin":*) ;;
    *) PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
esac
export PATH

EDITOR="nvim"
VISUAL="$EDITOR"
PAGER="less"
LESS="-R"

export EDITOR
export VISUAL
export PAGER
export LESS

ssh_agent_profile="$XDG_CONFIG_HOME/shell/ssh-agent.sh"
if [ -r "$ssh_agent_profile" ]; then
    . "$ssh_agent_profile"
fi
unset ssh_agent_profile
