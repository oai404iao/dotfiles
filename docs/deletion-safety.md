# Recoverable recursive removal

`~/.local/bin/rm` is an optional user-level guard for accidental recursive
deletion. It is deployed only when the machine data key `safeRm` is `true`;
the default is `false`, so a machine without that opt-in keeps the system
`/usr/bin/rm` as `rm`.

When enabled, `~/.local/bin` is kept at the front of `PATH`, so the wrapper
also covers normal non-interactive shell scripts and Pi shell commands that
invoke `rm` by name.

The wrapper behaves as follows:

- ordinary non-recursive removal is delegated to `/usr/bin/rm`;
- `-r`, `-R`, and `--recursive` move operands to the FreeDesktop Trash through
  `gio trash`;
- relative operands remain local filesystem paths even when their names
  resemble GIO URIs;
- every operand is checked before any operand is moved;
- `/`, the account home, conventional and current XDG roots,
  `/run/user/$UID`, Pi's config/session roots, configured home Trash trees and
  their ancestors are protected;
- per-volume `.Trash/$UID` and `.Trash-$UID` trees and their containing mount
  root are protected when addressed on that filesystem;
- unknown or abbreviated options fail closed;
- filesystems without Trash support, including the usual `/tmp` and
  `/run/user/$UID` tmpfs mounts, fail closed instead of falling back to
  permanent deletion.

Recursive option parsing honors GNU `rm` ordering for `-f`, `-i`, and `-I`.
Effective interactive removal still fails closed because a Trash move cannot
represent those prompts safely. When `POSIXLY_CORRECT` is present, option
parsing stops at the first operand.

List and restore items with:

```sh
gio trash --list
gio trash --restore trash:///ITEM
```

## Enabling or disabling

`chezmoi init` records `safeRm` with a default of `false`. On an already
initialized machine, add the key with `chezmoi edit-config` instead of
rerunning `chezmoi init`: a missing key is treated as `false`, and the first
chezmoi command after a template change prints a one-time
`config file template has changed` warning. Set `safeRm = true` in the
`[data]` table, then apply the explicit target and refresh the shell command
cache:

```sh
chezmoi apply ~/.local/bin/rm
hash -r 2>/dev/null || true
rehash 2>/dev/null || true
command -v rm
```

The expected path is `~/.local/bin/rm`. Setting `safeRm = false` stops
chezmoi managing the target but leaves an existing `~/.local/bin/rm` in place,
because chezmoi does not delete targets that become ignored. Remove it
explicitly and clear the shell cache:

```sh
/usr/bin/rm ~/.local/bin/rm
hash -r 2>/dev/null || true
rehash 2>/dev/null || true
```

## Validation isolation

The automated safe-rm check uses deterministic fake commands for failure and
ordering scenarios, then runs real GIO operations with isolated HOME and XDG
state plus the local VFS backend. It verifies the payload and `.trashinfo`
metadata inside that sandbox and never reads or modifies the user's Trash.

## Intentional temporary cleanup

GIO intentionally refuses Trash operations on system-internal mounts. A script
that owns a disposable temporary directory may bypass the wrapper only after
checking a marker stored inside a captured directory:

```bash
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/my-tool.XXXXXX")"
marker="$tmp_dir/.my-tool-tmp"
: >"$marker"

cleanup() {
    if [[ -f "$marker" ]]; then
        /usr/bin/rm -rf -- "$tmp_dir"
    else
        printf 'refusing unsafe cleanup: %s\n' "$tmp_dir" >&2
        return 1
    fi
}
trap cleanup EXIT
```

Do not derive the cleanup target later from ambient XDG variables.

## Limits

This is an accident guard, not a security boundary. `/usr/bin/rm`, `sudo rm`,
another `PATH`, `find -delete`, and programs calling unlink syscalls directly
can bypass it. Path checks and GIO calls are not one atomic filesystem
operation, and a multi-operand call can be partially completed if the
filesystem changes or GIO fails during execution. Moving a top-level directory
to Trash also depends on its parent permissions, so it can succeed where GNU
`rm` would fail while traversing a protected child. Use `/usr/bin/rm` only for
an intentionally disposable, positively identified path.

The Trash layout follows the
[FreeDesktop.org Trash specification](https://specifications.freedesktop.org/trash/latest/).
