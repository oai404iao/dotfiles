# Configure a machine

Machine-local data selects capabilities. `.chezmoi.toml.tmpl` prompts during
initial setup and writes the result to `~/.config/chezmoi/chezmoi.toml`.
`.chezmoiignore` determines which targets are managed for that selection.

For an initialized machine, use:

```sh
chezmoi edit-config
```

Edit `[data]` deliberately. Do not rerun `chezmoi init` just to silence a
template-change warning: it can regenerate the local configuration. Back up
and review that file before any intentional reinitialization.

## Machine data

| Key | Values / initial default | Meaning |
|---|---|---|
| `role` | `desktop`, `laptop`, `server`; `desktop` | Role metadata; also supplies the initial SSH-agent prompt default |
| `shell` | `zsh`, `bash`; `zsh` | Preference only; both trees deploy and the login shell is not changed |
| `graphical` | boolean; `true` | Graphical application configuration and local Pi notifications |
| `niri` | boolean; prompted for graphical machines | Niri session and desktop integration |
| `desktopShell` | `custom`, `dms`; `custom` | Niri desktop owner; missing values retain `custom` |
| `tether` | boolean; `false` | Optional Tether policy for graphical Niri/DMS machines |
| `tetherMode` | `notifications`, `wifi-clipboard`; `notifications` | Tether network and clipboard permissions |
| `niriOutputProfile` | `auto`, `laptop-dual-1080p`, `desktop-single-4k`; `auto` | Output definitions selected at render time |
| `work` | boolean; `false` | Work-machine metadata |
| `sshAgent` | boolean; defaults true except for `server` | rbw-backed SSH client configuration |
| `sshInboundIdentity` | `none`, `private`, `uni`; `none` | Complete `authorized_keys` ownership, or no ownership |
| `secretBackend` | `rbw` | Secret-backend marker written by initialization |

These are non-secret values. Never store credentials in machine data. Prefer
capability flags over hostname-specific behavior when extending the repository.

## Choose the smallest profile

| Need | Selection |
|---|---|
| Headless environment | `graphical = false`, `niri = false` |
| Graphical apps without a managed Niri session | `graphical = true`, `niri = false` |
| Niri with separate bar/launcher/notification components | `graphical = true`, `niri = true`, `desktopShell = "custom"` |
| Niri with DankMaterialShell | Same graphical/Niri flags, `desktopShell = "dms"` |
| iPhone notifications | DMS profile plus `tether = true`; leave `tetherMode = "notifications"` unless wider access is intended |
| Unknown display hardware | `niriOutputProfile = "auto"` |
| SSH client only | `sshAgent = true`, `sshInboundIdentity = "none"` |

Selecting a capability does not install packages, change the login shell,
pair an iPhone, or enable all required services. See the
[Quickstart](quickstart.md) and component guides for preparation.

## Change a deployed profile

1. Back up the current component's configuration and local data privately.
2. Read the migration guide before editing machine data.
3. Run the relevant offline checks, then inspect explicit safe targets.
4. Stop or disable the old component's retained services when the guide requires it.
5. Apply only the reviewed targets and check the new session or process.

Use [desktop switching](desktop-shells.md#switch-an-existing-machine),
[Tether retirement](tether.md#disable-or-change-desktop-profiles), or
[SSH ownership](ssh.md#machine-data) for the affected subsystem. Changing an
ignore condition alone does not remove old files or revoke access.
