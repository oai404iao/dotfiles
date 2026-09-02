#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if ! command -v uv >/dev/null 2>&1; then
    printf 'Missing uv. Install the Arch package with: sudo pacman -S uv\n' >&2
    exit 1
fi

printf 'Creating uv-managed Longshot environment at %s\n' "$LONGSHOT_VENV_DIR"

# Keep the environment outside XDG_CONFIG_HOME and use uv's managed Python
# instead of Arch's rolling system interpreter.
export UV_PROJECT_ENVIRONMENT="$LONGSHOT_VENV_DIR"
uv sync \
    --project "$SCRIPT_DIR" \
    --frozen \
    --managed-python \
    --python 3.12

if ! longshot_python_healthy; then
    printf 'Longshot environment health check failed.\n' >&2
    exit 1
fi

"$LONGSHOT_VENV_PYTHON" - <<'PY'
import cv2
import numpy

print(f"OpenCV {cv2.__version__}")
print(f"NumPy {numpy.__version__}")
PY

printf 'Longshot environment is ready.\n'
