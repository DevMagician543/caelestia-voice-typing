#!/bin/bash
set -euo pipefail

data="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/voice-typing"
model="${1:-large-v3-turbo}"
device="${2:-auto}"
case "$model" in
    tiny|base|small|medium|large-v3-turbo) ;;
    *) printf 'Unknown model: %s\n' "$model" >&2; exit 2 ;;
esac

scripts="$(cd -- "$(dirname -- "$0")" && pwd)"
bash "$scripts/build-input.sh" "$data"

mkdir -p "$data/models"
exec 9>"$data/setup.lock"
flock 9
if [[ ! -x "$data/venv/bin/python" ]]; then
    uv venv --python 3.13 "$data/venv"
fi
if ! "$data/venv/bin/python" -c 'import faster_whisper; assert faster_whisper.__version__ == "1.2.1"' 2>/dev/null; then
    uv pip install --python "$data/venv/bin/python" 'faster-whisper==1.2.1'
fi

HF_HUB_DISABLE_TELEMETRY=1 "$data/venv/bin/python" - "$model" "$data/models" <<'PY'
from pathlib import Path
import os
import sys
import tempfile
from faster_whisper.utils import download_model

name, directory = sys.argv[1:]
directory = Path(directory)
target = directory / name
files = ("model.bin", "config.json", "tokenizer.json", "preprocessor_config.json")
if all((target / filename).is_file() for filename in files):
    raise SystemExit(0)
# Existing models are left in place until the download finishes.
with tempfile.TemporaryDirectory(prefix=".download-", dir=directory) as work:
    download_model(name, output_dir=work)
    for filename in files[:3]:
        if not (Path(work) / filename).is_file():
            raise RuntimeError("The downloaded model is incomplete")
    target.mkdir(exist_ok=True)
    for file in Path(work).iterdir():
        if file.is_file():
            os.replace(file, target / file.name)
PY

# Install local CUDA libraries only on a host with an accessible NVIDIA GPU.
# A failed optional install leaves the offline CPU model usable.
if [[ "$device" != cpu ]] && command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
    if ! "$data/venv/bin/python" - 2>/dev/null <<'PY'
from ctypes import CDLL
from importlib.metadata import version

try:
    CDLL("libcublas.so.12")
    CDLL("libcudnn.so.9")
except OSError:
    version("nvidia-cublas-cu12")
    version("nvidia-cudnn-cu12")
PY
    then
        uv pip install --python "$data/venv/bin/python" 'nvidia-cublas-cu12' 'nvidia-cudnn-cu12>=9,<10' ||
            printf 'CUDA library installation failed. Voice Typing will use CPU.\n' >&2
    fi
fi
