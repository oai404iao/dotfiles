# Run the local Paseo service

This opt-in systemd **user** service runs the standalone pnpm CLI, not a
Desktop-managed daemon. It listens on `0.0.0.0:6767` (all IPv4 interfaces).
The bundled web UI, outbound relay,
and optional standalone service-proxy listener are explicitly disabled.

## Prepare and deploy

1. Prepare [pnpm and the user Node runtime](shell.md#user-level-nodejs), deploy
   the shared shell profile/toolchains, and explicitly install the CLI:

   ```sh
   pnpm add -g @getpaseo/cli
   command -v paseo
   ```

   The launcher uses `$PNPM_HOME/bin/paseo` and sources the public shared
   `shell/profile.sh`, so Node, provider CLIs, and Pi's XDG paths are available
   without an interactive shell. Installation and updates are manual network
   operations; chezmoi never installs or upgrades Paseo.

2. Run `chezmoi edit-config` on an initialized machine; do not rerun init.
   Set this non-secret value under `[data]`:

   ```toml
   paseo = true
   ```

   New-machine initialization prompts for it; missing `paseo` means disabled.
   No NetBird address configuration or IPv6 listener is required.

3. Before takeover, privately back up any existing launcher/units and
   `~/.local/share/paseo` outside this repository and retained agent scratch. Stop an
   existing CLI/Desktop-managed daemon through its current owner before
   starting this service. Do not use both lifecycle managers for one home.
   Paseo configuration can contain credentials: do not diff or import it.

4. Run the offline check, review the launcher, unit, and shared profile, then apply:

   ```sh
   ./tests/check-paseo.sh
   mkdir -p -- ~/.local/bin ~/.config/systemd/user
   chezmoi diff --skip-secrets --exclude=encrypted \
     ~/.local/bin/paseo-service \
     ~/.config/systemd/user/paseo.service \
     ~/.config/shell/profile.sh
   chezmoi apply --exclude=scripts,encrypted \
     ~/.local/bin/paseo-service \
     ~/.config/systemd/user/paseo.service \
     ~/.config/shell/profile.sh
   ```

5. When ready to start the daemon, as the owning user:

   ```sh
   systemctl --user daemon-reload
   systemctl --user enable --now paseo.service
   ```

   Chezmoi only deploys files: it never enables, starts, or restarts services.
   The service follows the user manager's lifetime. For operation at boot and
   after logout, deliberately enable linger with
   `loginctl enable-linger "$USER"`; this affects all of the account's user
   services. HOME, provider tools, and required credentials must be available
   without interactive login. Vault unlocks are not performed by this service.

## Listeners and security

The daemon binds directly to `0.0.0.0:6767`, including loopback, LAN, NetBird,
and any public IPv4 interface. No TCP forwarder or NetBird dependency is used.
Clients connect to a reachable address of the machine, not `0.0.0.0`.

Before starting, restrict port `6767` with the host firewall to trusted peers
or interfaces. NetBird policies alone do not protect LAN/public interfaces.
Reaching Paseo grants the owning account's agent/terminal authority. For daemon
authentication, set a password locally using `paseo daemon set-password` while
the service is stopped, then start it with systemd. Never place passwords in
chezmoi data, units, or Git. This service does not configure TLS: use NetBird or
another encrypted transport for untrusted networks; a password does not encrypt
traffic. Disabling the web UI does not disable the daemon's HTTP/WebSocket API.

## Ownership and operations

| Path / resource | Owner |
|---|---|
| `~/.local/bin/paseo-service`, `~/.config/systemd/user/paseo.service` | Chezmoi, only when `paseo = true` |
| `~/.local/share/paseo/` | Paseo: config, credentials, identities, sessions, worktrees, logs, and transient locks |
| `$PNPM_HOME` runtime and global package installation | pnpm, unmanaged |
| systemd enablement links and account linger | Explicit local administration |

The service fixes `PASEO_HOME=%h/.local/share/paseo` and overrides listen/web/relay/service-proxy
settings at launch without rewriting `config.json`. Other app/provider settings
and authentication stay application-owned. Use **systemctl**, not
`paseo daemon start/restart`, to control this deployment:

```sh
systemctl --user restart paseo.service
systemctl --user status paseo.service
journalctl --user -u paseo.service -n 50 --no-pager
ss -ltnp 'sport = :6767'
curl --fail http://127.0.0.1:6767/api/health
```

Logs may contain private data; review/redact locally. Expect `0.0.0.0:6767`,
not `[::]:6767`. Verify native-client access from trusted peers and confirm
the firewall rejects access from untrusted peers.
Also check `paseo daemon status` locally. Static checks do not prove runtime
connectivity, provider authentication, logout/reboot behavior, or recovery.

Before backup or restore, stop this deployment and any other owner of the same
home. Keep a private, consistent copy of `~/.local/share/paseo` (including config, credentials,
sessions, and worktrees), external workspace repositories, and provider data.
Exclude only verified transient locks/sockets from restoration. Restore with
the service stopped and matching CLI/provider versions; an older package may
not understand newer application state. Do not restore stale PID/lock files.

## Migrate an existing home

Stop `paseo.service` and any other owner of the old home before migration.
Privately back up the old home, current unit, and shared shell profile outside
Git and retained agent scratch. Move `~/.paseo` to `~/.local/share/paseo` only
when the destination does not exist; never merge two homes. Preserve private
permissions, the server identity, configuration, and `client-password.txt` if
present. Update persisted agent/project paths that point inside the moved home;
repair Git worktree links if managed worktrees contain any.

Apply the reviewed unit and shared profile, reload the user manager, then start
the service. Open a new login shell or source the shared profile so the CLI
exports `PASEO_HOME` too. Verify the reported home, existing data, password
authentication, and listener. Do not leave a compatibility symlink at `~/.paseo`.
For rollback, stop the service and move the current data back before restoring
the old unit/profile; do not overwrite post-migration data with an older backup.

## Disable or retire

First run `systemctl --user disable --now paseo.service` and confirm it is
inactive. Then set `paseo = false` using `chezmoi edit-config`.
Disabling the capability only relinquishes ownership; it does not stop services,
remove old units, delete `~/.local/share/paseo`, or uninstall the global package. Retain data
and private backups; remove obsolete targets only after explicit review.

Upstream contracts: [Configuration](https://paseo.sh/docs/configuration.md),
[Connectivity](https://paseo.sh/docs/connectivity.md), and
[Security](https://paseo.sh/docs/security.md). The offline suite checks rendering,
ownership, launcher environment, and unit syntax, not a running daemon.
