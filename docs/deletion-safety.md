# Recoverable recursive removal

`~/.local/bin/rm` is a user-level guard for accidental recursive deletion.
Because `~/.local/bin` is kept at the front of `PATH`, it also covers normal
non-interactive shell scripts and Pi shell commands that invoke `rm` by name.

The wrapper behaves as follows:

- ordinary non-recursive removal is delegated to `/usr/bin/rm`;
- `-r`, `-R`, and `--recursive` move operands to the FreeDesktop Trash through
  `gio trash`;
- every operand is checked before any operand is moved;
- `/`, the account home, conventional and current XDG roots,
  `/run/user/$UID`, Pi's config/session roots, the Trash, and their ancestors
  are protected;
- unknown or abbreviated options fail closed;
- filesystems without Trash support, including the usual `/tmp` and
  `/run/user/$UID` tmpfs mounts, fail closed instead of falling back to
  permanent deletion.

List and restore items with:

```sh
gio trash --list
gio trash --restore trash:///ITEM
```

After the first apply, start a new shell or clear its command cache:

```sh
hash -r 2>/dev/null || true
rehash 2>/dev/null || true
command -v rm
```

The expected path is `~/.local/bin/rm`.

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
