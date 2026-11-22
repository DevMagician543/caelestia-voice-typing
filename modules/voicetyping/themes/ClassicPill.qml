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
    readonly property bool completed: phase === "success"
    readonly property bool failed: phase === "error"
    readonly property bool showActivity: busy || (showWaveform && listening)
    readonly property color accent: failed ? Colours.palette.m3error
        : completed ? Colours.palette.m3success : Colours.palette.m3primary
    readonly property color badgeColour: failed ? Colours.palette.m3errorContainer
        : completed ? Colours.palette.m3successContainer : Colours.palette.m3primaryContainer
    readonly property color badgeInk: failed ? Colours.palette.m3onErrorContainer
        : completed ? Colours.palette.m3onSuccessContainer : Colours.palette.m3onPrimaryContainer

    readonly property real titleWidth: titleLabel.implicitWidth
        + (listening ? 6 + Tokens.spacing.small : 0)
    readonly property real controlsWidth: 44 + Tokens.padding.small + 2
        + (showActivity ? 68 + Tokens.spacing.medium + Tokens.padding.small + 2 : Tokens.padding.large)
        + Tokens.spacing.medium

    implicitWidth: Math.min(availableWidth, Math.max(caption ? 394 : 0, titleWidth + controlsWidth + 9))
    implicitHeight: 64

    Elevation {
        anchors.fill: surface
        radius: surface.radius
        level: 3
        z: -1
    }

    StyledRect {
        id: surface

        anchors.fill: parent
        radius: Tokens.rounding.full
        readonly property color baseColour: Qt.alpha(Colours.palette.m3surfaceContainer, 0.97)
        color: Colours.surface?.(baseColour) ?? baseColour
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3outline, 0.23)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small + 2
            anchors.rightMargin: root.showActivity ? Tokens.padding.small + 2 : Tokens.padding.large
            spacing: Tokens.spacing.medium

            Item {
                id: badge
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44

                Rectangle {
                    anchors.centerIn: parent
                    width: 49
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.accent
                    opacity: root.listening && !root.reduceMotion ? root.level * 0.62 : 0
                    scale: 0.91 + opacity * 0.18

                    Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                }

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: root.badgeColour

                    MaterialIcon {
                        anchors.centerIn: parent
                        fontStyle: Tokens.font.icon.large
                        fill: 1
                        color: root.badgeInk
                        animate: root.presented && !root.reduceMotion
                        text: root.failed ? "error" : root.completed ? "check"
                            : root.phase === "empty" ? "mic_off"
                            : root.phase === "finishing" ? "graphic_eq" : "mic"
                        scale: root.listening && !root.reduceMotion ? 1 + 0.09 * root.level : 1

                        Behavior on scale { NumberAnimation { duration: 115; easing.type: Easing.OutCubic } }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Rectangle {
                        visible: root.listening
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: root.accent
                    }

                    StyledText {
                        id: titleLabel

                        Layout.fillWidth: true
                        font: Tokens.font.label.large
                        elide: Text.ElideRight
                        text: {
                            switch (root.phase) {
                            case "starting": return qsTr("Starting microphone")
                            case "finishing": return qsTr("Finishing dictation")
                            case "success": return qsTr("Dictation inserted")
                            case "empty": return qsTr("No speech detected")
                            case "error": return qsTr("Voice Typing")
                            default: return qsTr("Listening")
                            }
                        }
                    }
                }

                StyledText {
                    property real captionHeight: root.caption ? implicitHeight : 0

                    Layout.fillWidth: true
                    Layout.preferredHeight: captionHeight
                    opacity: root.caption ? 1 : 0
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                    color: root.failed ? Colours.palette.m3error
                        : root.draft ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                    text: root.caption

                    Behavior on captionHeight {
                        enabled: !root.reduceMotion
                        Anim { type: Anim.FastSpatial }
                    }
                    Behavior on opacity {
                        enabled: !root.reduceMotion
                        Anim { type: Anim.FastEffects }
                    }
                }
            }

            StyledRect {
                id: activity
                visible: root.showActivity
                Layout.preferredWidth: 68
                Layout.preferredHeight: 40
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3secondaryContainer, 0.78)

                readonly property int bars: 9
                property var history: Array(bars).fill(0)

                Timer {
                    running: root.presented && root.listening && root.showWaveform
                    repeat: true
                    interval: root.reduceMotion ? 140 : 40
                    onRunningChanged: if (!running) activity.history = Array(activity.bars).fill(0)
                    onTriggered: activity.history = [...activity.history.slice(1), root.level]
                }

                Row {
                    anchors.centerIn: parent
                    opacity: root.listening ? 1 : 0
                    spacing: 3
                    height: 25

                    Behavior on opacity {
                        enabled: !root.reduceMotion
                        Anim { type: Anim.FastEffects }
                    }

                    Repeater {
                        model: activity.bars

                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 3 + 21 * (activity.history[index] ?? 0) * (0.55 + 0.1 * Math.min(index, 8 - index))
                            radius: width / 2
                            color: Colours.palette.m3onSecondaryContainer
                            opacity: 0.45 + index * 0.0625

                            Behavior on height {
                                enabled: !root.reduceMotion
                                NumberAnimation { duration: 95; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.busy && root.presented
                    sourceComponent: StyledProgressBar {
                        implicitWidth: 43
                        implicitHeight: 4
                        indeterminate: !root.reduceMotion
                        value: 0.42
                        fgColour: root.accent
                        bgColour: Qt.alpha(Colours.palette.m3onSecondaryContainer, 0.16)
                    }
                }
            }
        }
    }
}
