# Pi

Pi uses XDG paths configured by the shared shell profile:

- configuration: `~/.config/pi/agent`
- mutable sessions: `~/.local/state/pi/agent/sessions`

## Managed configuration

chezmoi owns the declarative files required to reproduce the current Pi setup:

- global settings and package declarations
- custom providers and models
- key bindings
- bundled subagent definitions and configuration
- Codex-tool, subagent, and Telegram extension configuration

Files are installed with mode `0600`; `~/.config/pi` remains mode `0700`.
Absolute development paths are rendered from the destination home directory.

The following generated or mutable data is deliberately not managed:

- `auth.json`, `trust.json`, and `models-store.json`
- `npm/`, `git/`, downloaded binaries, and package installation IDs
- `.pi-subagent/` manifests and extension runtime state
- sessions, recovery fragments, caches, and logs

Package declarations in `settings.json` remain the source of truth for
reinstalling Pi packages. npm packages are pinned to their adopted versions.
The enabled local package still requires this checkout at its rendered path:

- `~/Dev/local/omp/pi-extensions/pi-tree-continue`

Disabled packages and their configuration are not managed.

## Credentials

No Pi credential is committed or exported by shell startup files.

Managed `models.json` deliberately omits `apiKey`. Each machine stores the
following command reference under every applicable provider in its ignored
`auth.json`:

```json
{
  "deepseek": {
    "type": "api_key",
    "key": "!rbw get 'pi spiredive api key'"
  }
}
```

Configure `deepseek`, `openai`, `zai`, and `xai` with `/login`, selecting
API-key authentication when Pi offers multiple methods and entering the same
command reference for each. Do not replace the reference with the retrieved
value.

`auth.json` credentials take precedence over `models.json`. Pi resolves an
auth-file command on first use and caches the result for the process lifetime.
Because all four entries use the exact same command, one successful resolution
serves all four providers in that process. The key does not enter the general
login environment or get inherited automatically by unrelated shell tools.

Keep `rbw` unlocked for the first resolution in every new Pi process, including
independently launched subagents. Once resolution succeeds, later `rbw lock`
or expiry of rbw's default one-hour timeout does not revoke the copy held by
that process. Exit Pi to discard it. If the first lookup fails, unlock `rbw`
and restart Pi because failed command results are cached as well.

The Telegram extension does not support command or environment interpolation.
chezmoi renders its private `config.json` from these Bitwarden entries:

- `pi telegram bot token`
- `pi telegram chat id`

Unlock `rbw` before applying the Telegram template, configuring model
credentials, or starting a Pi process that has not resolved its key:

```sh
rbw unlock
```

During the initial takeover, an existing `models.json` can still contain a
literal API key. Do **not** diff that file: back it up, migrate the key to
Bitwarden, and replace it directly with the sanitized managed version:

```sh
chezmoi apply --force ~/.config/pi/agent/models.json
```

Keep that backup outside the chezmoi source with directory mode `0700` and file
mode `0600`. Verify the Bitwarden copy before replacement, then move the backup
to Trash after the migration has been accepted.

After that one-time sanitization, avoid displaying an unfiltered Pi diff
because the rendered Telegram target contains credentials. Use:

```sh
chezmoi diff --skip-secrets ~/.config/pi/agent
chezmoi apply ~/.config/pi/agent
```

Pi's `auth.json` remains unmanaged so `/login` can safely maintain OAuth
credentials without chezmoi overwriting them.
