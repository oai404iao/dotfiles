# Pi agents and instructions

This setup combines native codemode, a small Jev classifier registration,
the pinned subagent extension, and shared global instructions. Use this page
to understand their contracts or update them without losing active child work.
For package installation, see [Pi packages](pi-packages.md); for keys, see
[authentication](pi-authentication.md).

## Choose the right mechanism

| Need | Mechanism |
| --- | --- |
| Persistent rules across projects | [Global `AGENTS.md`](#global-agent-instructions) plus repository context files |
| Task-specific reusable instructions | [Shared skills](skills.md) |
| Batch tools or filter their output | [Native codemode](#codemode) |
| Advisory workflow/review triage | [Jev](#jev-task-triage), optional and at most once per task |
| Useful independent work | [A bounded child agent](#choose-a-role) |

These instructions do not create an operating-system sandbox. Tool ceilings
and read-only roles limit intended behavior, but an available `bash` tool can
still modify files. All agents share the working tree unless explicitly
isolated elsewhere.

## Choose a role

The managed role files live in
[`exact_agents/`](../dot_config/private_pi/agent/exact_agents/), deployed as
`~/.config/pi/agent/agents/{scout,reviewer,worker}.md`.

| Role | Use for | Model / thinking / ordinary tools |
| --- | --- | --- |
| `scout` | Bounded discovery when relevant paths/dependencies are unknown; not a known-path fix. | `openai/gpt-6-luna`, high; `read`, `grep`, `find`, `ls`, `bash`, `codemode`, `web_search`. |
| `reviewer` | One independent read-only review when requested or materially risk-justified; not a routine completion gate. | Inherit model, high thinking; the same ceiling as scout without `web_search`. |
| `worker` | Independent scoped implementation with relevant checks. | Inherit caller model/thinking and tools, including `apply_patch` and `web_search`; no role-specific ceiling. |

Worker omits `tools`, `model`, and `thinking`. With extension inheritance
enabled, it uses the configured child tool policy subject to inherited
ceilings and runtime limits—not an exact copy of root-only capabilities.

Read-only roles are scoped by what an action changes, not by which tool it
uses. `bash`, `codemode`, and `web_search` stay allowed for batched search,
`git` inspection, and non-mutating checks. Their instructions name the writing
operations to refuse—redirections, in-place edits, worktree or index changes,
`chezmoi apply`, package installs, artifact-emitting builds—and require
reporting such a check as not run. The ceiling is still the hard limit:
`tools:` accepts exact names only, so a tool absent from it cannot be reached
by prompt wording, and `web_search` requires the Codex tools extension to be
enabled and registered in the child. Commands with command-level permissions
remain the place for real enforcement.

Worker declares no ceiling, so it inherits the caller's, including the mutation
path. With Codex tools active, `apply_patch` is that path and `edit`/`write` are
undeclared; its instructions name `apply_patch` instead of leaving shell
redirection as an improvised substitute.

### Delegate a bounded task

Keep simple questions and known-path fixes with the root; there is no mandatory
scout → worker → reviewer pipeline. For useful independent work, supply:

- The goal, necessary context, and a concrete completion criterion.
- Owned files, excluded scope, and required coordination for shared-file edits.
- Relevant checks, safety restrictions, and how to report incomplete work.

Use `fork_turns:"none"` for self-contained reconnaissance or review with a
complete brief. Inherit history when the task genuinely depends on it.
Related follow-ups should reuse the existing agent with the latest task and
decisions, not create a fresh agent merely to repeat work.

The main agent normally coordinates parallel work. Nested delegation needs
a distinct purpose. Confirm receipt only when a material decision changes
scope or correctness; tool/message acceptance alone does not prove it was
implemented. Check the child's actual report against deliverables and required
checks before claiming completion.

Scout reports coverage, exact locations, constraints, and uncertainty; it does
not expand into implementation, an exhaustive audit, or a full test run.
Reviewer reports coverage, severity-ranked concrete findings, actual checks,
and gaps. It does not delegate or start another review. Another reviewer needs
a concrete residual high-risk issue or an explicit user/repository requirement,
not reassurance. Worker reports completed deliverables/files, exact commands run,
and remaining gaps; it leaves changes uncommitted unless the task authorizes
a commit, and records out-of-scope defects instead of fixing them. Small
reports may combine fields. A finished run with
unreviewed or unfinished requirements is partial work, not overall success.

## Runtime and lifecycle reference

Subagent **1.3.1** uses the asynchronous Codex multi-agent v2 runtime.
The managed `subagent.json` sets:

| Setting | Value and meaning |
| --- | --- |
| `agentScope` | `user` |
| `maxDepth` | `3` |
| `maxConcurrentAgents` | `8` active child runs across the whole root tree; root does not count. |
| `inheritExtensions` | `true` |
| `maxOutputBytes` | `51200` |
| `openAIIdentity` | `true`, retaining the optional identity lifecycle |

Waiting children still occupy slots. Admission fails immediately at capacity;
there is no queue. Continue independent work or wait for active work rather
than repeatedly retrying or interrupting unrelated agents.

Call these seven controls **directly**, not from native codemode scripts:

| Tool | Contract |
| --- | --- |
| `spawn_agent` | Start a uniquely named direct child; return its canonical path without waiting for completion. |
| `send_message` | Queue an attributed message; does not start an idle agent or wait for an answer. |
| `followup_task` | Carry a new task to an existing agent, starting an idle child or delivering at a safe boundary. |
| `wait_agent` | Wait for activity in the caller's mailbox; answers arrive separately as context messages. |
| `list_agents` | Paginated registry listing; supports `path_prefix`, `include_closed`, `limit`, and `cursor`. |
| `interrupt_agent` | Stop a run while retaining the agent for reuse. |
| `close_agent` | Permanently retire the target's structural subtree; retain history and reserved names. |

Task names use lowercase letters, digits, and underscores, not hyphens.
Use canonical paths for peers, without `../` or trailing slashes.
Spawn and follow-up accept explicit `model` and `thinking` selections, added
in 1.2.0, in addition to role defaults/inheritance. Closing is not cleanup,
rollback, or a reusable pause; choose interruption when more work may follow.

Mailbox waits default to **120 seconds** in 1.3.1; use **300 seconds** for
longer tasks. Incoming activity wakes the caller early. This is a plugin
default, not a `subagent.json` key. Wait only when no independent work remains
and progress depends on incoming work; a timeout is not task failure.

Control stores and child JSONL files remain under
`~/.local/state/pi/agent/sessions/`, including
`<rootSessionId>.subagents/<treeId>/`. They and `.pi-subagent/` manifests are
already ignored. Do not add them to configuration or delete them to repair an
SDK problem.

## Jev task triage

Jev is a classifier, not a chat model. It does not appear in `/model` or
`enabledModels`, and it does not replace the default coding model.
[`extensions/private_jev.ts`](../dot_config/private_pi/agent/extensions/private_jev.ts)
registers provider `typesafe`, model ID **`typesafe/jev`**, with Pi's built-in
`typesafe-system-one` transport. Pi 1.2.0's `models.json` additions are chat-only,
so this classifier needs the small provider extension, not another npm package.

The endpoint stays in `models.json` as
`https://api.commandcode.ai/provider/v1`; Pi appends `systemone` exactly once.
The integration targets the [Command Code Provider API](https://commandcode.ai/docs/provider).
Its managed auth command is `!rbw get 'pi commandcode api key'`, distinct from
Spiredive/Krill and requiring a Command Code key rather than a direct TypeSafe key.
The classifier retains unpriced zero-cost catalog metadata. Token usage is
recorded, but a zero session cost does **not** imply a free service.

### What the global instructions request

Jev is optional, not a step in every task. When it is genuinely unclear whether
a task needs independent delegation or an independent review, the root may call
`models.classify` through codemode at most once, before starting work that
depends on that choice:

- Select `{ provider: "typesafe", id: "typesafe/jev" }`.
- Send only a short sanitized task, scope/independent-work boundaries, and
  risk/unknowns summary, including known user/repository constraints. Never
  send secrets, raw files, or the full transcript.
- Ask both typed choice questions in that call: workflow `direct`/`delegate`
  and independent review `needed`/`unnecessary`.
- Accept only `stopReason === "stop"` with correctly typed, defined labels.
  Missing API, failed calls, invalid or uncertain answers fall back to
  proportionate root judgment—without classification retries or reviewer loops.

Straightforward work and known-path fixes skip the call entirely. Continuations,
status replies, tool results, and child messages in the same task do not trigger
another call. Children have `models: false` and must not proxy classification
through other agents, tools, or providers; they decide proportionately instead.

The result is advisory, not authorization or a correctness guarantee. User
restrictions and required checks still apply. Keep straightforward work direct;
delegate useful bounded work and request one review only when justified.
Finish when the deliverables and relevant required checks are complete.
This is prompt guidance, not an automatic routing hook or enforced call count.

### Deploy a Jev or role change

Publish the reviewed global prompt to `my_skills/main` and follow the
[reviewed-cache workflow](#global-agent-instructions). Privately back up
existing targets, then review/apply only the changed `models.json`,
`extensions/jev.ts`, and role files. Do not diff an existing model file that
might contain literal credentials; use [safe takeover](pi-authentication.md#adopt-a-legacy-model-file-containing-a-key).
Update `auth.json` separately after exiting Pi. Restart and create new children
for provider/role changes. This integration adds no npm dependency or package pin.

`tests/check-pi.sh` covers the auth merge and isolated deployment. With Node
and Pi installed, `tests/check-pi-jev.mjs` loads the registration against the
installed composer and mocks every HTTP request: endpoint/model, typed answers,
usage, and errors. It does not contact Command Code, resolve real credentials,
or establish live compatibility.

## Codemode

Managed settings add `"defaultTools": ["+codemode"]` and
`"codemode": {"mode": "on"}`. This enables native JavaScript batching and
output filtering while leaving direct tools visible. Other options, such as
`inlineBudget`, stay machine-local. The upstream [codemode reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/codemode.md)
defines the script and model APIs.

For example, independent reads can settle together without one failure
discarding every successful result:

```js
const results = await Promise.allSettled([
  tools.read({ path: "README.md" }),
  tools.read({ path: "AGENTS.md" }),
]);
for (let i = 0; i < results.length; i++) text({ index: i, ...results[i] });
```

Scripts run in QuickJS without Node, direct filesystem/network access, or
timers. That is a script-runtime boundary, **not** an OS sandbox for the tools
they invoke. Nested calls still pass Pi's tool hooks, and real side effects
before a script failure are not rolled back. Await calls before the script
ends; unfinished calls are cancelled. Inspect structured tool results—bash
can resolve successfully as a promise while reporting a nonzero `exit_code`.

### Extension and child limits

- Codex tools preserves codemode while reconciling active tools.
- All seven subagent controls are `model-only`; use direct `spawn_agent`,
  not `tools.spawn_agent()`. Runtime collaboration controls remain available
  within ordinary-tool ceilings and need no role allowlist entries.
- Scout/reviewer allowlists explicitly include codemode without adding editing
  tools. Child scripts stay within their fixed ceilings and have no `models`
  API. Bash remains subject to read-only instructions, not filesystem isolation
  or command-level permissions.
- Ask-user-question 2.13.9 has default `direct` exposure and is script-callable,
  but direct questions are preferred. Parallel dialogs and script cancellation
  around them have not been validated; this setup uses `on`, not `only`.
- Telegram listens for UI prompts and settled runs rather than individual
  transcript tool results; nested calls should not need a configuration change.

Privately back up and review only `settings.json`, `agents/scout.md`, and
`agents/reviewer.md` when changing this setup. Reload/restart and spawn new
children: existing agents' fixed tool permissions do not change in place.
CLI `--tools`/`--no-tools` can prevent activation, as can a project's plain-name
`defaultTools` list replacing the user selection. Interactive dialogs, live
model requests, and notification delivery are outside the offline checks.

## Global agent instructions

The sole source of truth for `~/.config/pi/agent/AGENTS.md` is
[`my_skills/prompts/pi-global-agents.md`](https://github.com/oai404iao/my_skills/blob/main/prompts/pi-global-agents.md).
Edit it in that repository, not the installed copy or a second local source
here. The external declaration in `.chezmoiexternal.toml` fetches remote `main`
as a private file (mode `0600`); no local checkout path is required. Support
currently targets Pi only.

Pi loads global instructions from `PI_CODING_AGENT_DIR` alongside project
context, not instead of repository `AGENTS.md`. A same-directory
`AGENTS.override.md` takes precedence over that directory's managed file;
review an override if the expected rules do not appear.

The coding principles adapt the upstream
[`coding-principles.md`](https://github.com/oai404iao/my_skills/blob/main/prompts/coding-principles.md):
stay in scope, make local changes, resolve low-risk uncertainty pragmatically,
and verify/report honestly. The tool defaults prefer `uv` for Python (including
one-off dependencies), and `pnpm`/`pnpm dlx` over `npm`/`npx`, without replacing
explicit project requirements, canonical scripts, or lockfiles.

### Scratch policy

Agent-created scratch belongs beneath the real home's fixed
`~/.local/state/agents/tmp/`, independently of temporary XDG overrides. Create
a private, uniquely named task directory on demand; retain its contents after
use. For example:

```sh
(
    set -eu
    umask 077
    scratch_root="$HOME/.local/state/agents/tmp"
    mkdir -p -- "$scratch_root"
    task_dir=$(mktemp -d "$scratch_root/task-name.XXXXXXXX")
    printf '%s\n' "$task_dir"
)
```

Capture that absolute path before changing HOME/XDG; shell variables do not
persist between tool calls. Scope `TMPDIR` only to commands needing it.
Do not use `/tmp`, cleanup traps, or broad sweeps for agent-created scratch.
Never keep credentials or credential backups there. The directory is ignored
by chezmoi. This is instruction policy, not a sandbox or global `TMPDIR`
override; existing tests' cleanup and application-managed temp contracts remain
unchanged.

### Review and deploy the external file

Publish reviewed edits to `my_skills/main` first. The 24-hour cache is not a
background timer: a chezmoi operation fetches when it needs the external and
the cache is due, or when explicitly refreshed. Fetches require network access.
Following `main` trades reproducible pins for convenient updates, so review
the fetched instructions before deployment.

Privately back up any existing target, then review and apply that target only:

```sh
chezmoi diff --refresh-externals=always --skip-secrets --exclude=scripts,encrypted \
  ~/.config/pi/agent/AGENTS.md
chezmoi apply --refresh-externals=never --exclude=scripts,encrypted \
  ~/.config/pi/agent/AGENTS.md
```

The apply reuses the reviewed cache, rather than fetching newer `main` between
review and deployment. Do not refresh the cache concurrently. On a new machine
or migration, publish the upstream prompt before deploying the external
declaration. See the [chezmoi external reference](https://www.chezmoi.io/reference/special-files/chezmoiexternal-format/).

For role changes, also back up/review the explicit
`~/.config/pi/agent/agents/{scout,reviewer,worker}.md` targets before applying
only those needed. To add worker alone, apply only `agents/worker.md`.
Reload/restart when child work no longer needs preserving, then spawn new
children. Use `/reload` or a new Pi session for updated context files.

`tests/check-pi.sh` verifies the external declaration and isolated deployment
with synthetic file and loopback HTTP fixtures, including reviewed-cache use.
It neither downloads nor validates the live upstream instructions.

## Subagent 1.0.0 migration

Use this when moving from the retired foreground/descriptor runtime to the
current asynchronous contract. `runtimeMode` is removed, not renamed.
Also remove `maxConcurrentBackgroundRuns`, `maxIdleRuntimes`,
`defaultBackground`, `enableRunInBackground`, `backgroundProtocol`,
`reportDelivery`, and `syncBundledAgents`. The managed runtime limits above
remain unchanged. Old descriptors are not resumed or migrated: retain the
historical sessions and start new agents.

| Previous usage | Current contract |
| --- | --- |
| `subagent` / `subagent_fork` | `spawn_agent(task_name, message, agent_type?, fork_turns?)`; asynchronous path return. |
| `agent`, `prompt`, context objects | Optional `agent_type`, plaintext `message`, and `fork_turns:"all"|"none"`; default inherits completed turns. |
| UUID / `subagent_id` / `agent_id` | Canonical `target` path. |
| Enqueue, then `followup_task` | `followup_task(target, message)` contains the new task itself. |
| Child `report` | `send_message(target, message)` to the parent. |
| Answer returned by `wait_agent` | Mailbox activity signal; answers arrive separately as attributed context. |

Privately back up existing files. Review/apply only the safe subagent target,
then deliberately install the pinned package:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/subagent.json
chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/subagent.json
pi install npm:@oai404iao/pi-subagent@1.3.1 --no-approve
```

The install updates that package declaration without resetting other local
settings. If applying managed `settings.json` too, review its wider ownership
first. Do not apply the whole Pi directory: it can replace local agent
overrides or retrieve Telegram credentials. Restart after package replacement,
or `/reload` once no child work needs preserving. Do not test migration with
paid model calls or Telegram delivery.

### `createCodemodeExtension is not a function`

This error occurs before a child can execute its task. Subagent 1.3.1 needs
Pi 1.2.0+ and its SDK factories. A newer dependency under
`agent/npm/node_modules` does not upgrade the running host: Pi maps extension
SDK imports to its own implementation.

For the system-managed Arch installation:

```sh
command -v pi
pacman -Q pi
sudo pacman -Syu pi
```

Finish the full upgrade, exit the old process, and start Pi again. `/reload`
does not replace the running SDK; retrying spawn in that process cannot fix
missing exports. Keep sessions and create a new child after restart.

Do not delete session/npm state, patch installed packages, or disable codemode
to mask the error: the child runtime creates its codemode factory regardless
of active tools. If it persists, check whether `command -v pi` selects a
different installation from the one upgraded, then inspect that host's SDK
and installed subagent version. Repository checks alone do not verify a
running process.
