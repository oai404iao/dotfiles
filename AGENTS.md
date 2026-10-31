# Repository instructions

This is the chezmoi source for a personal Arch Linux environment, not an
application or a backup of `$HOME`. Work from the source root, normally
`~/.local/share/chezmoi`. Treat the repository as public.

These rules load alongside the global Pi instructions and take precedence over
them where both apply. Nothing here is an operating-system sandbox.

## Find the owning source

| Change | Read before working |
|---|---|
| Source naming, ownership, generated vs mutable state | [How it works](docs/how-it-works.md) |
| Machine flags, deployment conditions, new capabilities | [Configuration](docs/configuration.md) |
| Shell environment, Node paths, or Zsh dependencies | [Shell](docs/shell.md), then [Zsh](docs/zsh.md) for external changes |
| Desktop apps, locale, keyring, or output profiles | [Desktop](docs/desktop.md) and its linked task guide |
| Niri custom/DMS switching or DMS integration | [Desktop shells](docs/desktop-shells.md) |
| DMS plugins, overlay, or launcher | [DMS plugin ownership](docs/dms-plugins.md) |
| Tether policy or live setup | [Tether](docs/tether.md) |
| Pi providers, extensions, modifiers, or agents | [Pi](docs/pi.md) and the relevant linked guide |
| Shared skills selection/installer | [Skills](docs/skills.md) |
| Git identity inventory or encrypted routing | [Git](docs/git.md) |
| SSH identities, hosts, or inbound ownership | [SSH](docs/ssh.md) |
| Publishing or rewriting history | [Publication](docs/publication.md) |

Read only the task-relevant guides. The [documentation index](docs/index.md)
is the human navigation entry; detailed procedures belong in their owning
guide rather than being duplicated here. The table is incomplete: for a change
it does not list, pick the guide from that index instead of assuming no rule
applies.

## Preserve ownership

- Edit declarative sources, not installed targets, caches, histories,
  sessions, databases, generated runtime state, or downloaded packages.
- Before adding a target, classify it as declarative configuration, generated
  state, mutable state, or secret material, following
  [who owns a file](docs/how-it-works.md#decide-who-owns-a-file). Add targets
  one at a time; never recursively `chezmoi add` `$HOME`, `.config`, or an XDG
  root.
- Git owns reproducible settings, templates, pins, recipients, and secret
  references. Bitwarden owns credentials and SSH private keys. age owns
  versioned static encrypted metadata. Applications own mutable state.
- `README.md`, `README.zh-CN.md`, `AGENTS.md`, `docs/`, `scripts/`, and `tests/`
  are source-only and must remain listed in `.chezmoiignore`.
- Preserve lockfiles unless explicitly updating dependencies. Do not
  incidentally regenerate `dot_config/nvim/lazy-lock.json`.
- Use a focused development branch and Conventional Commits. Preserve an
  existing dirty worktree; no destructive Git cleanup (`git clean -fdx`,
  `reset --hard`, forced checkout) to obtain a clean tree.
- Keep both READMEs semantically synchronized. Documentation and source
  comments are written in concise English.

## Protect credentials and destination state

Read [Security](docs/security.md) before secret-related previews or takeover.

- `--skip-secrets` does not redact existing destination credentials and does
  not exclude native encrypted sources. Broad status/diff/apply commands must
  also use `--exclude=encrypted`; this still does not make secret-bearing
  destination diffs safe.
- Never diff Pi `auth.json`, even after migration. Its modifier preserves
  other providers' keys/tokens. Never `chezmoi add` it or commit rendered data.
- Never display a diff of an existing Pi `models.json` that might contain
  literal keys. Use the direct-sanitization procedure in
  [Pi authentication](docs/pi-authentication.md).
- Never print `rbw get` output or decrypted SSH/Git inventory. Validate real
  ciphertext with the no-output trusted checks, and review trusted commits:
  anyone holding the public age recipient can create replacement ciphertext.
- Accessing the real vault, calling a paid model API, sending Telegram, or
  running live authentication requires an explicit user request. Offline
  tests must not do these things. Preserve rbw's current lock state; do not
  run `rbw lock` or `rbw stop-agent` as cleanup.
- Inspect and apply explicit reviewed target paths only. Back up an existing
  destination before forcing ownership. Do not run an unreviewed full-HOME
  `chezmoi apply`, `chezmoi update`, or equivalent just to validate changes.
- On initialized machines, do not rerun `chezmoi init` to silence a warning.
  It can rewrite local machine data; back up/review intentionally or use
  `chezmoi edit-config`.
- Ignored files are not disposable. Capability changes usually relinquish
  ownership, not delete targets or stop enabled services.

Agent scratch work uses retained task directories under
`~/.local/state/agents/tmp/`; follow the
[scratch-path procedure](docs/security.md#use-task-local-scratch-paths).
Never store credentials there. Existing tests retain their documented
isolation contracts. Repository scripts may use `/usr/bin/rm -rf` only for a
disposable `mktemp` path whose marker is verified immediately before cleanup;
never derive cleanup operands from rebound HOME/XDG variables.

## Subsystem contracts

### Shell and desktop

- `dot_config/shell/profile.sh` is the shared public POSIX login environment.
  Keep shell-specific completion, options, bindings, and prompts out of it.
  Do not retrieve secrets at startup.
- `dot_config/shell/toolchains.sh` owns XDG/toolchain paths. pnpm is a system
  package; user Node/global tools live under `PNPM_HOME`. Do not restore nvm
  loaders; retirement does not uninstall old runtimes/packages.
- Keep generated Matugen/Waypaper values as `create_` seeds. Change their
  generator/template instead of converting them to overwrite-managed files.
- Niri shared outputs/bindings live in `.chezmoitemplates/niri-{outputs,binds}.kdl`;
  profile files are adapters. Unknown hardware uses `auto`. New output
  profiles require both the initialization choice and shared output template.
- Missing `desktopShell` retains `custom`. In DMS mode preserve `create_empty_`
  Niri fragments, including intentionally empty files. DMS owns later edits.
- Niri starts native Dux Shell with `env -u DMS_SHELL_DIR dms run`; do not also
  enable `dms.service`. The profile selector remains `dms`. Manage only
  `~/.config/dms/settings.json`; the legacy `DankMaterialShell` directory is
  ignored, not migrated or deleted. Review duplicate paths privately before
  deployment. Custom-only files are ignored, not deleted.
- DMS plugin implementations belong to `oai404iao/dms-plugins`. Edit and test
  them in that checkout, not here or in installed packages/read-only shell
  extractions. Native Dux lyrics are the default; keep the legacy overlay out
  of the 2.0 dependency graph. Chezmoi owns integration, never
  plugin/provider enablement, auto-fetch/install, dependency preparation, or
  restarts. Plugin data and generated trees stay ignored. The managed bar uses
  stock widgets only; follow `docs/dms-plugins.md` for retiring the old
  launcher, overlay, and plugins without losing preferences.
- Tether is opt-in for graphical Niri/DMS. Preserve both mode drop-ins and
  local device/runtime fields. `notifications` is the default;
  `wifi-clipboard` deliberately adds network/clipboard access. Verify the
  intended service before using clients, which can auto-start an unsandboxed
  daemon. Disable it explicitly before retiring the profile.
- Desktop keyring activation uses the two managed user D-Bus overrides and
  packaged GNOME Keyring unit/socket. Do not add daemon startup commands,
  change `SSH_AUTH_SOCK`, restart the session bus, or delete keyrings as a fix.
  PAM, service enablement, and migration are manual; data/backups stay unmanaged.

### Pi and skills

- `modify_private_settings.json.tmpl` renders a Python modifier. Preserve
  unknown/runtime keys and replace only declared keys. `graphical` selects
  local notifications or Telegram without deleting the other profile's files.
- Keep model credentials out of `private_models.json`. The auth modifier
  merges API-key command references for `deepseek`, `openai`, `xai`,
  `anthropic`, and `typesafe`, preserving other providers and extra fields.
  Reject managed-provider non-API-key conflicts and malformed, duplicate-key,
  or non-object JSON without exposing credentials.
- Auth apply must not contact rbw. Before targeted apply, exit active Pi
  processes and privately back up existing auth data outside both the source
  and retained agent scratch. Follow the authentication guide. OAuth conflicts
  require explicit user removal, never automatic replacement. Pi caches
  resolved key commands for its process lifetime.
- Pinned npm declarations require Pi ≥ 1.2.0 and Node.js ≥ 22.19. Restart Pi
  after a host upgrade; `/reload` does not update the running SDK. Graphical
  local-notify source symlinks are machine-local, not managed plugin code.
- Keep Pi's hoisted-pnpm `npmCommand`. Settings apply does not rebuild existing
  installs; follow the layout migration without discarding/regenerating the
  machine-local lockfile. `npm/modify_private_pnpm-workspace.yaml` is the sole
  managed npm-state exception: merge exact reviewed approvals, preserve other
  settings. Rebuilds execute dependency code and are not offline checks/hooks.
- Telegram renders plaintext credentials from rbw and must remain mode `0600`.
  `.chezmoiignore` owns mutable/generated exclusions. Update the exact inventory
  in `tests/check-pi.sh` for every added/removed Pi source; add precise ignores
  and assertions for new runtime paths. Disabled packages/config are unmanaged.
- Global Pi instructions are owned by `my_skills/prompts/pi-global-agents.md`,
  published to that repository's `main`. `.chezmoiexternal.toml` fetches with a
  24-hour cache. Do not add a second local source or confuse this root
  `AGENTS.md` with that deployed file; follow the reviewed refresh procedure.
- Skill intent belongs to `scripts/skills.json` and `scripts/install-skills.py`.
  Use `python3 scripts/install-skills.py --dry-run` offline. Real installation
  is an explicit network operation that can replace edits; back up first.
  Apply never installs skills, and manifest removal does not uninstall them.
  Keep downloaded `~/.agents/skills/` and CLI lock state unmanaged; do not
  duplicate skills under Pi configuration.

### Git and SSH

- Keep identity names, addresses, and account-specific GitHub SSH rewrites in
  encrypted Git profiles, not `dot_gitconfig`. Public-facing profiles use
  ID-based GitHub `noreply` addresses; the organization address stays encrypted.
- SSH private bytes must never enter source or rendered targets. Files under
  `~/.ssh/identities/` are public selectors for rbw-agent only.
- Every managed host has one public `IdentityFile` and `IdentitiesOnly yes`.
  Exact Host blocks precede `Host *`; do not add a global IdentityFile.
  Local fragments may add aliases but must not overlap managed ones or use
  `Host *`, because IdentityFile is additive.
- `sshAgent` controls client deployment; `sshInboundIdentity` selects complete
  `authorized_keys` ownership for `private`/`uni`, while `none` is unmanaged.
  Host trust, local fragments, host keys, and server config remain local.
- Register a replacement key remotely before changing its client selector or
  inbound ownership. Keep the encrypted authorized-keys template consistent
  with the selected public key. Keep authenticated access open during migration.
- Run trusted private-config checks before applying or publishing changed Git/SSH
  ciphertext. Host selectors prevent accidental key choice, not same-UID
  access to every key exposed by rbw-agent. Do not enable global forwarding.

## Verify the change

Run `./tests/check-source.sh` and `git diff --check` from the source root, then
follow [Develop and verify](docs/development.md#run-the-complete-checks) for the
targeted checks, optional coverage, and skip reporting. Pi tests must use
`tests/fixtures/pi/bin/rbw`, never the real vault. Use
`CHECK_PRIVATE_CONFIG=1 ./tests/check-git.sh` and/or
`CHECK_PRIVATE_CONFIG=1 ./tests/check-ssh.sh` for changed real ciphertext;
publication requires `CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh` and the
full [publication procedure](docs/publication.md).

When adding capabilities, update the non-secret initialization data, narrow
template/ignore condition, supported-value render coverage, and initialized-
machine migration notes. Do not silently regenerate machine config.
When changing an inventory or invariant, update its domain test intentionally.

Before an authorized commit, follow [Review and commit](docs/development.md#review-and-commit).
Report completed work, checks actually run, skips, and blockers; do not claim
live behavior from static rendering.

## Code and comment style

- Match nearby format. POSIX scripts use `#!/bin/sh` and `set -eu`; Bash-only
  tests use strict mode. Quote path expansions and use `--` before filesystem
  operands. Keep KDL modules numerically ordered.
- JSON must parse strictly without duplicate keys; rendered template output
  must remain valid. Preserve modifier interface contracts and error handling.
- Prefer surgical edits. Do not reformat unrelated files or add dependencies,
  package bootstrap layers, or generated artifacts without task authorization.
- Prefer self-explanatory code. Add/update comments only for non-obvious intent,
  constraints, invariants, ordering, error modes, interface contracts, domain
  rules, or edge-case workarounds. Keep them short, precise, and current.
- Do not restate code, comment unchanged code, add play-by-play/change history,
  ticket numbers or TODO/FIXME status notes, invent constraints, duplicate a
  rule across callers, or leave tombstones/boilerplate. Write clearer code
  instead of a longer comment when possible.
