# AGENTS.md - Personal Chezmoi Dotfiles

> Context for AI coding agents working on this repository. Read this before making changes.

## What Is This Repository?

This is the chezmoi source state for a personal Arch Linux environment. It
manages shell, Git, Neovim, Niri desktop, terminal, and Pi configuration across
desktop, laptop, and server roles. It is a configuration repository rather
than an application: changes are rendered by chezmoi into the destination
home directory and are validated with repository scripts.

Treat the repository as public and respect the ownership boundaries below.

## Repository Layout

```text
.
|-- .chezmoi.toml.tmpl       # Generates machine-local chezmoi data and secret backends
|-- .chezmoiignore           # Machine conditions plus generated/state exclusions
|-- .chezmoiversion          # Minimum compatible chezmoi version
|-- private_dot_ssh/         # Generic config plus age-encrypted SSH inventory
|-- dot_config/
|   |-- shell/               # Shared POSIX login/session environment
|   |-- bash/ and zsh/       # Shell-specific interactive configuration
|   |-- git/                 # Path-specific identities and global ignores
|   |-- nvim/                # LazyVim bootstrap and locked plugin revisions
|   |-- niri/                # Modular Niri config and output-profile template
|   |-- waybar/              # Bar config and guarded helper scripts
|   |-- kitty/, fuzzel/      # Terminal and launcher configuration
|   |-- mako/, matugen/      # Notifications and generated theme templates
|   |-- waypaper/            # Wallpaper state bootstrap and theme hook
|   `-- private_pi/agent/    # Private-mode declarative Pi configuration
|-- dot_local/bin/
|   `-- executable_rm        # Recoverable recursive-removal wrapper
|-- run_once_before_disable-swayidle-service.sh.tmpl
|                            # Transfers swayidle ownership to Niri once
|-- scripts/                 # Source-only age identity backup/restore helpers
|-- tests/                   # Source, Niri, SSH, safe-rm, and Pi checks
`-- docs/                    # Configuration and publication operating notes
```

Root `dot_*` files map to home-directory files such as `~/.zshenv` and
`~/.gitconfig`. `README.md`, `README.zh-CN.md`, `AGENTS.md`, `docs/`,
`scripts/`, and `tests/` are source-only and must remain listed in
`.chezmoiignore`.

## Workspace / Package Rules

- Run repository commands from the source root, normally
  `~/.local/share/chezmoi`.
- This is not a monorepo and has no repository-wide package bootstrap or build
  command. System packages are installed separately; individual helpers may
  manage their own dependencies.
- Do not edit caches, downloaded plugins, package installations, histories,
  sessions, databases, or generated runtime state into source control.
- Preserve lockfiles unless the task explicitly updates dependencies. In
  particular, do not regenerate `dot_config/nvim/lazy-lock.json` incidentally.
- Pi npm declarations in `modify_private_settings.json` are pinned. The local
  `~/Dev/local/omp/pi-extensions/pi-tree-continue` checkout is an external
  prerequisite and is not cloned by chezmoi.
- Use a focused development branch and Conventional Commits. Do not mix
  unrelated changes or overwrite an existing dirty worktree.
- Keep `README.md` and `README.zh-CN.md` semantically synchronized.
- Add targets one at a time after classifying them. Never recursively
  `chezmoi add` `$HOME`, `.config`, or an XDG root.
- Do not use destructive Git cleanup (`git clean -fdx`, `reset --hard`, or
  forced checkout) to obtain a clean worktree.

## Chezmoi Source Conventions

| Source pattern | Destination behavior |
|---|---|
| `dot_name` | Writes `.name` |
| `executable_name` | Writes `name` with executable mode |
| `private_name` | Writes `name` with private permissions |
| `create_name` | Creates `name` only when it does not already exist |
| `modify_name` | Transforms the existing target; stdin is old content |
| `name.tmpl` | Renders a Go template before applying |
| `run_once_before_*` | Runs once, before target updates |

Prefixes can be combined. Do not rename an attributed source file without
checking the resulting target path and mode with `chezmoi target-path` and
`chezmoi status`.

Machine-local data comes from `.chezmoi.toml.tmpl`. Conditional deployment is
implemented in `.chezmoiignore`; currently `shell`, `graphical`, `niri`, and
`niriOutputProfile` materially affect rendered targets. Prefer capability
flags over hostname checks.

## Build, Test & Development Commands

```bash
# Canonical complete source validation
./tests/check-source.sh

# Targeted checks
./tests/check-niri.sh
./tests/check-safe-rm.sh
./tests/check-pi.sh
./tests/check-git.sh
./tests/check-ssh.sh
./tests/check-public.sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh

# Patch hygiene
git diff --check
git diff --cached --check

# Inspect status for an explicit target
chezmoi status --skip-secrets --exclude=encrypted <target>

# Diff only a sanitized target known not to contain plaintext credentials
chezmoi diff --skip-secrets --exclude=encrypted <target>

# Apply only a reviewed target
chezmoi apply <target>
```

`check-source.sh` always checks shell syntax, Git config parsing, all
locally reachable public history plus pending files, SSH, safe-rm, and Pi
configuration. Neovim checks run when `nvim` is installed; Niri rendering and
validation run when both `chezmoi` and `niri` are installed.

`check-safe-rm.sh` creates marked temporary directories, performs a real GIO
Trash round trip, restores its test item, and cleans only captured marked
paths. `check-pi.sh` renders the Telegram template with
`tests/fixtures/pi/bin/rbw`; it must never contact the real vault.

These checks are intended to be offline. Accessing the real vault, calling a
paid model API, or sending a Telegram notification requires an explicit user
request, and returned credential values must never be printed.

## Architecture

### Configuration Flow

```text
Git source state
  + machine data from ~/.config/chezmoi/chezmoi.toml
  + rbw/age references where required
  -> chezmoi template, create, or modify semantics
  -> reviewed target files under $HOME
  -> applications create local mutable state outside source control
```

### Ownership Boundaries

- **Git:** reproducible configuration, templates, pinned versions, public
  recipients, and credential references.
- **Bitwarden/rbw:** SSH private keys, Pi model key, Telegram credentials, and
  the backed-up age identity.
- **age:** SSH public selectors, host/user mappings, and other static encrypted
  files that genuinely need versioning; never commit the identity.
- **Per-machine state:** legacy SSH migration copies, GPG private keys, SSH
  host trust, Pi auth/trust/session data, editor state, caches, logs, and
  downloaded packages.

## Core Patterns

### Shell Selection

`.chezmoiignore` deploys exactly one shell-specific tree while retaining
`dot_config/shell/profile.sh` as the shared public environment. Do not move
shell-specific completion, options, bindings, or prompts into the shared
profile, and do not retrieve secrets during shell startup.

### Generated Desktop State

Matugen color outputs and Waypaper state use `create_` files so a fresh machine
gets a valid fallback without later applies reverting application-generated
values. Change the generator/template when appropriate; do not convert these
targets to ordinary overwrite-managed files without an explicit requirement.

### Niri Profiles

`dot_config/niri/config.kdl` includes ordered `conf.d` modules.
`20-outputs.kdl.tmpl` is the source of truth for named output profiles. Unknown
hardware should use `auto`. When adding a profile, update both the choice list
in `.chezmoi.toml.tmpl` and the output template, then run `check-niri.sh`.

### Pi Configuration

- `modify_private_settings.json` is executable Python stored under a chezmoi
  modifier name. It must preserve unknown/runtime keys while replacing only
  declared keys.
- `private_models.json` stores Pi command references such as
  `!rbw get 'pi spiredive api key'`, never a literal key.
- Telegram config is rendered from `rbw` because the extension does not support
  command interpolation. The destination contains plaintext credentials and
  must remain mode `0600`.
- `.chezmoiignore` is authoritative for Pi mutable/generated state.
- `tests/check-pi.sh` uses an exact managed-file inventory. Update that
  inventory intentionally whenever a Pi source file is added or removed.
- Disabled Pi packages and their configuration are not managed.

### Git Identities

- `dot_gitconfig` contains only public behavior and includes the encrypted
  default identity plus encrypted path-specific profiles.
- Names, email addresses, and account-specific GitHub SSH rewrites must stay in
  `encrypted_private_dot_gitconfig-*.age`.
- Public-facing identities use ID-based GitHub `noreply` addresses; the
  organization profile may retain its required address inside ciphertext.
- Update `tests/check-git.sh` when changing the profile inventory or schema,
  and run the trusted private-config check before applying new ciphertext.

### SSH Identities

- Bitwarden native SSH key items are the source of truth for client private
  keys; private key bytes must never enter the repository or a rendered target.
- Encrypted sources under `private_dot_ssh/` contain public selectors and real
  host/user mappings. Target files under `~/.ssh/identities/` contain only the
  decrypted public selectors used by `rbw-agent`.
- Every managed host uses one public `IdentityFile` and `IdentitiesOnly yes`.
  Exact host blocks precede `Host *`. Local fragments may add new aliases but
  must not overlap managed aliases or use `Host *`, because `IdentityFile` is
  additive.
- `sshAgent` controls client deployment. `sshInboundIdentity` selects complete
  `authorized_keys` ownership for `private` or `uni`; `none` leaves the target
  unmanaged.
- `known_hosts*`, local config fragments, host keys, and server configuration
  remain machine-local.
- SSH tests generate fake keys and hosts offline. Before applying or publishing
  changed ciphertext, run `CHECK_PRIVATE_CONFIG=1 ./tests/check-ssh.sh` to decrypt
  and validate the real payload without printing it.
- Accessing the real vault or running a live authentication check requires an
  explicit user request.
- Preserve the existing rbw lock state during checks. Never use `rbw lock` or
  `rbw stop-agent` as test cleanup because other programs share the agent.

### Recoverable Removal

`dot_local/bin/executable_rm` delegates non-recursive removal to
`/usr/bin/rm`, but recursive removal must pass full preflight and use GIO Trash.
Do not weaken protected-root checks or add a permanent-delete fallback.

Repository scripts may call `/usr/bin/rm -rf` only for an intentionally
disposable directory whose path was captured from `mktemp` and whose marker is
verified immediately before cleanup. Never derive cleanup paths later from
ambient `HOME` or XDG variables.

## Gotchas

### 1. A Diff Can Leak Existing Pi Credentials

`--skip-secrets` prevents secret-template rendering, but an existing unmanaged
or pre-takeover `models.json` can itself contain a literal key. Do not display
or capture a Pi diff until such a file has been backed up privately, its value
has been verified in Bitwarden, and the sanitized target has been applied
directly. `--skip-secrets` is not a redaction filter for destination content.
Never print `rbw get` output.

### 2. Do Not Run an Unreviewed Full Apply

Agents must inspect and apply explicit target paths. Back up a pre-existing
target before forcing ownership. Do not run `chezmoi apply`, `chezmoi update`,
or equivalent full-HOME operations merely to validate a source change.

### 3. Do Not Rebind XDG Roots Around Cleanup

The repository exists because temporary `HOME`/XDG scoping once turned a
cleanup command into removal of real configuration and state roots. Capture a
specific temporary path, validate its marker, and clean that path only. Never
construct cleanup operands from ambient XDG variables after changing them.

### 4. `chezmoi init` Regenerates Local Configuration

On a fresh machine, `chezmoi init` is expected. On an initialized machine, do
not run it blindly to silence a template-change warning: it can rewrite
`~/.config/chezmoi/chezmoi.toml`. Back up and review the generated diff first,
or edit machine data deliberately with `chezmoi edit-config`.

### 5. Pi State Is Not Declarative Configuration

Do not add `auth.json`, `trust.json`, `models-store.json`, installation IDs,
sessions, package directories, logs, manifests, or disabled-extension state.
When an extension creates a new runtime path, add a precise ignore and a
corresponding assertion in `tests/check-pi.sh`.

### 6. Ignored Files Are Not Disposable

`.gitignore` and `.chezmoiignore` protect worktrees, recovery copies, and
machine-local secrets. Do not use `git clean -fdx` or another broad cleanup;
ignored content can be the only remaining copy of data.

### 7. SSH Selection Is Not Agent Isolation

`rbw-agent` exposes every native SSH key in the active vault.
`IdentityFile <public-key>` with `IdentitiesOnly yes` prevents accidental key
selection, but another same-UID process can still request signatures. Never
enable agent forwarding globally or claim that Host rules isolate vault keys.

### 8. Encrypted SSH Diffs Reveal the Inventory

`--skip-secrets` does not exclude native encrypted source files, and a diff can
print decrypted public keys, addresses, and usernames. Broad status/diff/apply
commands must add `--exclude=encrypted`; review SSH ciphertext with the
no-output trusted validator and apply only explicit targets. The public age
recipient permits anyone to create replacement ciphertext, so encryption does
not replace trusted commit review.

## Adding or Changing Managed Configuration

1. Classify the target as declarative configuration, generated state, mutable
   state, or secret material.
2. For mutable state or unversioned secrets, add a precise ignore instead of a
   managed file.
3. Choose the correct chezmoi attributes and machine conditions.
4. Update the domain test when its inventory, profile set, or invariant
   changes.
5. Run `./tests/check-source.sh` and `git diff --check`.
6. Scan the source diff for credentials or machine-local state.
7. Preview only an explicit, sanitized destination with `--skip-secrets` and
   `--exclude=encrypted`.
   For Pi or another target that may already contain credentials, follow its
   documented direct-sanitization workflow instead of diffing.
8. Back up an existing destination before a reviewed targeted apply.

## Common Workflows

### Add a Machine Capability

1. Add a non-secret prompt/data key to `.chezmoi.toml.tmpl`.
2. Consume it in a narrow template or `.chezmoiignore` condition.
3. Add render coverage for every supported value.
4. Document migration for already initialized machines; do not silently
   regenerate their config.

### Change Pi Providers or Extensions

1. Update the declarative source, never the target's mutable files.
2. Use an `rbw` command reference or template lookup rather than a literal.
3. Keep npm versions pinned and external local paths explicit.
4. Update `tests/check-pi.sh` inventory and invariants.
5. Test offline/fake-secret rendering before any expressly requested live test.

### Change SSH Identities or Hosts

1. Keep private keys in native Bitwarden SSH items and commit only age
   ciphertext for public selectors and real host inventory.
2. Assign each exact host to one selector; do not add a global `IdentityFile`.
3. Register a replacement public key remotely before changing client config or
   fully managed `authorized_keys`.
4. Keep the encrypted `authorized_keys` template consistent with the
   `private` and `uni` selector files.
5. Run `CHECK_PRIVATE_CONFIG=1 ./tests/check-ssh.sh` before applying or
   publishing.
6. Run offline checks before any expressly requested live authentication.

### Commit a Change

1. Confirm the branch and worktree are appropriate and clean of unrelated work.
2. Stage only task-related paths; note that the user's global Git ignore may
   ignore newly created `AGENTS.md` files.
3. Review `git diff --cached` and run `git diff --cached --check`.
4. Use a focused Conventional Commit such as
   `docs(agents): add repository operating guide`.

### Publish the Repository

1. Follow `docs/publication.md`; deleting plaintext only at the tip is
   insufficient.
2. Run `CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh` against the rewritten
   history.
3. Prefer a new empty remote over changing an old private remote directly to
   public.
4. Verify a fresh clone before changing visibility or announcing the remote.

## Key Files Quick Reference

| What | Where |
|---|---|
| Human overview and bootstrap | `README.md` |
| Machine-data source | `.chezmoi.toml.tmpl` |
| Conditional and state exclusions | `.chezmoiignore` |
| Full validation entry point | `tests/check-source.sh` |
| Desktop ownership and dependencies | `docs/desktop.md` |
| Recursive-removal contract | `docs/deletion-safety.md` |
| Pi ownership and credential flow | `docs/pi.md` |
| Pi settings source of truth | `dot_config/private_pi/agent/modify_private_settings.json` |
| Pi managed-inventory assertions | `tests/check-pi.sh` |
| SSH operations and migration | `docs/ssh.md` |
| Encrypted SSH inventory | `private_dot_ssh/` |
| SSH rendering assertions | `tests/check-ssh.sh` |
| Publication gates | `docs/publication.md`, `tests/check-public.sh` |
| Niri output profiles | `dot_config/niri/conf.d/20-outputs.kdl.tmpl` |
| Safe recursive removal | `dot_local/bin/executable_rm` |
| Age identity helpers | `scripts/backup-age-identity.sh`, `scripts/restore-age-identity.sh` |

## Code Style

- Match the existing language and file format; documentation and source
  comments are written in concise English.
- POSIX shell scripts use `#!/bin/sh` with `set -eu`. Bash-only tests use strict
  mode; the safe-rm wrapper uses explicit failure checks instead of `errexit`.
- Quote path expansions and use `--` before filesystem operands.
- JSON must parse strictly without duplicate keys. Keep template output valid
  after rendering.
- Keep KDL modules ordered by their numeric prefix.
- Prefer small, surgical edits. Do not reformat unrelated configuration.
- Do not add a dependency, package bootstrap layer, or generated artifact
  unless the task explicitly requires it.

## Code Comments Rules (Strict)

- Prefer self-explanatory code through clear naming and structure. Comments are secondary.
- ONLY add or update comments when the logic is **not self-evident**.
- Comment these things (and only these):
  - Non-obvious intent and design decisions (the "why")
  - Important constraints, invariants, ordering requirements, and error modes
  - Interface/usage contracts that prevent plausible misuse
  - Business rules or domain constraints that cannot be expressed in code alone
  - Non-obvious edge cases or workarounds (with brief reason)
- Do NOT:
  - Restate what the code obviously does
  - Add comments to code you did not change
  - Write play-by-play, change history, ticket numbers, or "TODO/FIXME" status notes
  - Invent undocumented behavior or constraints
  - Repeat the same fact across callers and implementations (keep each fact at its owning interface)
  - Leave tombstones, removed-code explanations, or boilerplate
- Keep comments short, precise, and up-to-date. Outdated comments are worse than no comments.
- When in doubt, write clearer code instead of a longer comment.
