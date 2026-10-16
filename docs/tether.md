# iPhone integration with Tether

Forward iPhone notifications into DMS over Bluetooth, or deliberately grant
Tether LAN and desktop clipboard access. This is an opt-in capability for
graphical Niri/DMS machines; it is not enabled by selecting DMS alone.

| Mode | Enables | Does not provide |
|---|---|---|
| `notifications` (default) | Bluetooth forwarding with titles/bodies and live DMS notifications | Host IP networking, desktop clipboard, persistent message/contact files |
| `wifi-clipboard` (explicit opt-in) | Bluetooth notifications plus host LAN and desktop clipboard access | A clipboard-only protocol filter; upstream LAN also supports file transfer |

Prepare the [manual prerequisites](#install-and-prepare-manually), then
[opt in](#opt-in-and-ownership), [apply the service policy](#apply-and-enable-the-user-service),
and [pair interactively](#pair-and-verify). Read
[isolation and limitations](#isolation-and-limitations) before choosing a mode.
Wi-Fi clipboard setup is a separate, broader permission grant, not a required
step for Bluetooth notifications.

**Before every Tether CLI/GUI operation, verify that the service is active
with the intended mode.** A client can otherwise auto-start an unsandboxed
daemon. Resolve service failures through systemd first, not through the client.

## Tested setup and prerequisites

Bluetooth forwarding was tested with
Tether **0.2.36**, Arch BlueZ **5.87**, DMS **1.6.2**, and an iPhone 14 on
iOS **27**: BR/EDR, LE, ANCS, and MAP connected, and a real DMS notification
was confirmed. These are tested versions, not a promise about later releases.
[Upstream Tether](https://github.com/zackb/tether) describes notification
mirroring as beta and does not support it on iOS 18 or earlier.

No iOS companion app, Wi-Fi pairing, browser extension, or Avahi service is
needed for this Bluetooth path. An Avahi-unavailable warning concerns Wi-Fi
discovery; do not enable Avahi solely to silence it.

You need the [DMS desktop profile](desktop-shells.md), a reviewed Tether
package with its user/adapter units, system Bluetooth access, and an unlocked
phone for pairing. Package installation, root BlueZ configuration, and service
enablement are manual operations; chezmoi performs none of them.

## Install and prepare manually

### 1. Install the reviewed package and dependencies

Chezmoi does not install packages, modify root configuration, or enable
services. Install a reviewed Tether package separately. The tested AUR
`tether-bin` 0.2.36 package omitted its `libsecret` dependency; install it
explicitly along with the Bluetooth tools:

```sh
sudo pacman -S --needed libsecret bluez-utils bluez-obex
```

### 2. Review the root Bluetooth override

Before changing BlueZ, review `systemctl cat bluetooth.service` and the
source-only `scripts/tether/bluetooth-experimental.conf`. Back up any existing
root-owned destination to a private, retained local backup before overwriting
it. Then, only after review:

```sh
sudo install -d -m 0755 /etc/systemd/system/bluetooth.service.d
sudo install -m 0644 scripts/tether/bluetooth-experimental.conf \
  /etc/systemd/system/bluetooth.service.d/90-tether-experimental.conf
sudo systemctl daemon-reload
sudo systemctl restart bluetooth.service
sudo systemctl enable --now tether-btclass@hci0
```

### 3. Wait for the adapter

The last command enables the package's adapter-class unit; substitute the
actual controller if it is not `hci0`. Bluetooth restart interrupts existing
connections. Wait for the adapter to become ready and check its power state
with `bluetoothctl show`; `bluetoothctl power on` can report `Busy` immediately
after restart. Do not blindly remove bonds as a recovery step.

## Opt in and ownership

`tether` defaults to `false`. New-machine initialization asks about it only
when `graphical=true`, `niri=true`, and `desktopShell="dms"`. On an initialized
machine, back up its chezmoi config and deliberately add the following under
the existing `[data]` section with `chezmoi edit-config`; do not rerun init:

```toml
graphical = true
niri = true
desktopShell = "dms"
tether = true
tetherMode = "notifications" # or "wifi-clipboard"
```

Missing `tetherMode` retains `notifications`; unknown modes are rejected.
The mode is used only while the Tether capability is active. Wi-Fi mode does
not enable calls, AirPods, group messaging, or message/contact retention.

The capability manages only a private Bluetooth-settings modifier, two
mode-dependent service drop-ins, and one exact DMS notification rule. Review
[managed files and private state](#managed-files-and-private-state) before
merging an existing installation; the modifier preserves local pairing/runtime
fields, and apply does not turn a locally disabled connection back on.

## Apply and enable the user service

### 1. Back up and validate

Back up pre-existing Bluetooth settings, DMS settings, and both drop-ins into
a private retained directory outside Git. Review existing settings locally,
and run the offline checks from the source root:

```sh
./tests/check-source.sh
git diff --check
```

The full source check includes Tether; `./tests/check-tether.sh` is available
as a focused alternative during development.

### 2. Stop the daemon and apply only the integration targets

Apply only the reviewed targets, with the daemon stopped while its settings
are merged:

```sh
mkdir -p ~/.config/DankMaterialShell ~/.config/systemd/user/tetherd.service.d
systemctl --user stop tetherd.service
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/tether \
  ~/.config/systemd/user/tetherd.service.d/10-notification-network.conf \
  ~/.config/systemd/user/tetherd.service.d/20-no-clipboard.conf \
  ~/.config/DankMaterialShell/settings.json
systemctl --user daemon-reload
systemctl --user enable --now tetherd.service
systemctl --user is-active --quiet tetherd.service
```

Apply the Tether directory so chezmoi creates its private `0700` parent.
DMS watches `settings.json` and reloads its rules without a restart. Verify
them read-only with `dms ipc call settings get notificationRules`.
A package-provided user unit must exist before enabling it. Do not add a
separate autostart entry or run `tetherd` directly.

### 3. Check the effective policy before client operations

Inspect `systemctl --user cat tetherd.service` and confirm the selected
drop-ins are loaded. A successful `is-active` check alone does not prove the
intended mode or isolation. Review the [mode reference](#isolation-and-limitations)
and repeat [runtime isolation checks](#verify-runtime-isolation) after relevant
unit/package changes.

## Pair and verify

### 1. Start interactive Bluetooth setup

Use an interactive terminal, with the phone unlocked and its Bluetooth
settings open. Check the service before client commands:

```sh
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-setup
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-status
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-devices
```

Select the phone's machine-local address, then run:

```sh
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-pair <phone-address>
```

Replace `<phone-address>`; never store it in repository data. The CLI supports
interactive numeric-code confirmation without a GUI: compare the displayed
code with the phone and accept only if they match. Do not pipe automatic
confirmation into pairing.

### 2. Grant phone notification permissions

In the iPhone's Bluetooth device details, enable **Show System Notifications**
for ANCS and **Show Message Notifications** for MAP. Contact sharing is
optional. If the permission toggles do not appear, upstream's
`tether --bt-solicit` re-advertises ANCS without deleting the bond; check the
service first. If the connection was locally disabled, enable it deliberately
with `tether --bt-enable on`, again only with the service active.

### 3. Confirm real delivery

Verify ANCS/MAP and both Bluetooth bearers with `tether --bt-connection`
(after the service check), then send a real phone notification and confirm
its DMS delivery.

### Verify runtime isolation

For `notifications` mode, verify isolation after each relevant unit/package
change:

```sh
pid=$(systemctl --user show --property=MainPID --value tetherd.service)
test "$pid" -gt 0
readlink /proc/self/ns/net
readlink "/proc/$pid/ns/net"
ss -ltn 'sport = :5134'
```

The namespace identifiers must differ, and the host socket listing must not
contain Tether's listener. If access restrictions prevent inspecting the
daemon namespace, resolve that locally with a reviewed privileged check;
do not treat an unreadable identifier as success. Inspect the service's mount
namespace locally to confirm the compositor socket is hidden. Check that
message/contact files are not being retained; do not print their contents.
Offline tests validate configuration, not actual phone permissions or delivery.

## Enable Wi-Fi and clipboard synchronization

This mode intentionally exposes Tether to the host network and clipboard.
Paired devices can receive sensitive copied text. Use only trusted devices
and networks; the LAN transport also supports file transfer. Bluetooth
`retention=none` is not a guarantee about clipboard storage on the phone.

### 1. Switch both managed drop-ins

Back up the local chezmoi config and both existing drop-ins privately.
Set `tetherMode = "wifi-clipboard"` under `[data]`, keeping `tether = true`.
There is no need to reapply DMS or Bluetooth settings just to switch modes:

```sh
systemctl --user stop tetherd.service
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.config/systemd/user/tetherd.service.d/10-notification-network.conf \
  ~/.config/systemd/user/tetherd.service.d/20-no-clipboard.conf
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/systemd/user/tetherd.service.d/10-notification-network.conf \
  ~/.config/systemd/user/tetherd.service.d/20-no-clipboard.conf
systemctl --user daemon-reload
systemctl --user restart tetherd.service
systemctl --user is-active --quiet tetherd.service
```

Check the effective unit policy before any client operation.

### 2. Prepare trusted LAN discovery

Unlike Bluetooth-only mode, LAN discovery needs Avahi. Inspect existing
Avahi/firewall configuration before deliberately enabling its service:

```sh
sudo systemctl enable --now avahi-daemon.service
```

Install the official
[Tether - Linux Companion](https://apps.apple.com/us/app/tether-linux-companion/id6762097135)
on the iPhone, open it, and allow local-network access. Connect both devices
to the same trusted LAN; the computer may use Ethernet while the phone uses
Wi-Fi. Tether uses TCP 5134 for its mutual-TLS connection and UDP 5353 for
mDNS discovery. If a firewall blocks either, permit only the necessary LAN
traffic after reviewing its policy; do not disable the firewall or forward
these ports from the internet. The upstream listener is not automatically
restricted to one LAN interface.

### 3. Verify and accept the matching device

The App should discover the computer and request pairing. Check the pending
device and fingerprint before accepting the matching request:

```sh
systemctl --user is-active --quiet tetherd.service && tether pending
systemctl --user is-active --quiet tetherd.service && tether accept <fingerprint>
systemctl --user is-active --quiet tetherd.service && tether status
```

Keep certificates, trust records, phone addresses and fingerprints out of Git.
Never accept an unknown device merely because it appears in the pending list.
`tether status` should report clipboard availability and mDNS advertising;
after pairing, verify the phone is connected. Confirm the daemon shares the
host network namespace and can see the active Wayland socket. Test both
clipboard directions with disposable, non-sensitive text, not the user's
existing clipboard.

### 4. Keep the companion app active

The upstream iOS client at the tested revision
[disconnects on entering the background](https://github.com/zackb/tether/blob/v0.2.36/apple/Tether/ViewModels/TetherViewModel.swift#L210-L225)
and resumes discovery/reconnection when active. Keep it in the foreground
for live clipboard synchronization; Background App Refresh does not change
that implementation. Sending selected content through the iOS share extension
is an alternative to opening the main App. Bluetooth notification forwarding
does not depend on keeping the companion App open.

### Return to notification-only mode

To return to notification-only operation, set `tetherMode = "notifications"`,
apply the same two drop-ins, run `systemctl --user daemon-reload`, and restart
the user service, then repeat the isolation checks above.
This closes Tether's host-network listener and removes
clipboard access without deleting Bluetooth bonds or Wi-Fi trust records.
Avahi is a shared system service; switching modes does not stop it automatically.

## Disable or change desktop profiles

If stopping forwarding is desired, first run:

```sh
systemctl --user disable --now tetherd.service
```

Then set `tether=false` (or switch away from the active DMS/Niri profile).
The targets become ignored, not deleted, and changing machine data alone does
not stop the service. Existing drop-ins, local pairing state, and DMS settings
remain on disk. Review retained configuration explicitly before any later
manual service enablement; do not assume an ignored target has been reverted.

## Isolation and limitations

This reference describes the intended service boundary. Unit settings are not
runtime proof: repeat the [isolation checks](#verify-runtime-isolation) after
relevant changes. A manually launched client or GUI is outside this boundary.

### `notifications` (default)

The network drop-in clears the vendor `ExecStartPre` (which runs `pkill`) and
`ExecStart`, then starts:

```ini
ExecStart=/usr/bin/unshare --user --map-current-user --net /usr/bin/tetherd
PrivateUsers=yes
UMask=0077
```

`unshare` is mandatory and fails closed if a new network namespace cannot be
created. On the tested systemd 262 host, `PrivateNetwork` isolation silently
degraded with an `ExecStartPre` namespace failure (`EPERM`); merely reading a
unit's configured flags was not sufficient proof. The restarted daemon was
verified to have a different network namespace from the host and no host
TCP listener on port 5134. BlueZ/system D-Bus and the user Unix socket remain
available; Bluetooth operation does not need the host IP network.

The clipboard drop-in sets `RuntimeDirectory=tether`,
`RuntimeDirectoryMode=0700`, `RuntimeDirectoryPreserve=yes`, and
`WAYLAND_DISPLAY=wayland-0`. It overlays `%t` with `TemporaryFileSystem=%t:rw`,
exposing only `BindPaths=%t/tether` and `BindReadOnlyPaths=%t/bus`.
This hides all runtime-directory compositor sockets, including ones created
after the service starts, while leaving the user bus and Tether's Unix socket
reachable by DMS and the CLI.

Consequently clipboard synchronization, notification actions that copy codes,
and a Wayland GUI launched by the daemon do not work. A manually launched GUI
outside the unit may still work, but is not covered by the service's isolation.
This is a narrowly scoped service policy, not protection from other programs
running as the same user.

### `wifi-clipboard` (explicit opt-in)

The same drop-ins run `/usr/bin/tetherd` directly, without the network/user
namespace or runtime-directory overlays. They retain the cleared vendor
`ExecStartPre`, private runtime directory, and `UMask=0077`. The daemon inherits
the user manager's `WAYLAND_DISPLAY` rather than a fixed socket name.
Tether 0.2.36 also searches runtime-directory Wayland sockets and retries when
the compositor is not yet available.

This mode intentionally gives Tether the host network and clipboard. Paired
devices can exchange clipboard contents, including any sensitive text copied
there; use only trusted devices and networks. The upstream LAN transport also
supports file transfer: this mode is not a clipboard-only protocol filter.
Bluetooth's `retention=none` policy is unchanged, but it is not a promise about
clipboard handling or storage on the phone.

**Before every Tether CLI/GUI operation, verify that the service is active
with the intended mode.** The client can auto-start an unsandboxed daemon when no service is
running. Do not use the CLI to recover a failed service before resolving the
failure.

## Managed files and private state

| Target | Managed policy |
|---|---|
| `~/.config/tether/bluetooth.json` | Private merge; notification forwarding with retention `none` |
| `tetherd.service.d/10-notification-network.conf` | Selected mode's daemon command and host-network policy |
| `tetherd.service.d/20-no-clipboard.conf` | Private runtime directory and selected mode's compositor-socket exposure |
| DMS notification rules | Exact `tether-gtk` rule with `no_history` |

The drop-ins are under `~/.config/systemd/user/`. Both remain managed in both
modes so switching replaces the old policy rather than leaving an ignored
isolation drop-in behind.

The Bluetooth directory is `0700` and its file `0600`. The modifier enables
notification forwarding with titles/bodies and retention `none`; call control,
AirPods management, group messaging, and lock-on-away remain disabled.
Existing `device_address`, `auth_strategy`, `adapter`, `enabled`,
`config_version`, and unknown keys survive. Apply does not enable a connection
that was locally disabled. Invalid known runtime-field types are rejected
because upstream fallback could skip retention.

The DMS modifier consolidates the exact `tether-gtk` selector before broad user
rules. It preserves unrelated rules/preferences but deliberately overrides
conflicting rules matching that selector.

The DMS rule keeps notifications in the live notification center but excludes
them from its historical store. It does **not** purge earlier DMS history.
Tether can still hold MAP messages and contacts in memory; retention `none`
prevents message/contact files, not receipt of that information.
Contact sharing is optional for this notification-only use.

Phone addresses, Bluetooth bonds/authentication, certificates and keys,
store keys, known hosts, message/contact stores, logs, and other runtime state
stay machine-local. Do not recursively add Tether's configuration or state
directories to chezmoi. Notifications contain personal information: inspect
existing Bluetooth/DMS settings locally, not in shared diff logs.

## Troubleshooting and next steps

| Symptom | Safe next step |
|---|---|
| Service fails to start in `notifications` mode | Inspect systemd diagnostics and namespace support; do not use the CLI to spawn a replacement |
| `bluetoothctl power on` reports `Busy` | Wait for adapter readiness after the BlueZ restart; do not delete bonds |
| Phone permission toggles are absent | With the intended service active, use `tether --bt-solicit`; contact sharing remains optional |
| Notifications do not arrive | Check ANCS/MAP, both bearers, and phone permissions, then send a real test notification |
| Avahi warning during Bluetooth setup | No action required for Bluetooth-only forwarding |
| Clipboard actions fail in `notifications` mode | Expected: compositor sockets are hidden; opt into the broader mode only deliberately |
| Wi-Fi app disconnects in the background | Keep it foregrounded or use the iOS share extension; Bluetooth notifications are independent |
| Targets become ignored after disabling | Expected: the service and retained files still require explicit retirement |

`./tests/check-tether.sh` covers mode rendering, modifier preservation/validation,
and source isolation invariants offline. It does not pair a phone, prove a
namespace is active, inspect private message contents, or confirm delivery.
Use `./tests/check-source.sh` and `git diff --check` before a reviewed apply.

Next: [desktop shell switching](desktop-shells.md#switch-an-existing-machine),
[desktop keyring](desktop-session.md#desktop-keyring), or the
[upstream Tether repository](https://github.com/zackb/tether) for application
behavior beyond this integration.
