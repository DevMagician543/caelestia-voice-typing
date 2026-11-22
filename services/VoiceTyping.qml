pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.utils
import qs.services as Services
import qs.components.misc

Singleton {
    id: root

    readonly property alias prefs: preferenceAdapter
    readonly property string scripts: Quickshell.shellDir + "/scripts/voice-typing/"
    readonly property string data: Paths.data + "/voice-typing/"
    readonly property string defaultShortcut: "CTRL + SUPER + V"
    property bool sessionLocked: false
    readonly property bool reducedMotion: prefs.reduceMotion || Quickshell.env("QT_QUICK_CONTROLS_REDUCED_MOTION") === "1"
    property string state: "idle"
    property string monitorName: ""
    property string address: ""
    property string draftText: ""
    property string lastCommit: ""
    property string message: ""
    property real level: 0
    property string installedShortcut: ""
    property string bindingError: ""
    property string setupStatus: ""
    readonly property bool installing: installer.running
    readonly property bool canStop: ["starting", "listening", "transcribing"].includes(state)
    readonly property bool inSession: ["starting", "listening", "transcribing", "finishing", "cancelling"].includes(state)
    property bool pendingStart: false
    property bool pendingStop: false
    property bool retiring: false

    function setPref(key: string, value: var): void {
        if (prefs[key] === value)
            return;
        prefs[key] = value;
        store.writeAdapter();
        if (key === "enabled" || key === "shortcut")
            syncDelay.restart();
        if (key === "enabled" && !value)
            cancel();
    }

    function themeOptionsFor(id: string): var {
        return prefs.themeOptions?.[id] ?? {};
    }

    function setThemeOption(id: string, key: string, value: var): void {
        const current = themeOptionsFor(id);
        if (current[key] === value)
            return;
        const options = Object.assign({}, current);
        options[key] = value;
        const next = Object.assign({}, prefs.themeOptions);
        next[id] = options;
        prefs.themeOptions = next;
        store.writeAdapter();
    }

    function syncBindings(): void {
        if (binding.running) {
            syncDelay.restart();
            return;
        }
        binding.command = ["python3", scripts + "desktop.py", prefs.enabled ? "1" : "0", prefs.shortcut];
        binding.running = true;
    }

    function setup(): void {
        if (installing)
            return;
        setupStatus = qsTr("Downloading the local speech engine and model…");
        installer.command = ["bash", scripts + "setup.sh", prefs.model, prefs.device];
        installer.running = true;
    }

    function send(request: var): void {
        engine.write(JSON.stringify(request) + "\n");
    }

    function begin(): void {
        pendingStart = false;
        if (state !== "starting" && !pendingStop)
            return;
        send({
            action: "start", address,
            model: prefs.model, language: prefs.language, device: prefs.device,
            microphone: prefs.microphone, behavior: prefs.behavior,
            vocabulary: prefs.vocabulary, preview: true
        });
        if (pendingStop) {
            pendingStop = false;
            send({action: "stop"});
        }
    }

    function showError(detail: string): void {
        message = detail;
        draftText = "";
        lastCommit = "";
        level = 0;
        state = "error";
        closeDelay.interval = 3400;
        closeDelay.restart();
    }

    function stop(): void {
        if (!canStop)
            return;
        state = "finishing";
        level = 0;
        if (pendingStart)
            pendingStop = true;
        else
            send({action: "stop"});
    }

    function toggle(): void {
        if (!prefs.enabled || sessionLocked)
            return;
        if (canStop) {
            stop();
            return;
        }
        if (state !== "idle")
            return;
        const t = Hyprland.activeToplevel;
        const target = String(t?.address ?? "");
        address = target && !target.startsWith("0x") ? "0x" + target : target;
        monitorName = t?.monitor?.name ?? Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        draftText = "";
        lastCommit = "";
        message = "";
        level = 0;
        if (!address || address === "0x0") {
            showError(qsTr("Focus a text field before dictating"));
            return;
        }
        expiry.stop();
        state = "starting";
        if (engine.running && !retiring) {
            begin();
        } else {
            pendingStart = true;
            if (!retiring)
                engine.running = true;
        }
    }

    function cancel(): void {
        if (!inSession || state === "cancelling")
            return;
        if (pendingStart) {
            pendingStart = false;
            pendingStop = false;
            settle();
        } else {
            state = "cancelling";
            draftText = "";
            lastCommit = "";
            level = 0;
            send({action: "cancel"});
        }
    }

    function settle(): void {
        state = "idle";
        draftText = "";
        lastCommit = "";
        level = 0;
        expiry.restart();
    }

    function receive(result: var): void {
        if (result.state === "idle") {
            settle();
            return;
        }
        if (!inSession || state === "cancelling")
            return;
        if (result.state === "error") {
            showError(result.message);
            return;
        }
        if (result.state === "success" || result.state === "empty") {
            state = result.state;
            closeDelay.interval = 1050;
            closeDelay.restart();
            if (state === "success" && prefs.sounds)
                Services.Audio.playNotification();
        } else if (result.state && state !== "finishing") {
            state = result.state;
        }
        if (result.level !== undefined)
            level = state === "finishing" ? 0 : result.level;
        if (result.preview !== undefined && state !== "finishing")
            draftText = result.preview;
        if (result.committed && state !== "finishing")
            lastCommit = result.committed;
    }

    FileView {
        id: store
        path: Paths.config + "/voice-typing.json"
        watchChanges: true
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (!prefs.enabled)
                root.cancel();
        }

        JsonAdapter {
            id: preferenceAdapter
            property bool enabled: true
            property string shortcut: root.defaultShortcut
            property string microphone: ""
            property string language: ""
            property string model: "large-v3-turbo"
            property string device: "auto"
            property bool preview: true
            property bool waveform: true
            property string position: "bottom"
            property bool sounds: false
            property string behavior: "balanced"
            property string vocabulary: ""
            property bool reduceMotion: false
            property string theme: "dynamic-wave"
            property int widgetScale: 100
            property int animationSpeed: 100
            property var themeOptions: ({})

            onEnabledChanged: syncDelay.restart()
            onShortcutChanged: syncDelay.restart()
        }
    }

    Timer { id: syncDelay; interval: 240; onTriggered: root.syncBindings() }
    Timer { id: closeDelay; onTriggered: root.settle() }
    Timer {
        id: expiry
        interval: 180000
        onTriggered: {
            if (engine.running && root.state === "idle") {
                root.retiring = true;
                root.send({action: "quit"});
            }
        }
    }

    Process {
        id: binding
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    root.bindingError = result.error ?? "";
                    if (result.error)
                        console.warn("Voice Typing shortcut:", result.error);
                    else
                        root.installedShortcut = result.shortcut ?? "";
                } catch (error) {
                    root.bindingError = qsTr("Unable to read Hyprland binding status");
                }
            }
        }
        onExited: code => {
            if (code)
                root.bindingError = qsTr("Unable to install Hyprland bindings");
        }
    }

    Process {
        id: engine
        stdinEnabled: true
        command: ["bash", root.scripts + "run.sh", root.data, root.scripts + "backend.py"]
        onStarted: if (root.pendingStart) root.begin()
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.receive(JSON.parse(line));
                } catch (error) {
                    root.showError(qsTr("The speech engine sent an invalid response"));
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("Voice Typing worker:", line)
        }
        onExited: (code, status) => {
            if (root.retiring) {
                root.retiring = false;
                if (root.pendingStart)
                    Qt.callLater(() => { if (root.pendingStart) engine.running = true; });
                return;
            }
            root.pendingStart = false;
            root.pendingStop = false;
            if (root.inSession) {
                console.warn("Voice Typing worker exited", code, status);
                root.showError(qsTr("The speech engine stopped unexpectedly"));
            }
        }
    }

    Process {
        id: installer
        onExited: code => root.setupStatus = code === 0
            ? qsTr("The local speech model is installed")
            : qsTr("Setup failed. Check network access or the setup command in the Voice Typing guide")
    }

    CustomShortcut {
        name: "voiceTypingStop"
        description: "Finish Voice Typing"
        onPressed: root.stop()
    }

    IpcHandler {
        target: "voiceTyping"
        function toggle(): void { root.toggle(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.cancel(); }
        function status(): string {
            return JSON.stringify({state: root.state, shortcut: root.installedShortcut,
                                   error: root.bindingError || root.message});
        }
    }

    onSessionLockedChanged: if (sessionLocked) cancel()
    Connections {
        target: Services.Hypr
        function onConfigReloaded(): void { syncDelay.restart(); }
    }

    Component.onCompleted: syncDelay.start()
}
