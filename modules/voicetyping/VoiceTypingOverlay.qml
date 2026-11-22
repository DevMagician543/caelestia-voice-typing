pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: overlay

    readonly property ThemeDefinition selected: ThemeRegistry.resolve(VoiceTyping.prefs.theme)
    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData
            readonly property bool topPosition: VoiceTyping.prefs.position === "top"
            readonly property string phase: VoiceTyping.state
            readonly property bool active: phase !== "idle" && phase !== "cancelling"
            readonly property bool shown: active && !VoiceTyping.sessionLocked && VoiceTyping.monitorName === modelData.name
            readonly property ThemeDefinition desired: overlay.selected
            readonly property real sizeFactor: Math.max(0.75, Math.min(1.35, VoiceTyping.prefs.widgetScale / 100))
            readonly property real motionSpeed: Math.max(0.5, Math.min(1.5, VoiceTyping.prefs.animationSpeed / 100))
            property ThemeDefinition currentTheme: ThemeRegistry.resolve(VoiceTyping.prefs.theme)
            property string displayPhase: "listening"

            function switchTheme(): void {
                exchange.stop();
                if (!shown || VoiceTyping.reducedMotion) {
                    currentTheme = desired;
                    contentHost.opacity = 1;
                } else {
                    exchange.restart();
                }
            }

            onDesiredChanged: switchTheme()
            onPhaseChanged: if (active) displayPhase = phase
            onShownChanged: {
                if (shown) {
                    displayPhase = phase;
                } else if (exchange.running) {
                    exchange.stop();
                    currentTheme = desired;
                    contentHost.opacity = 1;
                }
            }

            screen: modelData
            name: "voice-typing"
            visible: !VoiceTyping.sessionLocked && (shown || positioner.opacity > 0.01)
            implicitWidth: Math.min(modelData.width, currentTheme.width * sizeFactor)
            implicitHeight: currentTheme.height * sizeFactor
            surfaceFormat.opaque: false
            mask: Region {}
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.layer: WlrLayer.Overlay
            anchors.top: topPosition
            anchors.bottom: !topPosition
            margins.top: Config.bar.position === "top" ? 34 : 7
            margins.bottom: Config.bar.position === "bottom" ? 34 : 7

            ThemePresentation {
                id: presentation

                phase: win.displayPhase
                draftText: VoiceTyping.draftText
                committedText: VoiceTyping.lastCommit
                message: VoiceTyping.message
                level: VoiceTyping.level
                presented: win.shown && !exchange.running
                reduceMotion: VoiceTyping.reducedMotion
                animationSpeed: win.motionSpeed
                options: VoiceTyping.themeOptionsFor(win.currentTheme.themeId)
                showPreview: options.preview ?? VoiceTyping.prefs.preview
                showWaveform: options.waveform ?? VoiceTyping.prefs.waveform
            }

            Item {
                id: positioner

                anchors.centerIn: parent
                width: win.width / win.sizeFactor
                height: win.height / win.sizeFactor
                opacity: win.shown ? 1 : 0
                scale: win.sizeFactor * (win.shown || presentation.reduceMotion ? 1 : win.currentTheme.entranceScale)
                transform: Translate {
                    y: win.shown || presentation.reduceMotion ? 0 : win.topPosition ? -15 : 15

                    Behavior on y {
                        enabled: !presentation.reduceMotion
                        Anim {
                            type: Anim.DefaultSpatial
                            duration: Math.round(Tokens.anim.durations.expressiveDefaultSpatial / win.motionSpeed)
                        }
                    }
                }

                Behavior on opacity {
                    enabled: !presentation.reduceMotion
                    Anim {
                        type: Anim.FastEffects
                        duration: Math.round(Tokens.anim.durations.expressiveFastEffects / win.motionSpeed)
                    }
                }
                Behavior on scale {
                    enabled: !presentation.reduceMotion
                    Anim {
                        type: Anim.DefaultSpatial
                        duration: Math.round(Tokens.anim.durations.expressiveDefaultSpatial / win.motionSpeed)
                    }
                }

                ThemeHost {
                    id: contentHost

                    anchors.fill: parent
                    presentation: presentation
                    source: win.visible ? win.currentTheme.widget : null
                }
            }

            SequentialAnimation {
                id: exchange

                NumberAnimation {
                    target: contentHost
                    property: "opacity"
                    to: 0
                    duration: Math.round(120 / win.motionSpeed)
                    easing.type: Easing.InCubic
                }
                ScriptAction { script: win.currentTheme = win.desired }
                NumberAnimation {
                    target: contentHost
                    property: "opacity"
                    to: 1
                    duration: Math.round(200 / win.motionSpeed)
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
