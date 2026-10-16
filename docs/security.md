# Work safely with dotfiles

Treat this repository as public, even when its remote is private. Git stores
configuration intent, not a complete copy of your home or a credential backup.
For ownership categories, see [How it works](how-it-works.md#decide-who-owns-a-file).

## Choose a safe preview

| Target | Review method |
|---|---|
| Explicit, known secret-free configuration | Targeted `chezmoi diff --skip-secrets --exclude=encrypted` |
| Pi `auth.json` | Review the modifier source; never diff the destination |
| Existing Pi `models.json` that might contain keys | Private backup and direct sanitization, not a diff |
| Telegram config | Fake-secret rendering for tests; explicit private apply for deployment |
| Encrypted SSH/Git targets | Trusted no-output validation and source commit review |

`--skip-secrets` skips secret-template rendering. It is not a redaction filter
for credentials already in a destination file. It also does not exclude native
`encrypted_` sources: use `--exclude=encrypted` to omit those.

Avoid whole-Pi-directory diffs. The auth modifier preserves other providers'
keys and OAuth credentials; a successful migration does not make an auth diff
safe. Never print `rbw get` output.

## Keep secrets with their owner

- Keep SSH private keys in native Bitwarden SSH items. Managed selector files
  contain public keys only.
- Keep API-key command references in the Pi auth modifier, not literal keys
  in model configuration. Auth-only apply does not contact rbw.
- Headless Telegram targets contain plaintext credentials because the
  extension cannot resolve commands. They must remain mode `0600` and untracked.
- Never add rendered `auth.json`, the age identity, GPG private keys, keyring
  databases, recovery copies, sessions, or authentication/trust state.

For credential takeover and process caching, follow
[Pi authentication](pi-authentication.md). For key selection and rotation,
follow [SSH](ssh.md).

## Review encrypted changes

Encryption protects metadata from casual disclosure; it does not establish
who authored a replacement file. Anyone with the public age recipient can
create new ciphertext. Review trusted commits and validate real payloads
before applying or publishing changes:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

The validators decrypt into protected temporary directories without printing
the inventory or consulting the vault. Broad decrypted SSH diffs can expose
hostnames, usernames, and public-key correlations.

`rbw-agent` exposes every native SSH key in the active vault. A public
`IdentityFile` plus `IdentitiesOnly yes` limits accidental OpenSSH key
selection, not access by another same-UID process. Do not enable agent
forwarding globally or describe Host rules as vault isolation.

## Back up before takeover

Back up existing targets before forcing ownership. Keep credential-bearing
backups private and outside the Git source. Pi auth backups must also stay
outside the retained agent scratch tree, with directory mode `0700` and file
mode `0600`; use its dedicated procedure rather than a generic scratch backup.

Do not delete ignored files to make the worktree clean. They may contain the
only surviving copy of configuration, secrets, or local changes.

## Use task-local scratch paths

Agent-created scripts, downloads, logs, and intermediate output belong in a
fresh directory below `~/.local/state/agents/tmp/`:

```sh
(
    set -eu
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    task_dir=$(mktemp -d "$scratch_root/task-name.XXXXXXXX")
    printf '%s\n' "$task_dir"
)
```

Capture the printed absolute path and reuse it. Scope `TMPDIR` to that path
for individual commands that support it; do not change the login environment.
Leave task directories in place. Cleanup needs an explicit request for a
specific path. Do not store credentials in retained scratch data.

Never derive cleanup operands from `HOME` or XDG variables after rebinding
them for a test. Existing repository tests have their own isolation/cleanup
contracts; do not rewrite those merely to adopt the agent scratch convention.

Repository scripts may use `/usr/bin/rm -rf` only for an intentionally
disposable directory captured from `mktemp`, with its marker verified
immediately before cleanup. Do not use `git clean -fdx`, `reset --hard`, or
forced checkout to obtain a clean worktree.

## Separate validation from live actions

Offline checks must not contact the real vault, call paid model APIs, send
Telegram notifications, or perform live SSH authentication. Each needs an
explicit user request. Preserve the existing rbw lock state: `rbw lock` and
`rbw stop-agent` affect other programs and are not test cleanup.

Likewise, reading a setup command is not authorization to run it. Package
installs, dependency rebuilds, external refreshes, service changes, and
configuration applies have side effects beyond documentation validation.
Agents must inspect and apply explicit reviewed targets, never an unreviewed
full-HOME `chezmoi apply`, `chezmoi update`, or equivalent operation.

Before making the repository public, follow the separate
[publication procedure](publication.md). Removing a secret from the latest
commit does not remove it from history.
