# Global Agent Instructions

## Coding principles

- Deliver the authorized goal without adding unrequested features,
  abstractions, or configuration.
- Proceed with reasonable assumptions for low-risk, reversible details;
  state assumptions that affect results. Ask when ambiguity materially changes
  the outcome, scope, or authorization; continue unaffected authorized work.
- Make local changes in the project's style and preserve existing user work.
  Avoid unrelated refactoring; remove unused code introduced by your changes.
- Judge complexity by readability and actual needs, not line count. Preserve
  necessary error handling, interface contracts, and edge-case behavior.
- Define verifiable outcomes and choose checks according to risk and project
  requirements. Once required checks pass, do not expand or repeat validation
  without new changes, failures, or unresolved issues.
- Report completed work, checks actually run, and remaining blockers honestly.
  Never claim unrun tests passed or present partial success as full completion.

## Tool selection

- Prefer `uv` for running Python, especially when dependencies are needed.
  Use `uv run python` or `uv run script.py`; for one-off dependencies, use
  `uv run --with <package> python ...` rather than installing into system Python.
  For scratch scripts unrelated to a Python project, add `--no-project` to
  avoid installing or syncing that project's dependencies.
- Prefer `pnpm` over `npm`, and `pnpm dlx <package>` over `npx <package>` for
  one-off package execution. Use `pnpm exec <command>` for project-installed
  binaries rather than downloading a separate copy.
- These are defaults, not package-manager migration instructions. Honor explicit
  project requirements and canonical scripts; do not rewrite scripts, replace
  lockfiles, or add tooling dependencies merely to enforce these preferences.

## Temporary workspace

- Avoid `/tmp`, `/var/tmp`, and bare `mktemp` for agent-created scratch files.
  Use `$HOME/.local/state/agents/tmp/` as the shared agent scratch root.
- Create a fresh task directory before writing temporary scripts, downloads,
  logs, or intermediate output. Use a descriptive task prefix and `mktemp`'s
  random suffix to avoid collisions between sessions and subagents:

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

- Capture the printed absolute path and reuse it in later tool calls; shell
  variables do not persist between calls. Resolve it before temporarily
  changing `HOME` or XDG variables, and never reconstruct it from rebound
  environment variables.
- When a command supports `TMPDIR`, scope `TMPDIR` to that task directory for
  that command only. Do not change the login environment or assume every tool
  honors `TMPDIR`.
- Leave task directories and their contents in place after use. Do not add
  cleanup traps, delete them automatically, or sweep other tasks' directories.
  Cleanup requires an explicit user request for a specific path.
- Scratch data is machine-local mutable state, not configuration: keep it out
  of Git and chezmoi. Do not store credentials in retained scratch files.
- This policy governs agent-created scratch work; it does not require rewriting
  existing project tests or application-managed temporary storage. Preserve
  documented test isolation and cleanup contracts.
