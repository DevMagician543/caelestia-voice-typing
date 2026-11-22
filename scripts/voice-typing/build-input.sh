#!/bin/bash
set -euo pipefail

scripts="$(cd -- "$(dirname -- "$0")" && pwd)"
data="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/voice-typing}"
mkdir -p "$data"
work="$(mktemp -d "$data/.input-build.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

protocol="$scripts/virtual-keyboard-unstable-v1.xml"
wayland-scanner client-header "$protocol" "$work/virtual-keyboard.h"
wayland-scanner private-code "$protocol" "$work/virtual-keyboard.c"
read -r -a flags <<< "$(pkg-config --cflags --libs wayland-client xkbcommon)"
cc -std=c11 -Wall -Wextra -Werror -O2 -I "$work" "$scripts/type-text.c" "$work/virtual-keyboard.c" "${flags[@]}" -o "$work/type-text"
mv -f -- "$work/type-text" "$data/type-text"
