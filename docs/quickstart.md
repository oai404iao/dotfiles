# Quickstart

Set up the repository on a new Arch Linux machine without applying an
unreviewed home-directory configuration. For an existing installation, read
the component's takeover procedure before replacing any files.

This guide includes manual installation, vault access, and deployment steps.
They are actions for the machine owner, not part of offline validation.

## 1. Prepare the host

Install the common tools:

```sh
sudo pacman -S --needed git chezmoi age rbw openssh python bash zsh
```

The configured editor and pager expect `neovim` and `less`. Full source checks
need both Bash and Zsh. Generate `en_US.UTF-8` and `zh_CN.UTF-8` on the host;
the desktop and interactive shells use different locales.

Select dependencies from the annotated [pacman](packages/pacman.txt) and
[AUR](packages/aur.txt) lists. They are references for all profiles, not bulk
install scripts. Third-party `archlinuxcn` packages are marked separately;
alternative font providers can conflict.

Configure GitHub SSH access before cloning with the SSH URL below. This is an
initial access prerequisite; the managed rbw-backed SSH setup comes later.

## 2. Initialize without applying

```sh
chezmoi init git@github.com:oai404iao/dotfiles.git
cd "$(chezmoi source-path)"
```

Do not add `--apply`. Answer the capability prompts, then inspect the generated
`~/.config/chezmoi/chezmoi.toml`. Use the
[machine-data reference](configuration.md#machine-data) to interpret the choices.
For unknown display hardware, keep `niriOutputProfile = "auto"`.

Initialization can fetch declared external resources. It does not install
system packages, change your login shell, or enable desktop services.

## 3. Prepare secrets privately

Configure the local `rbw` client for the intended vault, then run the steps
appropriate for a new device:

```sh
rbw register
rbw login
rbw unlock
rbw sync
./scripts/restore-age-identity.sh
```

Registration is needed only on first use. The restore helper reads the
`chezmoi age identity` item and installs
`~/.config/chezmoi/age-identity.txt` with directory mode `0700` and file mode
`0600`. Never print or commit that identity. The companion
`./scripts/backup-age-identity.sh` explicitly writes and verifies the vault
backup; it is not a test.

Pi needs these credential items, depending on the selected features:

| Feature | Bitwarden item |
|---|---|
| Spiredive model providers | `pi spiredive api key` |
| Krill provider | `pi krill api key` |
| Command Code / Jev | `pi commandcode api key` |
| Headless notifications | `pi telegram bot token`, `pi telegram chat id` |

SSH clients need the native Bitwarden SSH key items described in
[SSH](ssh.md). Use rbw's default one-hour inactivity timeout; see
[agent lifecycle](ssh.md#agent-lifecycle) if this machine overrides it.

## 4. Prepare selected components

| Component | Before its first session |
|---|---|
| Shell | Back up existing entrypoints; prepare [user Node.js](shell.md#user-level-nodejs) if needed |
| Zsh framework | Back up existing trees and review [pinned dependency takeover](zsh.md) |
| Desktop | Install [graphical dependencies](desktop.md) and follow [profile setup](desktop-shells.md) |
| Optional DMS plugins | Review compatibility and the separate [plugin repository](dms-plugins.md); native Dux needs no external launcher |
| Pi | Install Pi ≥ 1.2.0 and Node.js ≥ 22.19; prepare the [notification profile](pi.md#notifications-by-machine-profile) |
| Tether | Follow [manual preparation](tether.md#install-and-prepare-manually); capability selection alone does not install or enable it |

Graphical Pi profiles require a trusted local extension source symlink at
`~/.local/share/pi/extensions/pi-local-notify`. Headless profiles use Telegram
and do not need that checkout. Fully restart Pi after a host upgrade.

## 5. Validate the source

With the restored age identity available:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
git diff --check
```

The suite uses fake vault values and isolated rendering. The explicit private
check also validates real age-encrypted Git/SSH payloads without printing them
or contacting the vault. It does not prove the ciphertext's author is trusted.
Review the source revision too.

See [Development](development.md) for prerequisites and optional checks that
may skip when tools are unavailable. A passing source check is not a live
desktop, notification, or SSH authentication test.

## 6. Adopt reviewed targets

Back up existing destination files before takeover. Follow the
[targeted preview/apply workflow](usage.md#preview-and-apply-one-target) for
each known sanitized component. Do not use a full-HOME apply as a shortcut.

Some targets need a different procedure:

- **Pi auth:** exit active Pi processes, privately back up existing auth data
  outside both the source and retained agent scratch, review the modifier,
  and use the [auth-only apply](pi.md#apply-authentication-references-safely).
  Never diff `auth.json`.
- **Existing Pi models:** do not diff a file that might contain literal keys.
  Follow [direct sanitization](pi.md#credentials).
- **Telegram:** only headless profiles render plaintext credentials. Unlock
  rbw and apply the explicit config using the [Pi guide](pi-authentication.md),
  without displaying a diff.
- **Encrypted Git/SSH:** use the trusted no-output validators and explicit
  targets in [Git](git.md) and [SSH](ssh.md), not decrypted diffs.

`--skip-secrets` does not redact existing credentials, and
`--exclude=encrypted` is needed to exclude native age sources. Read
[Security](security.md) before broad inspection.

## 7. Verify the new environment

Start a new login session. Check the locale in an interactive shell and, on a
graphical machine, the expected font aliases:

```sh
locale
fc-match sans-serif
fc-match monospace
```

Run the font commands only where Fontconfig and the graphical fonts are
installed. Verify each adopted application using its guide; keep old sessions
open during shell or inbound SSH migration until the replacement works.

Continue with [daily maintenance](usage.md),
[machine configuration](configuration.md), or the [documentation index](index.md).
