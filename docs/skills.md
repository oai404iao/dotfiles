# Global skills

Skills give Pi and other compatible agents task-specific instructions and
supporting files. This repository declares which shared skills to install;
it does not vendor their contents. Use a skill for reusable workflow knowledge,
not a global rule or an executable Pi integration. Those belong in
[agent instructions](pi-agents.md#global-agent-instructions) or
[Pi packages](pi-packages.md).

## Use an installed skill

Pi natively discovers `~/.agents/skills/`. It advertises names/descriptions
and reads full `SKILL.md` instructions when a task matches. For explicit
selection, use `/skill:name` in Pi; arguments after the command become the
task request. Run `/reload` after installing or changing skills.

Review the skill and its bundled scripts before use: instructions can ask an
agent to execute code or modify files. Skills are not a sandbox. The upstream
[Pi skills guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md)
describes discovery and portable `SKILL.md` frontmatter.

<a id="add-and-install"></a>

## Choose and review selections

[`scripts/skills.json`](../scripts/skills.json) pins the **skills CLI to 1.5.26**
and selects explicit names from each source. Current selections cover:

- `agent-browser` from `vercel-labs/agent-browser`
- `shadcn` from `shadcn/ui`
- `linear-cli` from `schpet/linear-cli`
- `agents-md`, `frontend-design`, `development-workflow`, `api-design`,
  `deployment-standards`, and `llm-prompt-design` from `oai404iao/my_skills`

Edit the manifest to change installation intent. For example, one source entry
looks like:

```json
{
  "source": "vercel-labs/skills",
  "skills": ["find-skills"]
}
```

This is an example entry, not an additional default selection. Sources accept
GitHub `owner/repo` shorthand or credential-free HTTPS URLs without query
strings/fragments. Names use lowercase kebab-case, at most 64 characters;
wildcards and duplicate names are rejected. Keep credentials and private
host/account inventory out of this public manifest.

The CLI is pinned, but shorthand sources follow the upstream default branch.
Use an upstream-supported revision URL when a fixed skill revision is needed.
The local lock file is bookkeeping, not a reproducibility guarantee.

## Preview and install

Run these from the chezmoi source root:

```sh
# Offline: validate the full manifest and print planned commands.
python3 scripts/install-skills.py --dry-run
```

Dry-run does not invoke pnpm, create directories, or require Node.js.
Before installation, review upstream content and privately back up local edits
and the active CLI lock file. Installation skips confirmation prompts and can
replace skills with matching names. Then, only when network installation is
intended:

```sh
# Requires pnpm, Node.js, and Git; fetches and installs remote content.
python3 scripts/install-skills.py
```

The helper runs pinned `pnpm dlx skills` with
`--global --agent universal --skill <names> --yes`. The pinned CLI installs
universal global skills directly to `~/.agents/skills/`, without agent-specific
symlinks. No Pi settings entry or duplicate under `~/.config/pi/agent/skills/`
is needed. See the reviewed CLI
[invocation](https://github.com/vercel-labs/skills/blob/d667282815248da03a08a18272b5d2eef9caf77c/README.md)
and [installer](https://github.com/vercel-labs/skills/blob/d667282815248da03a08a18272b5d2eef9caf77c/src/installer.ts).

There is no chezmoi run hook: **`chezmoi apply` never installs skills**.
An empty manifest does nothing in either mode. A failed installation stops
the helper, but completed installs are not rolled back.

## Update or remove selections

Re-running the installer installs all declared selections again; it does not
prune unlisted skills. Editing or removing a manifest entry does not alter
installed files or uninstall anything. Existing local skills and lock state
are not automatically imported. Review and back up local changes before each
update rather than assuming the previous install is disposable.

| Path | Ownership |
| --- | --- |
| `scripts/skills.json` | Managed installation intent and CLI version |
| `scripts/install-skills.py` | Managed manual installer |
| `~/.agents/skills/` | Downloaded skill contents, owned by the external installer |
| `$XDG_STATE_HOME/skills/.skill-lock.json` | Active CLI bookkeeping when `XDG_STATE_HOME` is set; normally `~/.local/state/skills/.skill-lock.json` |
| `~/.agents/.skill-lock.json` | CLI fallback when `XDG_STATE_HOME` is unset |

Skill contents and both default lock paths are ignored by chezmoi and Git.
Custom XDG roots remain machine-local. The pinned CLI's
[lock-path selection](https://github.com/vercel-labs/skills/blob/d667282815248da03a08a18272b5d2eef9caf77c/src/skill-lock.ts)
prefers `XDG_STATE_HOME`: back up the active file, and do not import a stale
fallback lock. Never `chezmoi add` downloaded skills or copy them into this
repository.

<a id="offline-checks"></a>

## Scratch and offline checks

Real installs scope `TMPDIR` to a private retained task directory beneath
`~/.local/state/agents/tmp/` and disable skills telemetry for the child process.
They do not change the login environment. The CLI can clean its own downloads;
the helper leaves its task directory in place. Do not retain credentials there.

`./tests/check-skills.sh` uses fake pnpm and isolated HOME/XDG directories to
check manifest validation, argv, dry-run/empty behavior, failure handling, and
state exclusions. It fetches no packages and changes no real installed skills.
It also runs through `./tests/check-source.sh`.
