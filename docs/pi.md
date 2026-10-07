# Pi

Pi uses XDG paths configured by the shared shell profile:

- configuration: `~/.config/pi/agent`
- mutable sessions: `~/.local/state/pi/agent/sessions`

## Managed configuration

chezmoi owns the declarative files required to reproduce the current Pi setup:

- global settings and package declarations
- global agent instructions (`AGENTS.md`)
- custom providers and models
- key bindings
- user-maintained subagent definitions and configuration
- Codex-tool, subagent, and Telegram extension configuration

Files are installed with mode `0600`; `~/.config/pi` remains mode `0700`.

The following generated or mutable data is deliberately not managed:

- `auth.json`, `trust.json`, and `models-store.json`
- `npm/`, `git/`, downloaded binaries, and package installation IDs
- `.pi-subagent/` manifests and extension runtime state
- sessions (including `<rootSessionId>.subagents/<treeId>/` control stores),
  recovery fragments, caches, and logs

Package declarations in `settings.json` remain the source of truth for
reinstalling Pi packages. `"npmCommand": ["pnpm"]` makes Pi use pnpm for package
lookup and installation; the `npm:` source prefix still identifies registry
packages. npm packages are pinned to their adopted versions.
The pinned extensions require Pi 0.99.1 or newer and Node.js 22.19 or newer.
Upgrade the system-managed Pi package
(`pacman -S pi`) before applying these declarations.
No local extension checkout is required. The tree-continue package is no longer
declared; applying settings stops loading it without deleting its local checkout.

Disabled packages and their configuration are not managed.

Codex tools 4.1.0 keeps the existing configuration paths, but its pinned schemas
come from `pi-codex-runtime@0.5.0`. GPT-6 Astra/Sol/Luna deliberately retain
Lite, automatic WebSocket transport, prewarm, standalone search, and native
Responses compaction rather than adopting the new Standard/SSE defaults.
Astra needs explicit fields: its bundled defaults override inherited values
even when `extends` points to the Lite profile. Image generation and default
Fast mode remain disabled. Deprecated `responses.endpoint` overrides are
removed; Pi's provider API and base URL own routing.

Subagent is pinned to **1.0.0**, using the asynchronous Codex multi-agent v2
runtime. Its six tools are model-only (not callable from native codemode);
the managed scout/reviewer ordinary-tool allowlists are unchanged. See the
[subagent migration](#subagent-100-migration) before updating an existing install.
Telegram keeps its existing credential template and notification settings.
These configuration checks do not establish live endpoint compatibility.

Shared skills under `~/.agents/skills/` are installed separately with
`pnpm dlx skills`; only their [manifest and manual installer](skills.md) are managed
here, not the downloaded contents or CLI lock state.

## Subagent 1.0.0 migration

The managed `subagent.json` no longer contains `runtimeMode`. Foreground mode is
removed, not renamed. `maxConcurrentAgents: 4` limits active child runs across
the whole root tree; root does not count. Depth remains 3, with extension
inheritance, the optional OpenAI identity lifecycle, and the 51200-byte output
cap preserved.

Other retired settings (`maxConcurrentBackgroundRuns`, `maxIdleRuntimes`,
`defaultBackground`, `enableRunInBackground`, `backgroundProtocol`,
`reportDelivery`, `syncBundledAgents`) must not remain in the new configuration.
The old descriptor format is not resumed or migrated; retain historical sessions
and start new agents.

| Previous call | New contract |
| --- | --- |
| `subagent` / `subagent_fork` | `spawn_agent(task_name, message, agent_type?, fork_turns?)`; returns a path without waiting for completion. |
| `agent`, `prompt`, context objects | Optional `agent_type`, plaintext `message`, and `fork_turns:"all"|"none"` (default: all completed turns). |
| UUID / `subagent_id` / `agent_id` controls | `target` path; use canonical paths for peers, without `../` or trailing slash. |
| Enqueue then `followup_task` | `followup_task(target, message)` carries the new task itself. |
| Child `report` | `send_message(target, message)` to the parent. |
| Read answers from `wait_agent` | Wait for mailbox activity; answers arrive separately in attributed context messages. |

The remaining controls are `interrupt_agent(target)` and
`list_agents(path_prefix?)`. Ordinary messages do not start idle agents. Task
names use lowercase letters, digits and underscores, without hyphens.
Collaboration controls are provided by the runtime even with an ordinary-tool
ceiling, so scout/reviewer definitions need no new control-tool entries.

The tree store and child JSONL files remain under
`~/.local/state/pi/agent/sessions/`, already excluded by `.chezmoiignore`.
No new configuration target or runtime-state directory belongs in Git.

Review only explicit safe targets and privately back up existing files first:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/subagent.json
chezmoi apply ~/.config/pi/agent/subagent.json
pi install npm:@oai404iao/pi-subagent@1.0.0 --no-approve
```

The Pi install command updates that package declaration without resetting other
machine-local settings. If local settings differ from the managed source,
review those differences before applying `settings.json`: its modifier also
owns model selection, the enabled-model list and codemode defaults. Do not apply
the whole Pi directory merely to upgrade subagent; that can overwrite local
agent overrides or render Telegram credentials.

Restart Pi after replacing the installed package, or use `/reload` once no child
work needs preserving. Do not test migration by making paid model calls or sending
Telegram notifications.

## Codemode

Managed settings enable Pi's built-in codemode with
`"defaultTools": ["+codemode"]` and `"codemode": {"mode": "on"}`.
This adds JavaScript tool batching and output filtering without hiding direct
tool calls. Other codemode options, such as `inlineBudget`, remain machine-local.
See the [Pi codemode reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/codemode.md).

The pinned extension sources were checked against Pi's native codemode contract:

- Codex tools preserves codemode when reconciling its active tools.
- Subagent orchestration is `model-only`: call `spawn_agent` and the other five
  controls directly, not through `tools.spawn_agent()`. The managed scout/reviewer allowlists do not include
  codemode, so this change enables it in the parent, not those children.
- Ask-user-question 2.12.0 still uses default `direct` exposure, so it is also
  script-callable. Prefer direct questions; parallel dialogs and cancellation
  inside scripts have not been validated. This is why `on`, not `only`, is used.
- Telegram listens for UI prompts and settled runs rather than individual
  transcript tool results; nested calls should not require a config change.

Nested calls still pass through Pi's tool hooks, but scripts execute real tools:
their side effects are not rolled back on failure. This is not an OS sandbox.
Interactive dialogs, live provider requests, and Telegram delivery are not
covered by the offline checks.

After reviewing and applying the explicit settings target, use `/reload` or
restart Pi. CLI `--tools`/`--no-tools` overrides can prevent activation; a
project's plain-name `defaultTools` list can also replace the user selection.

## Global agent instructions

`dot_config/private_pi/agent/private_AGENTS.md` is the source of truth for
`~/.config/pi/agent/AGENTS.md` (mode `0600`). Pi loads it from
`PI_CODING_AGENT_DIR` alongside project context files; it does not replace
repository-specific `AGENTS.md` files. Support currently targets Pi only.
A local `AGENTS.override.md` in the same directory takes precedence; review
any such override if the managed rules do not appear.

The instructions prefer `uv` for Python (including one-off dependencies) and
`pnpm` / `pnpm dlx` over `npm` / `npx`, while preserving explicit project
requirements, canonical scripts, and lockfiles. Command examples follow the
[uv script guide](https://docs.astral.sh/uv/guides/scripts/) and
[pnpm CLI documentation](https://pnpm.io/cli/dlx).
The coding principles adapt the instruction body of
[`my_skills/prompts/coding-principles.md`](https://raw.githubusercontent.com/oai404iao/my_skills/refs/heads/main/prompts/coding-principles.md):
stay within scope, make local changes, resolve minor uncertainty pragmatically,
and verify and report outcomes honestly.

The instructions reserve `~/.local/state/agents/tmp/` for agent-created scratch
work across projects and agents. Agents create private, uniquely named task
directories on demand and retain their contents after use, rather than using
`/tmp` or adding cleanup traps. The root is deliberately fixed under the real
home directory, independent of temporary XDG overrides. Its contents are ignored
by chezmoi and must not contain credentials.

This is an instruction-level policy, not a sandbox or global `TMPDIR` override.
Existing test cleanup contracts and application-managed temporary files are
unchanged.

To deploy only these instructions, privately back up any existing target first,
review the explicit target, then apply:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/AGENTS.md
chezmoi apply ~/.config/pi/agent/AGENTS.md
```

Use `/reload` or start a new Pi session to load the updated context file.

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

Configure `deepseek`, `openai`, and `xai` with `/login`, selecting
API-key authentication when Pi offers multiple methods and entering the same
command reference for each. Do not replace the reference with the retrieved
value.

`auth.json` credentials take precedence over `models.json`. Pi resolves an
auth-file command on first use and caches the result for the process lifetime.
Because all three entries use the exact same command, one successful resolution
serves all three providers in that process. The key does not enter the general
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

## Web search

Pi reaches the web by running the `tvly` command through its normal bash tool,
guided by the Tavily Agent Skills. Install the CLI outside chezmoi:

```sh
uv tool install tavily-cli
```

The skills are declared in `scripts/skills.json` and installed with
`scripts/install-skills.py`; see [Global skills](skills.md). Do not run a bare
`tvly init`, which installs its own bundled copies of the same skills and would
give `~/.agents/skills/` a second owner. Pi discovers that directory natively
and needs a restart before newly installed skills are available.

The CLI cannot interpolate a command reference, so chezmoi renders
`~/.tavily/config.json` from the Bitwarden entry `pi tavily api key`:

```sh
rbw unlock
chezmoi apply ~/.tavily/config.json
```

`tvly` reads the `api_key` field of that file; `TAVILY_API_KEY` in the
environment would take precedence over it. Search and extract also work
keyless, while `map`, `crawl`, and `research` require the credential.
`tvly login`, `tvly logout`, and other CLI state live under `~/.tavily/`;
`session.json` is ignored, and a later apply restores the managed key.
Verify with `tvly auth --json` and a single `tvly search`.
