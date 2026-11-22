pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property string phase
    required property string caption
    required property bool draft
    required property real level
    required property bool showWaveform
    required property bool reduceMotion
    required property bool presented
    required property real availableWidth

    readonly property bool listening: phase === "listening" || phase === "transcribing"
    readonly property bool busy: phase === "starting" || phase === "finishing"
    readonly property bool failed: phase === "error"
    readonly property bool complete: phase === "success"
    readonly property bool waveformActive: listening && showWaveform
    readonly property string status: {
        switch (phase) {
        case "starting": return qsTr("Starting microphone")
        case "finishing": return qsTr("Finishing dictation")
        case "success": return qsTr("Inserted")
        case "empty": return qsTr("No speech detected")
        case "error": return qsTr("Voice Typing")
        default: return qsTr("Listening")
        }
    }
    readonly property color accent: failed ? Colours.palette.m3error
        : complete ? Colours.palette.m3success : Colours.palette.m3primary
    readonly property int meterWidth: 30
    readonly property real minimumWidth: 24 + textMetrics.advanceWidth + glyph.implicitWidth
        + 2 * Tokens.padding.medium + Tokens.spacing.medium
        + (waveformActive || busy ? meterWidth + Tokens.spacing.medium : 0)

    implicitWidth: Math.min(availableWidth, caption ? 374 : Math.max(148, minimumWidth))
    implicitHeight: failed && caption ? 56 : 42

    TextMetrics {
        id: textMetrics
        font: Tokens.font.label.large
        text: root.status
    }

    Elevation {
        anchors.fill: plate
        radius: plate.radius
        level: 2
        z: -1
    }

    StyledRect {
        id: plate

        anchors.fill: parent
        radius: Math.min(height / 2, Tokens.rounding.large)
        readonly property color baseColour: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.97)
        color: Colours.surface?.(baseColour) ?? baseColour
        border.width: 1
        border.color: Qt.alpha(root.failed ? root.accent : Colours.palette.m3outline, root.failed ? 0.42 : 0.24)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                id: glyph

                Layout.alignment: Qt.AlignVCenter
                fontStyle: Tokens.font.icon.medium
                fill: root.listening || root.complete ? 1 : 0
                color: root.accent
                animate: root.presented && !root.reduceMotion
                text: root.failed ? "error" : root.complete ? "check"
                    : root.phase === "empty" ? "mic_off" : "mic"
                scale: root.waveformActive && !root.reduceMotion ? 1 + root.level * 0.10 : 1

                Behavior on scale {
                    enabled: !root.reduceMotion
                    Anim { type: Anim.FastSpatial }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.caption || root.status
                font: root.listening && root.caption ? Tokens.font.body.small : Tokens.font.label.large
                color: root.failed ? Colours.palette.m3onSurface
                    : root.draft ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                wrapMode: root.failed ? Text.Wrap : Text.NoWrap
                maximumLineCount: root.failed ? 2 : 1
                elide: Text.ElideRight
            }

            Item {
                id: activity

                visible: root.waveformActive || root.busy
                Layout.preferredWidth: root.meterWidth
                Layout.preferredHeight: 22
                readonly property int bars: 7
                property var history: Array(bars).fill(0)

                Timer {
                    running: root.presented && root.waveformActive
                    repeat: true
                    interval: root.reduceMotion ? 120 : 40
                    onRunningChanged: if (!running) activity.history = Array(activity.bars).fill(0)
                    onTriggered: activity.history = [...activity.history.slice(1), root.level]
                }

                Row {
                    anchors.centerIn: parent
                    visible: root.waveformActive
                    spacing: 2
                    height: 18

                    Repeater {
                        model: activity.bars

                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: 3 + 14 * (activity.history[index] ?? 0)
                            radius: width / 2
                            color: root.accent
                            opacity: 0.42 + 0.085 * index

                            Behavior on height {
                                enabled: !root.reduceMotion
                                NumberAnimation { duration: 92; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.presented && root.busy

                    sourceComponent: StyledProgressBar {
                        implicitWidth: root.meterWidth
                        implicitHeight: 3
                        indeterminate: !root.reduceMotion
                        value: 0.45
                        fgColour: root.accent
                        bgColour: Qt.alpha(root.accent, 0.22)
                    }
                }
            }
        }
    }
}
