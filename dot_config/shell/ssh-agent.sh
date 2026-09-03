# Preserve a forwarded or explicitly selected agent.
if [ -z "${SSH_AUTH_SOCK-}" ] && [ -n "${XDG_RUNTIME_DIR-}" ]; then
    SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/rbw/ssh-agent-socket"
    export SSH_AUTH_SOCK
fi
