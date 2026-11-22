"""Install user-scoped Hyprland shortcuts and report live conflicts."""

import json
import re
import subprocess
import sys

MODIFIERS = {"SUPER": 64, "ALT": 8, "SHIFT": 1, "CTRL": 4}
TOGGLE = "Caelestia Voice Typing toggle"
STOP = "Caelestia Voice Typing stop"
LEGACY_CANCEL = "Caelestia Voice Typing cancel"


def parse(chord):
    parts = [part.strip().upper() for part in chord.split("+")]
    modifiers, key = parts[:-1], parts[-1]
    if (not modifiers or len(set(modifiers)) != len(modifiers)
            or any(modifier not in MODIFIERS for modifier in modifiers)
            or not re.fullmatch(r"[A-Z0-9]|F(?:[1-9]|1[0-9]|2[0-4])", key)
            or not any(modifier != "SHIFT" for modifier in modifiers)):
        raise ValueError("Use Super, Alt or Ctrl with a letter, digit or F1–F24")
    ordered = [modifier for modifier in MODIFIERS if modifier in modifiers]
    return " + ".join(ordered + [key]), sum(MODIFIERS[modifier] for modifier in ordered), key


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=3)
    if result.returncode:
        raise OSError("Hyprland IPC is unavailable")
    return result.stdout.strip()


def install(enabled, shortcut):
    chord, mask, key = parse(shortcut) if enabled else ("", 0, "")
    binds = json.loads(hypr("-j", "binds"))
    owned = [bind for bind in binds if bind.get("description") in {TOGGLE, STOP, LEGACY_CANCEL}]
    if enabled:
        for bind in binds:
            if bind in owned or bind.get("submap") not in (None, "", "reset"):
                continue
            binding_key = bind.get("key", "").upper()
            same_mask = bind.get("modmask") == mask or bind.get("ignore_mods", False)
            if (same_mask and (binding_key == key or (not binding_key and bind.get("keycode")))):
                raise ValueError(f"{chord} conflicts with {bind.get('description') or bind.get('dispatcher') or 'a keycode binding'}")
            if binding_key == "ESCAPE" and (bind.get("modmask") == 0 or bind.get("ignore_mods", False)):
                raise ValueError("Escape already has a global Hyprland binding")
    commands = []
    for bind in owned:
        old_key = bind.get("key", "")
        old_mask = bind.get("modmask", 0)
        modifiers = [mod for mod, bit in MODIFIERS.items() if old_mask & bit]
        old_chord = " + ".join(modifiers + [old_key])
        if any(other not in owned and other.get("key", "").lower() == old_key.lower()
               and other.get("modmask") == old_mask
               and other.get("submap") == bind.get("submap") for other in binds):
            raise ValueError(f"{old_chord} is shared by another binding")
        commands.append(f"hl.unbind({json.dumps(old_chord)})")
    if enabled:
        commands.extend([
            f'hl.bind({json.dumps(chord)}, hl.dsp.exec_cmd("qs -c caelestia ipc call voiceTyping toggle"), '
            f'{{ description = "{TOGGLE}" }})',
            f'hl.bind("Escape", hl.dsp.global("caelestia:voiceTypingStop"), '
            f'{{ non_consuming = true, description = "{STOP}" }})',
        ])
    if commands:
        response = hypr("eval", "\n".join(commands))
        if response.lower() != "ok":
            raise OSError(f"Hyprland rejected the Voice Typing bindings: {response}")
    return chord


if __name__ == "__main__":
    try:
        print(json.dumps({"shortcut": install(sys.argv[1] == "1", sys.argv[2])}))
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"error": str(error)}))
