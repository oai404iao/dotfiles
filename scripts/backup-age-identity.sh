#!/bin/sh
set -eu

item="chezmoi age identity"
identity=${1:-"${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/age-identity.txt"}

if ! grep -q '^AGE-SECRET-KEY-' "$identity"; then
    printf '%s\n' "invalid age identity: $identity" >&2
    exit 1
fi

if rbw get "$item" >/dev/null 2>&1; then
    grep -m1 '^AGE-SECRET-KEY-' "$identity" | rbw edit "$item" >/dev/null
else
    grep -m1 '^AGE-SECRET-KEY-' "$identity" | rbw add "$item" >/dev/null
fi

local_key=$(grep -m1 '^AGE-SECRET-KEY-' "$identity")
remote_key=$(rbw get "$item")

if [ "$local_key" != "$remote_key" ]; then
    printf '%s\n' "Bitwarden backup verification failed" >&2
    exit 1
fi

unset local_key remote_key
printf '%s\n' "Bitwarden age identity backup verified"
