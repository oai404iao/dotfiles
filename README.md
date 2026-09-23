# Dotfiles

[English](README.md) | [简体中文](README.zh-CN.md)

Personal Arch Linux configuration managed by
[chezmoi](https://www.chezmoi.io/). The repository supports Bash or Zsh,
graphical Niri machines, headless machines, Neovim, Git, and Pi while keeping
credentials and mutable application state out of Git.

## Highlights

- Machine capabilities are selected during `chezmoi init`.
- Bash and Zsh share one public login environment while keeping interactive
  behavior shell-specific.
- The shared login environment exports `DSH_HOME`, defaulting to
  `$XDG_DATA_HOME/dsh` (`~/.local/share/dsh`) while preserving explicit overrides.
  DSH keeps everything under this single root; its contents stay unmanaged.
  Existing `~/.dsh` data is not migrated automatically. Set overrides in the
  launch environment, not in DSH `.env` files.
- User sessions use Simplified Chinese while interactive shells use a complete
  English locale.
- Proportional UI uses Adwaita Sans, terminals use JetBrainsMono Nerd Font
  Mono, and the status bar uses its Nerd Font Propo variant for icon alignment; Noto fonts
  provide CJK, symbol, and emoji fallback.
- Niri uses modular configuration and selectable output profiles.
- Niri desktops choose a complete `dms` shell or the existing `custom`
  component stack during init. [Profile switching and ownership](docs/desktop-shells.md)
  preserve GUI preferences and keep the two startup paths separate.
- On Niri machines, GNOME Keyring D-Bus activation uses the packaged systemd
  user service; [keyring data and backups stay machine-local](docs/desktop.md#desktop-keyring).
- Matugen and Waypaper generated state is bootstrapped without being reset on
  later applies.
- Satty, btop, Fcitx5 candidate windows, swaylock-effects, and GTK file
  management share the desktop style while preserving input schemes and app state.
- LazyVim configuration includes a lockfile reconstructed from verified local
  plugin checkouts.
- Pi model and Telegram credentials come from Bitwarden through `rbw`.
- Global agent instructions are managed for Pi first, with retained per-task
  scratch directories under `~/.local/state/agents/tmp/` instead of `/tmp`.
- [Global skills](docs/skills.md) use a manifest and manual `npx skills` installer;
  downloaded contents under `~/.agents/skills/` stay outside this repository.
- OpenSSH uses age-encrypted public selectors and host metadata while
  `rbw-agent` keeps private client keys in Bitwarden; Git identity metadata is
  encrypted as well.
- The optional `safeRm` opt-in redirects recursive `rm` to the desktop Trash
  and rejects protected XDG and Pi roots.

## Repository Layout

```text
.
├── .chezmoi.toml.tmpl       # Machine-local data and secret backends
├── .chezmoiignore           # Conditional targets and state exclusions
├── dot_config/
│   ├── shell/, bash/, zsh/  # Shell environment and interactive modules
│   ├── git/, nvim/          # Encrypted Git identities and LazyVim
│   ├── environment.d/       # Locale, input method, and rbw-agent socket
│   ├── fontconfig/, gtk-*/  # User font aliases and GTK defaults
│   ├── niri/, waybar/       # Niri desktop session
│   ├── kitty/, fuzzel/      # Terminal and launcher
│   ├── mako/, matugen/      # Notifications and generated themes
│   ├── waypaper/            # Wallpaper integration
│   └── private_pi/agent/    # Private-mode declarative Pi configuration
├── private_dot_ssh/         # Generic SSH policy and encrypted inventory
├── dot_local/bin/           # User commands, including the optional safe rm wrapper
├── scripts/                 # Source-only age identity helpers
├── tests/                   # Offline source and rendering checks
├── docs/                    # Component-specific operating notes
└── AGENTS.md                # Repository rules for coding agents
```

chezmoi source attributes are part of the design:

- `dot_` produces a leading dot;
- `private_` enforces private permissions;
- `executable_` sets executable mode;
- `create_` only creates an absent target;
- `modify_` transforms and preserves selected existing state;
- `.tmpl` files are rendered with machine-local data.

`README*`, `AGENTS.md`, `docs/`, `scripts/`, and `tests/` are source-only and
are not installed into the destination home.

## Ownership and Security

- **Git** contains reproducible configuration, templates, pinned versions,
  secret references, and age-encrypted SSH/Git identity metadata.
- **Bitwarden (`rbw`)** is the source of truth for credentials and SSH private
  keys used through `rbw-agent`.
- **age** is reserved for static secret files that genuinely need versioning.
- **Each machine** owns GPG private keys, SSH host trust and local fragments,
  caches, histories, databases, sessions, Pi authentication/trust state,
  downloaded packages, and desktop keyring databases and backups.

Treat this repository as public even when its remote is private. Never add a
credential, recursively import `$HOME` or an XDG root, or commit a recovery
backup.

Managed Pi model providers omit API credentials. Each machine stores an
`rbw` command reference in its ignored `auth.json` instead:

```json
{
  "deepseek": {
    "type": "api_key",
    "key": "!rbw get 'pi spiredive api key'"
  }
}
```

Pi resolves the command once per process and keeps the result in memory.
The Telegram extension cannot resolve commands itself, so chezmoi renders its
Bitwarden values into a target file with mode `0600`. Avoid displaying
unfiltered Pi diffs. `--skip-secrets` skips secret templates; it does not
redact a literal credential already present in a destination file or exclude
native encrypted source files. Use `--exclude=encrypted` for broad previews.

## Machine Profiles

`.chezmoi.toml.tmpl` initializes non-secret data in the machine-local chezmoi
config:

| Key | Values | Effect |
|---|---|---|
| `role` | `desktop`, `laptop`, `server` | Machine role metadata |
| `shell` | `zsh`, `bash` | Records shell preference; both configurations are deployed, without changing the login shell |
| `graphical` | boolean | Enables graphical application configuration |
| `niri` | boolean | Enables Niri and desktop session ownership |
| `desktopShell` | `custom`, `dms` | Selects the Niri desktop shell; missing values retain `custom` |
| `niriOutputProfile` | `auto`, named profile | Selects rendered output config |
| `work` | boolean | Work-machine metadata |
| `sshAgent` | boolean | Enables the rbw SSH client and selector files |
| `sshInboundIdentity` | `none`, `private`, `uni` | Selects `authorized_keys` ownership |

Choose `niriOutputProfile = "auto"` for unknown display hardware. Machine data
must not contain credentials.

## Prerequisites

On Arch Linux, install the repository-level tools:

```sh
sudo pacman -S --needed git chezmoi age rbw openssh python bash zsh glib2
```

Both Bash and Zsh are needed for complete source validation; only the selected
shell is needed at runtime. `neovim` and `less` are expected to be installed.
Pi and Node.js are installed separately. Graphical dependencies are listed in
[docs/desktop.md](docs/desktop.md); this repository does not provide a
system-wide package bootstrap. `glib2` supplies the `gio` command used by the
safe-rm test and, when `safeRm` is enabled, by the wrapper.

Both `en_US.UTF-8` and `zh_CN.UTF-8` must be generated on the host. Graphical
font configuration also expects Fontconfig plus the Adwaita, Noto, Noto CJK,
Noto Symbols, Noto Color Emoji, and JetBrains Mono Nerd Font families; the
corresponding Arch packages are listed in [docs/desktop.md](docs/desktop.md).

### User-level Node.js

Install pnpm 12 separately (for example, `pnpm-bin` from the AUR), then use
the shared shell environment and install the user runtime without `sudo`:

```sh
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/toolchains.sh"
pnpm runtime set node 24 -g
pnpm add -g npm@11
```

pnpm itself remains system-package-managed; Node.js and npm/npx live under
`PNPM_HOME` (default: `~/.local/share/pnpm`). Chezmoi manages the environment,
not the downloaded runtimes or global packages.

Both Bash and zsh configurations are managed, regardless of the `shell`
preference. Back up existing `~/.bash_profile`, `~/.bashrc`, `~/.zshenv`,
`~/.config/bash`, and `~/.config/zsh` before a targeted apply. Move an obsolete
`~/.zshrc` into the backup; zsh now reads `~/.config/zsh/.zshrc`.

When migrating from nvm, also back up `shell/toolchains.sh`, `shell/nvm.sh`,
and `bash/rc.d/50-node.bash` / `zsh/rc.d/50-node.zsh` under `~/.config`.
`.chezmoiremove` removes the nvm loaders; new shells discard inherited nvm
runtime paths and variables. Chezmoi does not uninstall nvm or its global
packages: migrate any needed tools before separately removing the system nvm
package and trashing its user runtime directory.
Open a new terminal after applying and verify `command -v node npm pnpm`:
Node/npm should resolve under `$PNPM_HOME/bin`, and pnpm to the system package.

## Bootstrap a New Machine

### 1. Initialize without applying

Configure GitHub SSH access first, then run:

```sh
chezmoi init git@github.com:oai404iao/dotfiles.git
cd "$(chezmoi source-path)"
```

Do not pass `--apply`. Answer the machine-profile prompts and inspect the
generated `~/.config/chezmoi/chezmoi.toml`.

### 2. Prepare Bitwarden and age

Configure the local `rbw` client, then:

```sh
rbw register  # First use on a new device, when required
rbw login
rbw unlock
rbw sync
./scripts/restore-age-identity.sh
```

The helper restores `~/.config/chezmoi/age-identity.txt` from the Bitwarden
item `chezmoi age identity`, with directory mode `0700` and file mode `0600`.
The private age identity must never enter Git.

The Pi setup also expects these Bitwarden items:

- `pi spiredive api key`
- `pi telegram bot token`
- `pi telegram chat id`

SSH client machines expect the native Bitwarden SSH key set described in
[docs/ssh.md](docs/ssh.md). Use rbw's default one-hour inactivity timeout.
Machines with an explicit timeout can restore the default once:

```sh
rbw config unset lock_timeout
```

### 3. Prepare external application dependencies

Pi expects this local checkout:

```text
~/Dev/local/omp/pi-extensions/pi-tree-continue
```

It is intentionally not cloned by chezmoi. Install the selected shell,
desktop, Neovim, and Pi dependencies appropriate for the machine.

### 4. Validate the source

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

The test suite is intended to remain offline. Pi template tests use a fake
`rbw`. When `niri` is installed, its configuration is rendered into isolated
temporary homes and validated. SSH profiles and public selectors are checked
with generated fake data; the explicit trusted check also validates the real
age ciphertext without printing it or contacting the vault. The safe-rm test
combines deterministic fake-command failure cases with real GIO under isolated
HOME/XDG state. It verifies the resulting Trash payload and metadata without
reading or modifying the user's Trash.

### 5. Review and apply

For a new machine with no pre-existing secret-bearing Pi configuration:

```sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted
chezmoi apply --interactive --skip-secrets --exclude=encrypted

rbw unlock
chezmoi apply \
  "$HOME/.config/pi/agent/extensions/pi-telegram-notify/config.json"

CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
chezmoi apply "$HOME/.gitconfig" "$HOME/.config/git"
chezmoi apply "$HOME/.ssh"
```

The first apply excludes secret templates; the targeted command after
`rbw unlock` renders the private Telegram configuration without showing it in
a diff. The remaining commands validate and apply age-encrypted Git and SSH
metadata separately; omit the SSH apply on a profile where both SSH
capabilities are disabled.

Configure Pi's ignored local credentials before the first model request. In
Pi, run `/login` for `deepseek`, `openai`, and `xai`, select API-key
authentication when prompted, and enter this command reference for each:

```text
!rbw get 'pi spiredive api key'
```

Keep `rbw` unlocked until each new Pi process has resolved the command. The
result is cached in that process, so locking `rbw` afterward does not interrupt
it. See [docs/pi.md](docs/pi.md) for lifecycle and recovery details.

For a machine with existing configuration, back it up and adopt one component
at a time:

```sh
chezmoi status --skip-secrets <target>
chezmoi diff --skip-secrets <sanitized-target>
chezmoi apply <reviewed-target>
```

Do not diff an existing Pi `models.json` that might contain a literal key.
Follow the direct sanitization procedure in [docs/pi.md](docs/pi.md). Do not
diff encrypted SSH targets because their decrypted host inventory would be
printed; use the trusted check and targeted apply in [docs/ssh.md](docs/ssh.md).

After applying, start a new login session and verify:

```sh
command -v rm
locale
fc-match sans-serif
fc-match monospace
chezmoi status --skip-secrets --exclude=encrypted
```

The expected `rm` path is `~/.local/bin/rm` when `safeRm` is enabled and
`/usr/bin/rm` otherwise.

## Daily Workflow

```sh
chezmoi git pull -- --autostash --rebase
cd "$(chezmoi source-path)"
./tests/check-source.sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted <sanitized-target>
chezmoi apply <reviewed-target>
```

Unlock `rbw` before applying a changed Telegram template, before a new Pi
process first resolves its model key, and before using an SSH identity through
`rbw-agent`. An already initialized Pi process keeps its resolved key in
memory. Inspect a full rendered secret diff only in a trusted terminal.

When adding configuration, use an explicit file:

```sh
chezmoi add ~/.config/example/config
```

Never recursively add `$HOME`, `.config`, or an XDG root. Mutable state and
secrets belong in `.chezmoiignore` or the appropriate external secret backend.

## Documentation

- [Desktop ownership and dependencies](docs/desktop.md)
- [DMS/custom desktop profiles and switching](docs/desktop-shells.md)
- [Optional recoverable recursive deletion](docs/deletion-safety.md)
- [Pi configuration and credentials](docs/pi.md)
- [SSH identities and rbw-agent](docs/ssh.md)
- [Public repository safety](docs/publication.md)
- [Coding-agent operating guide](AGENTS.md)

Back up or restore the age identity from the source root with:

```sh
./scripts/backup-age-identity.sh
./scripts/restore-age-identity.sh
```
