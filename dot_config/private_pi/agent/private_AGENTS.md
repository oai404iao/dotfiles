# Global Agent Instructions

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
