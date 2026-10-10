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
- npm installation state (except its build policy below), `git/`, downloaded
  binaries, package installation IDs, and local plugin links under
  `~/.local/share/pi/extensions/`
- `.pi-subagent/` manifests and extension runtime state
- sessions (including `<rootSessionId>.subagents/<treeId>/` control stores),
  recovery fragments, caches, and logs

Package declarations in `settings.json` remain the source of truth for
reinstalling Pi packages. `"npmCommand": ["pnpm", "--config.node-linker=hoisted"]`
makes Pi use pnpm with a flat dependency layout; the `npm:` source prefix still
identifies registry packages. Pi's jiti loader resolves imports from extension
symlink paths without first resolving their real paths. An isolated pnpm layout
can therefore load stale npm-era siblings or fail to find transitive dependencies.
The hoisted setting applies only to Pi package operations, not other projects.
npm packages are pinned to their adopted versions.
The pinned extensions require Pi 0.99.1 or newer and Node.js 22.19 or newer.
Upgrade the system-managed Pi package
(`sudo pacman -Syu pi`) before applying these declarations, then fully exit and
restart Pi so the process uses the upgraded host SDK.
Graphical machines also require the local notification source link described below.
The tree-continue package is no longer declared; applying settings stops loading
it without deleting its local checkout.

Disabled packages and their configuration are not managed.

Codex tools 4.1.1 keeps the existing configuration paths, but its pinned schemas
come from `pi-codex-runtime@1.0.0`. GPT-6 Astra/Sol/Luna deliberately retain
Lite, automatic WebSocket transport, prewarm, standalone search, and native
Responses compaction rather than adopting the new Standard/SSE defaults.
Astra needs explicit fields: its bundled defaults override inherited values
even when `extends` points to the Lite profile. Image generation and default
Fast mode remain disabled. Deprecated `responses.endpoint` overrides are
removed; Pi's provider API and base URL own routing.

The removed `directImageApiFallback` property is no longer managed, including
its former `false` value. Profiles already select standalone image generation
and Responses `compaction_trigger`, not the removed hosted-image or unary
compaction paths. `/fast` now changes session state without rewriting the
configured default; children follow the main session's selection.
Historical opaque checkpoints remain protected; unrecognized custom-profile
hashes fail closed rather than silently converting history to text.

Subagent is pinned to **1.0.1**, using the asynchronous Codex multi-agent v2
runtime. Its six tools are model-only (not callable from native codemode);
the managed scout/reviewer allowlists enable codemode alongside their existing
ordinary tools. Mailbox waits now default to 120 seconds, with 300 seconds
recommended for longer tasks; incoming activity still wakes the caller early.
This is a plugin default, not a new `subagent.json` setting. See the
[subagent migration](#subagent-100-migration) before updating an existing install.
Headless machines keep the existing Telegram credential template and settings.
These configuration checks do not establish live endpoint compatibility.

Shared skills under `~/.agents/skills/` are installed separately with
`pnpm dlx skills`; only their [manifest and manual installer](skills.md) are managed
here, not the downloaded contents or CLI lock state.

## Notifications by machine profile

Chezmoi's `graphical` machine data selects exactly one notification package:

| Profile | Package |
| --- | --- |
| `graphical = true` | `~/.local/share/pi/extensions/pi-local-notify` |
| `graphical = false` | `npm:@oai404iao/pi-telegram-notify@0.6.0` |

This is an apply-time choice, independent of `niri`, `DISPLAY`, or SSH session
variables. Change `graphical` deliberately with `chezmoi edit-config` when the
machine role changes; it also controls other graphical targets.

`~/.local/share/pi/extensions/` is the stable entry directory for local plugins.
Each machine maintains symlinks there to trusted source checkouts, wherever
those checkouts live. Pi settings declare individual packages through these
links; the directory is not automatically scanned. Neither the links nor their
source code are owned by chezmoi.

On desktops, create the link once, replacing the source placeholder with the
absolute path to `pi-local-notify` inside your `omp` checkout:

```sh
mkdir -p -- "$HOME/.local/share/pi/extensions"
ln -sT -- /absolute/path/to/omp/pi-extensions/pi-local-notify \
  "$HOME/.local/share/pi/extensions/pi-local-notify"
```

Do not overwrite an existing entry without inspecting it. If a checkout moves,
update only its machine-local link, not Pi settings. The package is
private/local-only and is not installed from npm or copied into chezmoi.
A missing or dangling link does not fall back to Telegram. It uses Kitty OSC 99
in an interactive TUI; other terminals and non-interactive modes do not notify.
The managed tmux configuration already enables `allow-passthrough on`, which
only passes notifications from visible panes. Unlike Telegram, the local plugin
notifies settled runs, not blocking questionnaires or approvals.

Graphical profiles ignore the Telegram configuration directory, so applying Pi
configuration does not retrieve Telegram credentials. Existing Telegram config
and downloaded packages are retained, not deleted; removing its package
declaration stops loading it after reload/restart. Independently configured
project or CLI extensions are outside this selection and can still load it.

To switch an existing machine, privately back up and review
`~/.config/pi/agent/settings.json`, then apply only that target:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/settings.json
chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/settings.json
```

For a headless machine, also back up and apply the explicit Telegram
`~/.config/pi/agent/extensions/pi-telegram-notify/config.json` target after
unlocking `rbw`; never display its secret-bearing diff. Restart Pi or use
`/reload` when child work no longer needs preserving. On Kitty, manually run
`/local-notify-test` to check delivery and click-to-focus; offline configuration
checks do not send notifications or establish desktop delivery.

## pnpm build approvals

Pi installs user npm packages under `~/.config/pi/agent/npm`. Chezmoi manages
only that directory's `pnpm-workspace.yaml` build policy, not `package.json`,
the lockfile, `node_modules`, or installation state. Its modifier preserves
unrelated settings and approvals while replacing selectors for these packages
with exact reviewed versions:

- `@google/genai@2.21.0`
- `esbuild@0.28.2`
- `protobufjs@7.6.6`

This is not a global pnpm policy and does not approve builds in project-local
or temporary Pi installs. It neither allows all builds nor disables build
checking. Other versions require a new review; package pins do not pin every
transitive dependency. Existing unrelated machine-local policies remain intact.
See pnpm's [build policy reference](https://pnpm.io/settings/build#allowbuilds).

Back up the existing workspace file privately, then review and apply only
this non-secret policy target:

```sh
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.config/pi/agent/npm/pnpm-workspace.yaml
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/pi/agent/npm/pnpm-workspace.yaml
```

The modifier accepts one YAML mapping without document markers, rejecting
malformed or ambiguous input instead of discarding it. Applying the policy
does not install packages or run their scripts. A subsequent Pi package install
reads the approvals. If an earlier install skipped builds, deliberately rebuild
after reviewing the installed versions:

```sh
pnpm --dir ~/.config/pi/agent/npm rebuild @google/genai esbuild protobufjs
```

That command executes dependency code; it is not part of the offline checks or
an apply hook. The checks cover policy merging, idempotence, invalid input,
the managed-file exception, and pnpm 12 reading a fixture policy, not real
dependency builds or live Pi startup.

## Pi package layout migration

Applying settings does not rebuild an existing package installation. Privately
back up `~/.config/pi/agent/settings.json` and `~/.config/pi/agent/npm/` outside
chezmoi before migrating, then review and apply only the settings target:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/settings.json
chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/settings.json
```

Rebuild the existing lockfile without changing package versions or running
package lifecycle scripts:

```sh
cd ~/.config/pi/agent/npm
pnpm --config.node-linker=hoisted install --offline --frozen-lockfile --ignore-scripts
```

For an installation created with peer auto-installation disabled, append
`--config.auto-install-peers=false` if `settings.autoInstallPeers` in
`pnpm-lock.yaml` is `false`; frozen installs must match that recorded setting.
Do not discard or regenerate the lockfile to bypass a configuration mismatch.
`--offline` requires every locked package to be in the local pnpm store. If one
is missing, retain the backup and explicitly retry without `--offline` to allow
registry access. pnpm rebuilds the isolated layout and removes stale top-level
packages. Do not delete just the old Codex sibling directories: an isolated
layout still leaves jiti unable to resolve their replacements.

Restart Pi after the rebuild and check `/codex-minimal-tools:doctor` on
`openai/gpt-6.1-sol`: the model profile should no longer be `(none)`, the provider
shim should be active, and `apply_patch` should be active. The 4.1.1 runtime
already supplies this model profile; adding it to user `models.json` is not the
fix. Installation data, lockfiles, and backups remain machine-local and ignored.

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
pi install npm:@oai404iao/pi-subagent@1.0.1 --no-approve
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

### `createCodemodeExtension is not a function`

This error occurs during child-runtime creation, before the child can execute
its task. Check the host Pi version first: subagent 1.0.1 requires Pi 0.99.1 or
newer, including its SDK factories. A newer `pi-coding-agent` dependency under
`agent/npm/node_modules` does not upgrade the running host; Pi maps extension
SDK imports to its own implementation.

For the system-managed Arch installation:

```sh
command -v pi
pacman -Q pi
sudo pacman -Syu pi
```

Finish the full upgrade, then exit the old Pi process and start Pi again.
`/reload` reloads extensions, not the running host SDK; retrying `spawn_agent`
inside an outdated process will not fix missing exports. Keep existing
sessions and create a new child after restarting. Do not delete session or npm
state, patch installed extension files, or disable codemode to mask this error:
the child runtime creates its codemode factory regardless of the active tool list.

If it persists after a full restart, check whether `command -v pi` selects a
different installation from the one upgraded, then inspect that host's SDK and
the installed subagent version. Repository configuration checks alone do not
verify the running process.

## Agent delegation guidance

The managed global instructions define bounded tasks, file ownership, explicit
completion criteria, and confirmation of decisions that change delegated work.
Independent reconnaissance or review can use `fork_turns:"none"` with a
self-contained brief; related follow-ups reuse an agent with the latest task and
decisions. Message acceptance is not evidence that a decision was implemented.

Scout reports coverage, exact locations, constraints, and uncertainty without
expanding into implementation or a full audit. Reviewer reports coverage,
severity-ranked findings, actual verification, and gaps. Both remain read-only;
unreviewed requirements must be explicit rather than hidden behind a completed
run status. These are instruction-level expectations, not enforced permissions
or a guarantee of complete review.

Worker executes scoped subtasks, including file edits and verification, and
reports completed deliverables, actual checks, and remaining gaps. Its definition
omits `tools`, `model`, and `thinking`: it uses the default child tool policy
without an additional role-specific ceiling and inherits the caller's model and
thinking level. With extension inheritance enabled, it uses the same configured
tool setup as the main agent, subject to inherited ceilings and the plugin's
[child-runtime limits](#codemode); this is not an exact copy of root-only
capabilities. Select it with `spawn_agent` using `agent_type: "worker"`.

The main agent normally coordinates parallel work. Nested delegation needs a
distinct purpose; shared-file edits require coordination. The existing model
choices, thinking levels, tool ceilings, package pins, and runtime limits are
unchanged. No queue or new plugin setting is introduced.

To deploy this guidance, review and privately back up the explicit targets
before applying only `~/.config/pi/agent/AGENTS.md`,
`~/.config/pi/agent/agents/scout.md`, and
`~/.config/pi/agent/agents/reviewer.md`. Reload or restart Pi when existing child
work no longer needs preserving, then spawn new children.

To add only worker, review and apply the explicit target
`~/.config/pi/agent/agents/worker.md`, privately backing it up first if it exists.
Reload or restart Pi before selecting the new agent type.

## Codemode

Managed settings enable Pi's built-in codemode with
`"defaultTools": ["+codemode"]` and `"codemode": {"mode": "on"}`.
This adds JavaScript tool batching and output filtering without hiding direct
tool calls. Other codemode options, such as `inlineBudget`, remain machine-local.
See the [Pi codemode reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/codemode.md).

The pinned extension sources were checked against Pi's native codemode contract:

- Codex tools preserves codemode when reconciling its active tools.
- Subagent orchestration is `model-only`: call `spawn_agent` and the other five
  controls directly, not through `tools.spawn_agent()`. The managed scout/reviewer
  allowlists explicitly include `codemode`, enabling batching and filtering
  within each child's tool ceiling without adding editing tools. Their
  read-only instructions remain unchanged; the existing `bash` tool is not a
  filesystem sandbox. The child runtime loads codemode with `models: false`,
  so its default implementation does not expose the `models` API.
- Ask-user-question 2.12.0 still uses default `direct` exposure, so it is also
  script-callable. Prefer direct questions; parallel dialogs and cancellation
  inside scripts have not been validated. This is why `on`, not `only`, is used.
- Telegram listens for UI prompts and settled runs rather than individual
  transcript tool results; nested calls should not require a config change.

Nested calls still pass through Pi's tool hooks, but scripts execute real tools:
their side effects are not rolled back on failure. This is not an OS sandbox.
Interactive dialogs, live provider requests, and Telegram delivery are not
covered by the offline checks.

After reviewing and backing up existing targets, apply only
`~/.config/pi/agent/settings.json`, `~/.config/pi/agent/agents/scout.md`, and
`~/.config/pi/agent/agents/reviewer.md` as needed. Use `/reload` or restart Pi,
and spawn new children rather than expecting existing agents' fixed tool
permissions to change. CLI `--tools`/`--no-tools` overrides can prevent activation; a
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

`anthropic` uses `https://api.krill-code.net` with Pi's built-in model catalog.
The enabled-model list includes `anthropic/claude-opus-5-5`; the default remains
`openai/gpt-6-astra`. Configure its own Krill API-key credential with
`/login anthropic`, selecting API-key authentication. It does not automatically
reuse the Spiredive credential.

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

On headless machines, the Telegram extension does not support command or
environment interpolation. Chezmoi renders its private `config.json` from these
Bitwarden entries (not required for desktop notifications):

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
