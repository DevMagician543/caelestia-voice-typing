#!/usr/bin/env python3
"""Install the Voice Typing add-on into a user-owned MiDnight configuration."""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
from tempfile import NamedTemporaryFile, mkdtemp


PROJECT = Path(__file__).resolve().parent
SHELL = Path("shell.qml")
REGISTRY = Path("modules/nexus/PageCompRegistry.qml")
SERVICES = Path("modules/nexus/pages/ServicesPage.qml")
VOICE_IMPORT = 'import "modules/voicetyping"\n'
VOICE_COMPONENT = "    VoiceTypingOverlay {}\n"
LOCK_BINDING = """    Binding {
        target: VoiceTyping
        property: "sessionLocked"
        value: lock.lock.locked
    }
"""
NAV_ROW = """        NavRow {{
            icon: "mic"
            text: qsTr("Voice Typing")
            subtext: qsTr("Offline dictation, microphone and language")
            onClicked: root.nState.openSubPage({index})
        }}

"""


def insert_before(text, anchor, addition):
    if text.count(anchor) != 1:
        raise ValueError(f"Expected exactly one MiDnight integration point: {anchor.strip()}")
    return text.replace(anchor, addition + anchor, 1)


def shell_integration(shell, lock):
    if "property alias lock: lock" not in lock or not re.search(
        r"(?m)^    Lock \{\s+id: lock\b", shell
    ):
        raise ValueError("Could not find MiDnight's session lock")
    if VOICE_IMPORT not in shell:
        shell = insert_before(shell, 'import "modules/lock"\n', VOICE_IMPORT)
    if VOICE_COMPONENT not in shell:
        shell = insert_before(shell, "    Lock {\n", VOICE_COMPONENT)
    if LOCK_BINDING not in shell:
        shell = insert_before(shell, VOICE_COMPONENT, LOCK_BINDING)
    return shell


def settings_integration(registry, services):
    stack = list(re.finditer(
        r"(?m)^            StackPage \{\n(?P<pages>[\s\S]*?)^            \}", registry
    ))
    matches = [match for match in stack if "ServicesPage {}" in match["pages"]]
    if len(matches) != 1:
        raise ValueError("Could not locate the Nexus Services page stack")
    match = matches[0]
    pages = re.findall(r"(?m)^                    (\w+) \{\}\s*$", match["pages"])
    if not pages or pages[0] != "ServicesPage":
        raise ValueError("Unexpected Services page layout")
    voice_page = "                Component {\n                    VoiceTypingPage {}\n                }\n"
    if "VoiceTypingPage" in pages:
        index = pages.index("VoiceTypingPage")
    else:
        index = len(pages)
        end = match.end("pages")
        registry = registry[:end] + voice_page + registry[end:]

    row, replaced = re.subn(
        r'(?m)(^            text: qsTr\("Voice Typing"\)\n'
        r'[^\n]*\n            onClicked: root\.nState\.openSubPage\()\d+(\))',
        lambda match: f"{match[1]}{index}{match[2]}",
        services,
    )
    if replaced == 0:
        if '"Voice Typing"' in services:
            raise ValueError("A custom Voice Typing settings entry is already present")
        anchor = '        SelectRow {\n            Layout.fillWidth: true\n            last: true\n            label: Tr.tr("GPU")'
        row = insert_before(services, anchor, NAV_ROW.format(index=index))
    return registry, row


def install(target, dry_run):
    shell = target / SHELL
    registry = target / REGISTRY
    services = target / SERVICES
    if not all(path.is_file() for path in (shell, registry, services)):
        raise ValueError(f"No compatible MiDnight configuration found at {target}")

    new_shell = shell_integration(
        shell.read_text(encoding="utf-8"),
        (target / "modules/lock/Lock.qml").read_text(encoding="utf-8"),
    )
    new_registry, new_services = settings_integration(
        registry.read_text(encoding="utf-8"), services.read_text(encoding="utf-8")
    )
    changes = {}
    for directory in ("modules", "scripts", "services"):
        for source in (PROJECT / directory).rglob("*"):
            if source.is_file() and source.suffix in {".qml", ".frag", ".qsb", ".md", ".py", ".sh", ".c", ".xml"}:
                changes[source.relative_to(PROJECT)] = source.read_bytes()
    changes.update({
        REGISTRY: new_registry.encode(),
        SERVICES: new_services.encode(),
        SHELL: new_shell.encode(),
    })

    for relative in changes:
        destination = target / relative
        if not destination.resolve().is_relative_to(target) or destination.is_symlink():
            raise ValueError(f"Refusing to replace linked path {destination}")
        if destination.exists() and not destination.is_file():
            raise ValueError(f"Expected a file at {destination}")
    pending = {
        path: content for path, content in changes.items()
        if not (target / path).is_file() or (target / path).read_bytes() != content
    }
    if not pending:
        print("Voice Typing is up to date.")
        return
    if dry_run:
        for path in sorted(pending):
            print(path)
        return

    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    backups = state / "caelestia/voice-typing-backups"
    backups.mkdir(parents=True, exist_ok=True)
    backup = Path(mkdtemp(prefix="before-install-", dir=backups))
    for path in pending:
        if (target / path).is_file():
            (backup / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target / path, backup / path)
    for path, content in pending.items():
        destination = target / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        mode = stat.S_IMODE(destination.stat().st_mode) if destination.exists() else 0o644
        with NamedTemporaryFile(dir=destination.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                output.write(content)
                output.close()
                temporary.chmod(mode)
                temporary.replace(destination)
            finally:
                temporary.unlink(missing_ok=True)
    print(f"Installed Voice Typing into {target}\nPrevious files backed up to {backup}")


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell-dir", type=Path, default=config / "quickshell/caelestia")
    parser.add_argument("--dry-run", action="store_true", help="list changes without applying them")
    args = parser.parse_args()
    try:
        install(args.shell_dir.expanduser().resolve(), args.dry_run)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
