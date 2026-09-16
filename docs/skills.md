# Global skills

The repository manages installation intent, not skill contents:

- `scripts/skills.json`: pinned `skills` CLI version and selected remote skills
- `scripts/install-skills.py`: explicit manual installation via `npx skills`
- `~/.agents/skills/`: downloaded contents, owned by the external installer
- `~/.agents/.skill-lock.json`: machine-local CLI bookkeeping, not a manifest

The last two paths are ignored by chezmoi and Git. Do not `chezmoi add` skill
directories or copy their contents into this repository. Existing local skills
and lock state are not automatically imported. Editing the manifest does not
change installed files; removing an entry does not uninstall anything.

## Add and install

Edit `scripts/skills.json`, selecting explicit skill names. For example:

```json
{
  "cliVersion": "1.5.26",
  "sources": [
    {
      "source": "vercel-labs/skills",
      "skills": ["find-skills"]
    }
  ]
}
```

Sources accept GitHub `owner/repo` shorthand or credential-free HTTPS URLs
without query strings or fragments. Skill names use lowercase kebab-case
(up to 64 characters); wildcards and duplicate names are rejected.
Do not put credentials or private host/account inventory in this public manifest.
The CLI version is pinned, but shorthand sources follow their upstream default
branch. Use an upstream-supported revision URL when a fixed skill revision is
needed; the local CLI lock file is not a reproducibility guarantee.

From the chezmoi source root:

```sh
# Offline: validate the entire manifest and print the planned commands.
python3 scripts/install-skills.py --dry-run

# Explicit network operation; requires Node.js/npm (npx) and Git.
python3 scripts/install-skills.py
```

Neither command does anything to installed skills when the manifest is empty.
Dry runs do not invoke `npx`, create directories, or require Node.js.
There is no chezmoi run hook: `chezmoi apply` never installs these skills.

The helper passes `--global --agent universal --skill <names> --yes` to the
[upstream CLI](https://github.com/vercel-labs/skills/blob/d667282815248da03a08a18272b5d2eef9caf77c/README.md).
In the pinned version, the
[installer](https://github.com/vercel-labs/skills/blob/d667282815248da03a08a18272b5d2eef9caf77c/src/installer.ts)
uses `~/.agents/skills/` for universal global installs without agent-specific
symlinks. Pi discovers that directory natively; no Pi settings entry or duplicate
copy under `~/.config/pi/agent/skills/` is required. Reload Pi after installation.

Installation skips confirmation prompts and may replace existing skills with
matching names. Review upstream content and privately back up local edits before
running it. Re-running installs the declared selections again; it does not prune
unlisted skills. On failure the helper stops, but already completed installs
are not rolled back.

The helper scopes `TMPDIR` to a private, retained task directory beneath
`~/.local/state/agents/tmp/` and disables skills telemetry for the child process.
It does not change the login environment. The CLI may clean its own downloads;
the helper leaves the task directory in place. Do not retain credentials there.

## Offline checks

`./tests/check-skills.sh` uses a fake `npx` with isolated HOME/XDG directories.
It validates the manifest, argv, dry-run/empty behavior, failure handling, and
state exclusions without fetching packages or changing real installed skills.
It is also included in `./tests/check-source.sh`.
