#!/bin/bash
set -euo pipefail

data="$1"
backend="$2"
python="$data/venv/bin/python"
if [[ ! -x "$python" ]]; then
    exec python3 -u "$backend"
fi

# CTranslate2 can use either system CUDA libraries or wheels in this environment.
for package in "$data"/venv/lib/python*/site-packages/nvidia/{cublas,cudnn}/lib; do
    if [[ -d "$package" ]]; then
        export LD_LIBRARY_PATH="$package${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
done
exec "$python" -u "$backend"
