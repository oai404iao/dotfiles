#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

python3 - <<'PY'
import base64
import binascii
import pathlib
import re
import shutil
import subprocess

email_re = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
id_noreply_re = re.compile(
    r"\d+\+[^@\s]+@users\.noreply\.github\.com",
    re.IGNORECASE,
)
public_key_re = re.compile(
    rb"(?mi)^(?![ \t]*#).{0,4096}?"
    rb"(?:ssh-(?:dss|rsa|ed25519)"
    rb"|ecdsa-sha2-nistp\d+"
    rb"|sk-(?:ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)"
    rb"(?:-cert-v01@openssh\.com)?[ \t]+[A-Za-z0-9+/=]{32,}(?:[ \t]|$)"
)
age_key_re = re.compile(
    rb"(?mi)^AGE-(?:SECRET-KEY|PLUGIN-[A-Z0-9-]+)-[A-Z0-9]{40,}\s*$"
)
pem_key_re = re.compile(rb"(?mi)^-----BEGIN [^-]*PRIVATE KEY[^-]*-----\s*$")
pgp_key_re = re.compile(rb"(?mi)^-----BEGIN PGP PRIVATE KEY BLOCK-----\s*$")
ssh2_key_re = re.compile(rb"(?mi)^---- BEGIN SSH2 PUBLIC KEY ----\s*$")
ssh2_private_key_re = re.compile(
    rb"(?mi)^---- BEGIN SSH2 (?:ENCRYPTED )?PRIVATE KEY ----\s*$"
)
putty_key_re = re.compile(rb"(?mi)^PuTTY-User-Key-File-\d+:[ \t]*")
pem_public_key_re = re.compile(
    rb"(?mi)^-----BEGIN (?:RSA |DSA |EC )?PUBLIC KEY-----\s*$"
)
ssh_inventory_re = re.compile(
    rb"(?mi)^[ \t]*(?:HostName|User|Port|IdentityFile)[ \t]+"
)
ssh_host_re = re.compile(rb"(?mi)^[ \t]*Host[ \t]+(?!\*[ \t]*$)")
git_route_re = re.compile(
    rb'(?mi)^[ \t]*(?:\[url[ \t]+"[^"]+"\]|insteadOf[ \t]*=)'
)
allowed_emails = {
    b"git@github.com",
    b"x@y.com",
}


def git_bytes(*args: str) -> bytes:
    return subprocess.check_output(("git", "--no-replace-objects", *args))


def check_email(email: bytes, context: str) -> None:
    lowered = email.lower()
    if (
        lowered in allowed_emails
        or lowered.endswith(b"@example.invalid")
        or lowered.endswith(b"@users.noreply.github.com")
    ):
        return
    raise SystemExit(f"non-public email in {context}")


def valid_age_envelope(data: bytes) -> bool:
    lines = data.splitlines()
    if (
        len(lines) < 4
        or lines[0] != b"-----BEGIN AGE ENCRYPTED FILE-----"
        or lines[-1] != b"-----END AGE ENCRYPTED FILE-----"
        or any(
            not re.fullmatch(rb"[A-Za-z0-9+/=]{1,64}", line)
            for line in lines[1:-1]
        )
    ):
        return False
    try:
        payload = base64.b64decode(b"".join(lines[1:-1]), validate=True)
    except (ValueError, binascii.Error):
        return False
    header, separator, body = payload.partition(b"\n--- ")
    if not separator or len(body) < 17:
        return False
    mac, separator, encrypted_body = body.partition(b"\n")
    if (
        not separator
        or not re.fullmatch(rb"[A-Za-z0-9+/]{43}", mac)
        or len(encrypted_body) < 16
    ):
        return False
    header_lines = header.splitlines()
    if (
        not header_lines
        or header_lines[0] != b"age-encryption.org/v1"
        or not any(line.startswith(b"-> ") for line in header_lines[1:])
    ):
        return False
    for line in header_lines[1:]:
        if line.startswith(b"-> "):
            if not re.fullmatch(rb"-> [\x20-\x7e]+", line):
                return False
        elif not re.fullmatch(rb"[A-Za-z0-9+/]+={0,2}", line):
            return False
    return subprocess.run(
        ("age-inspect", "--json", "-"),
        input=data,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def check_blob(path: str, data: bytes, context: str) -> None:
    if (
        age_key_re.search(data)
        or pem_key_re.search(data)
        or pgp_key_re.search(data)
        or ssh2_private_key_re.search(data)
        or putty_key_re.search(data)
    ):
        raise SystemExit(f"private-key material in {context}: {path}")
    if path.endswith(".age"):
        if not valid_age_envelope(data):
            raise SystemExit(f"invalid age ciphertext in {context}: {path}")
        return
    if (
        public_key_re.search(data)
        or ssh2_key_re.search(data)
        or pem_public_key_re.search(data)
    ):
        raise SystemExit(f"plaintext SSH public key in {context}: {path}")
    for email in email_re.findall(data):
        check_email(email, f"{context} path {path}")
    if path.startswith("private_dot_ssh/"):
        if ssh_inventory_re.search(data) or ssh_host_re.search(data):
            raise SystemExit(f"plaintext SSH inventory in {context}: {path}")
    if path == "dot_gitconfig" or path.startswith("dot_config/git/"):
        if git_route_re.search(data):
            raise SystemExit(f"plaintext Git account routing in {context}: {path}")


def require_rejected(path: str, data: bytes) -> None:
    try:
        check_blob(path, data, "scanner regression fixture")
    except SystemExit:
        return
    raise SystemExit(f"public scanner accepted unsafe fixture: {path}")


require_rejected(
    "fixture.pem",
    b"-----BEGIN " + b"ENCRYPTED PRIVATE KEY-----\nfixture\n",
)
require_rejected(
    "fixture.asc",
    b"-----BEGIN PGP " + b"PRIVATE KEY BLOCK-----\nfixture\n",
)
require_rejected(
    "fixture.txt",
    b"AGE-PLUGIN-" + b"FIXTURE-" + b"A" * 40 + b"\n",
)
require_rejected(
    "fixture.ppk",
    b"PuTTY-" + b"User-Key-File-1: ssh-ed25519\n",
)
require_rejected(
    "fixture.ssh2",
    b"---- BEGIN SSH2 " + b"ENCRYPTED PRIVATE KEY ----\n",
)
require_rejected(
    "fixture.pem",
    b"-----BEGIN RSA " + b"PUBLIC KEY-----\n",
)
require_rejected(
    "authorized_keys",
    b'restrict,command="fixture" '
    + b"ecdsa-sha2-nistp256 "
    + b"A" * 64
    + b" fixture\n",
)
require_rejected(
    "authorized_keys",
    b"sk-ssh-ed25519" + b"@" + b"openssh.com " + b"A" * 64 + b" fixture\n",
)
require_rejected(
    "fixture.age",
    b"-----BEGIN AGE ENCRYPTED FILE-----\n"
    + b"A" * 64
    + b"\n-----END AGE ENCRYPTED FILE-----\nplaintext\n",
)
non_age_payload = base64.b64encode(b"not an age payload" * 8)
require_rejected(
    "fixture.age",
    b"-----BEGIN AGE ENCRYPTED FILE-----\n"
    + b"\n".join(
        non_age_payload[index : index + 64]
        for index in range(0, len(non_age_payload), 64)
    )
    + b"\n-----END AGE ENCRYPTED FILE-----\n",
)
require_rejected(
    "dot_config/git/profile",
    b'[url "ssh://git@github-fixture/"]\n'
    b"\tinsteadOf = git@github.com:\n",
)
require_rejected(
    ".git-tag-object",
    b"object " + b"0" * 40 + b"\ntype commit\ntag fixture\n\n"
    b"-----BEGIN " + b"ENCRYPTED PRIVATE KEY-----\nfixture\n",
)


if git_bytes("for-each-ref", "--format=%(refname)", "refs/replace").strip():
    raise SystemExit("Git replacement refs are forbidden during public audit")
if shutil.which("age-inspect") is None:
    raise SystemExit("age-inspect is required for public ciphertext validation")
grafts_path = pathlib.Path(
    git_bytes("rev-parse", "--git-path", "info/grafts").decode().strip()
)
if grafts_path.is_file() and grafts_path.read_bytes().strip():
    raise SystemExit("Git grafts are forbidden during public audit")


history_identities = git_bytes(
    "log",
    "--format=%an%x00%ae%x00%cn%x00%ce%x00",
    "--all",
).decode("utf-8", "strict").split("\0")
for index in range(0, len(history_identities) - 1, 4):
    author_name, author_email, committer_name, committer_email = (
        history_identities[index : index + 4]
    )
    if not author_name or not committer_name:
        raise SystemExit("empty Git history identity")
    if not id_noreply_re.fullmatch(author_email):
        raise SystemExit("Git author history does not use an ID-based noreply email")
    if not id_noreply_re.fullmatch(committer_email):
        raise SystemExit(
            "Git committer history does not use an ID-based noreply email"
        )

for message in git_bytes("log", "--format=%B%x00", "--all").split(b"\0"):
    if (
        age_key_re.search(message)
        or pem_key_re.search(message)
        or pgp_key_re.search(message)
        or ssh2_private_key_re.search(message)
        or putty_key_re.search(message)
    ):
        raise SystemExit("private-key material in Git commit message")
    if (
        public_key_re.search(message)
        or ssh2_key_re.search(message)
        or pem_public_key_re.search(message)
    ):
        raise SystemExit("plaintext SSH public key in Git commit message")
    for email in email_re.findall(message):
        check_email(email, "Git commit message")

seen = set()
commits = git_bytes("rev-list", "--all").decode().splitlines()
for commit in commits:
    for entry in git_bytes("ls-tree", "-r", "-z", commit).split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        object_id = metadata.split()[2].decode()
        path = raw_path.decode("utf-8", "surrogateescape")
        key = (object_id, path)
        if key in seen:
            continue
        seen.add(key)
        check_blob(
            path,
            git_bytes("cat-file", "blob", object_id),
            "Git history",
        )

for entry in git_bytes("ls-files", "-s", "-z").split(b"\0"):
    if not entry:
        continue
    metadata, raw_path = entry.split(b"\t", 1)
    object_id = metadata.split()[1].decode()
    if set(object_id) == {"0"}:
        continue
    path = raw_path.decode("utf-8", "surrogateescape")
    check_blob(path, git_bytes("cat-file", "blob", object_id), "Git index")

worktree_paths = (
    git_bytes("ls-files", "-z").split(b"\0")
    + git_bytes("ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
)
for raw_path in worktree_paths:
    if not raw_path:
        continue
    path = raw_path.decode("utf-8", "surrogateescape")
    source = pathlib.Path(path)
    if source.is_file():
        check_blob(path, source.read_bytes(), "working tree")

seen_tags = set()
for object_id in git_bytes(
    "for-each-ref",
    "--format=%(objectname)",
).decode().splitlines():
    while git_bytes("cat-file", "-t", object_id).strip() == b"tag":
        if object_id in seen_tags:
            break
        seen_tags.add(object_id)
        tag = git_bytes("cat-file", "tag", object_id)
        check_blob(
            ".git-tag-object",
            tag,
            "annotated tag reachable from a local ref",
        )
        first_line = tag.partition(b"\n")[0]
        if not re.fullmatch(rb"object [0-9a-f]{40,64}", first_line):
            raise SystemExit("malformed annotated tag target")
        object_id = first_line.split()[1].decode()
PY

printf '%s\n' "public-source checks passed"
