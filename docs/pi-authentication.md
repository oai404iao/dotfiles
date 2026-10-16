# Pi authentication

The repository stores provider endpoints and secret-manager command references,
not resolved API keys. Use this page when adopting an existing Pi installation,
changing credentials, or diagnosing a failed lookup. For models and defaults,
see [Pi configuration](pi.md#defaults-and-model-reference).

## Credential ownership

| Item | Owner and behavior |
| --- | --- |
| `models.json` | Declarative metadata; deliberately omits `apiKey`. |
| `auth.json` | Private machine-local credentials, with five managed command references merged in. |
| Provider keys | Bitwarden entries accessed by `rbw` on first use. |
| Telegram `config.json` | Headless-only template; resolved credentials are written to a private file. |
| Shell startup | Exports paths, never provider credentials. |

The executable [`modify_private_auth.json`](../dot_config/private_pi/agent/modify_private_auth.json)
merges entries with `"type": "api_key"` and these exact `key` references:

| Provider | Command reference |
| --- | --- |
| `deepseek` | `!rbw get 'pi spiredive api key'` |
| `openai` | `!rbw get 'pi spiredive api key'` |
| `xai` | `!rbw get 'pi spiredive api key'` |
| `anthropic` | `!rbw get 'pi krill api key'` |
| `typesafe` | `!rbw get 'pi commandcode api key'` |

For example, the managed part of one entry is:

```json
{
  "deepseek": {
    "type": "api_key",
    "key": "!rbw get 'pi spiredive api key'"
  }
}
```

Apply installs references without contacting `rbw`. It replaces only `type`
and `key` for these providers, preserving extra API-key fields such as `env`
and every unrelated provider/value, including OAuth credentials. The target
is mode `0600`. Only the modifier belongs in Git: never `chezmoi add auth.json`,
commit rendered authentication data, or substitute retrieved key values.

Anthropic uses its separate Krill credential; Command Code's Jev classifier
needs a Command Code key, not a direct TypeSafe key. Neither uses Spiredive's key.

## Apply authentication references safely

**Never display or capture an `auth.json` diff**, even with `--skip-secrets`.
The modifier preserves unrelated secrets, so its output is not safe to preview.
The same prohibition applies to the rendered Telegram target. Do not diff or
apply the whole Pi directory.

1. Exit every active Pi process using this agent directory. Otherwise Pi and
   chezmoi can write authentication state concurrently.
2. Privately back up the existing target outside the chezmoi source **and outside
   `~/.local/state/agents/tmp/`**. Use directory mode `0700` and file mode
   `0600`; do not print or log the contents. Retained agent scratch is not a
   credential backup location.
3. Review the modifier source and run `./tests/check-pi.sh`. Its synthetic
   credentials test merge/rejection behavior without the real vault.
4. Apply only the authentication target:

   ```sh
   chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/auth.json
   ```

5. Restart Pi. Unlock `rbw` before its first provider-key resolution.

Applying this target itself does **not** require an unlocked vault.

### Resolve a rejected input

An existing managed-provider entry with a type other than `api_key` is a
conflict. The modifier fails without emitting replacement JSON or overwriting
the target; it never silently converts OAuth. If you explicitly choose to
replace that login, remove it yourself, for example with the provider selected
in Pi's `/logout`, then exit Pi before applying again.

Malformed, duplicate-key, non-object, or non-finite JSON is also rejected
without echoing credential-bearing input. Repair deliberately from the private
backup; do not discard unrelated credentials to make the modifier succeed.

## Understand first-use caching

Stored `auth.json` credentials take precedence over `models.json`. Pi resolves
an auth-file `!command` when first needed and caches successful **and failed**
results for the process lifetime. The identical Spiredive command serves all
three of its providers after one successful resolution; Krill and Command Code
resolve independently.

Keep `rbw` unlocked for that first lookup in each new Pi process, including
independently launched subagents. A later `rbw lock`, or rbw's default one-hour
timeout, does not revoke an already cached key. Exit Pi to discard the copy.
If the first lookup fails, unlock `rbw` and restart Pi; retrying inside the same
process will reuse the failure. Keys are not exported into the general login
environment or automatically inherited by unrelated shell tools.

```sh
rbw unlock
```

This is a live vault operation. Do not print `rbw get` output or use Pi's
credential-printing commands as a diagnostic. The upstream
[provider reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md#load-an-api-key-from-a-command)
describes command caching; commands in `models.json` have a different,
request-time contract and are not used here.

## Adopt a legacy model file containing a key

An unmanaged or pre-takeover `models.json` may contain literal credentials.
`--skip-secrets` does not redact existing destination content: **do not diff it**.

1. Make the same private, restricted backup described above, outside source
   and retained agent scratch.
2. Migrate the key to Bitwarden and verify that copy before replacement.
3. Review the sanitized model source, then replace the explicit target:

   ```sh
   chezmoi apply --force --exclude=scripts,encrypted ~/.config/pi/agent/models.json
   ```

4. Use the separate authentication workflow for command references. After the
   migration is accepted, move the old credential-bearing backup to Trash.

Do not force ownership before the backup and verified Bitwarden copy exist.

## Render headless Telegram credentials

Only `graphical = false` selects Telegram. The extension does not support
command or environment interpolation, so chezmoi retrieves these entries when
rendering `~/.config/pi/agent/extensions/pi-telegram-notify/config.json`:

- `pi telegram bot token`
- `pi telegram chat id`

For an authorized headless setup, privately back up that existing target,
unlock `rbw`, and apply only the explicit file without displaying a diff:

```sh
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/pi/agent/extensions/pi-telegram-notify/config.json
```

The rendered file contains plaintext credentials and must remain mode `0600`.
Graphical profiles ignore the directory without deleting an existing file;
their Pi configuration apply does not retrieve Telegram credentials.
See [notification switching](pi-packages.md#notifications-by-machine-profile)
for the accompanying settings change and delivery limits.

## What the checks establish

`tests/check-pi.sh` tests five-provider merging, private permissions, idempotence,
invalid-input rejection, conflict preservation, and isolated apply without
vault access. It renders Telegram with `tests/fixtures/pi/bin/rbw`, never the
real vault. It does not verify real keys, send notifications, or make paid
model requests. Those operations require explicit authorization.
