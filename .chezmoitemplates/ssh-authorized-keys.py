{{- if not (has .identity (list "private" "uni")) -}}
{{-   fail "authorized_keys requires sshInboundIdentity private or uni" -}}
{{- end -}}
{{- $keys := list (get .keys .identity) -}}
{{- if and (eq .identity "private") (eq .hostname .keys.mobileHost) -}}
{{-   $keys = concat $keys .keys.mobile -}}
{{- end -}}
#!/usr/bin/env python3
import base64
import hashlib
import os
import subprocess
import sys

managed = {{ $keys | toJson }}
current = sys.stdin.buffer.read()

# Match existing keys even if their comments differ or options restrict them.
result = subprocess.run(
    ["ssh-keygen", "-l", "-E", "sha256", "-f", "/dev/stdin"],
    input=current, capture_output=True, env={**os.environ, "LC_ALL": "C"},
)
if result.returncode and not (
    result.returncode == 255 and result.stderr.strip() == b"/dev/stdin is not a public key file."
):
    sys.exit("could not inspect existing authorized_keys")
present = {line.split()[1] for line in result.stdout.splitlines()}

missing = []
for key in managed:
    blob = base64.b64decode(key.split()[1], validate=True)
    fingerprint = b"SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).rstrip(b"=")
    if fingerprint not in present:
        missing.append(key.encode())
        present.add(fingerprint)

sys.stdout.buffer.write(current)
if missing:
    if current and not current.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.write(b"\n".join(missing) + b"\n")
