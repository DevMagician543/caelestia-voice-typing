pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
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
    property bool previewSample: false
    property real animationSpeed: 1

    readonly property bool listening: phase === "listening" || phase === "transcribing"
    readonly property bool finishing: phase === "finishing"
    readonly property bool finished: phase === "success"
    readonly property bool failed: phase === "error"
    readonly property color accent: failed ? Colours.palette.m3error
        : finished ? Colours.palette.m3success : Colours.palette.m3primary
    readonly property string subtitle: caption || (failed ? qsTr("Voice Typing")
        : finishing ? qsTr("Finishing dictation") : phase === "empty" ? qsTr("No speech detected") : "")
    readonly property real targetEnergy: presented && listening && showWaveform && !reduceMotion
        ? Math.max(0, Math.min(1, (level - 0.06) / 0.94)) : 0
    property vector4d audioTrail: Qt.vector4d(0, 0, 0, 0)
    readonly property real envelope: audioTrail.x
    readonly property bool settling: Math.max(Math.abs(targetEnergy - audioTrail.x),
        Math.abs(targetEnergy - audioTrail.y), Math.abs(targetEnergy - audioTrail.z),
        Math.abs(targetEnergy - audioTrail.w)) > 0.002
    property real successProgress: 1

    onPresentedChanged: if (presented) audioTrail = Qt.vector4d(0, 0, 0, 0)
    onReduceMotionChanged: if (reduceMotion) audioTrail = Qt.vector4d(0, 0, 0, 0)

    onPhaseChanged: {
        if (finished && presented && !reduceMotion)
            finishPulse.restart();
    }

    function approach(current: real, target: real, dt: real, tau: real): real {
        return current + (target - current) * (1 - Math.exp(-dt / tau));
    }

    FrameAnimation {
        running: root.presented && !root.reduceMotion && root.settling
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            const old = root.audioTrail;
            const attack = root.targetEnergy > old.x ? 0.039 : 0.205;
            const near = root.approach(old.x, root.targetEnergy, dt, attack);
            const middle = root.approach(old.y, near, dt, 0.061);
            const outer = root.approach(old.z, middle, dt, 0.073);
            const end = root.approach(old.w, outer, dt, 0.091);
            root.audioTrail = Qt.vector4d(near, middle, outer, end);
        }
    }

    NumberAnimation {
        id: finishPulse

        target: root
        property: "successProgress"
        from: 0
        to: 1
        duration: Math.round(680 / root.animationSpeed)
        easing.type: Easing.OutCubic
    }

    Item {
        id: signalField

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 92

        ShaderEffect {
            id: wave

            anchors.fill: parent
            visible: waveVisibility > 0.002 || processing > 0.002 || successVisibility > 0
            property color primaryColour: Colours.palette.m3primary
            property color secondaryColour: Colours.palette.m3secondary
            property color tertiaryColour: Colours.palette.m3tertiary
            property color successColour: Colours.palette.m3success
            property vector2d resolution: Qt.vector2d(width, height)
            property real phase: 0
            property real ringPhase: 0
            property vector4d energyTrail: root.previewSample ? Qt.vector4d(root.level, root.level, root.level * 0.88, root.level * 0.66)
                : root.audioTrail
            property real spread: (!root.presented && !root.previewSample) || root.finished || root.failed || root.phase === "empty" ? 0.1
                : root.finishing ? 0.23 : root.phase === "starting" ? 0.70 : 1
            property real waveVisibility: root.showWaveform && (root.listening || root.finishing || root.phase === "starting") ? 1 : 0
            property real processing: root.finishing ? 1 : 0
            property real successPulse: root.successProgress
            property real successVisibility: root.finished ? 1 : 0

            fragmentShader: Qt.resolvedUrl("dynamic-wave-ribbons.frag.qsb")

            UniformAnimator {
                target: wave
                uniform: "phase"
                from: 0
                to: 1
                duration: Math.round(4200 / root.animationSpeed)
                loops: Animation.Infinite
                running: root.presented && !root.reduceMotion && wave.visible === true
                    && (root.listening || wave.waveVisibility > 0.01)
            }

            UniformAnimator {
                target: wave
                uniform: "ringPhase"
                from: 0
                to: 1
                duration: Math.round(1750 / root.animationSpeed)
                loops: Animation.Infinite
                running: root.presented && !root.reduceMotion && wave.processing > 0.01
            }

            Behavior on spread {
                enabled: !root.reduceMotion
                Anim { type: Anim.DefaultSpatial }
            }
            Behavior on waveVisibility {
                enabled: !root.reduceMotion
                Anim { type: Anim.FastEffects }
            }
            Behavior on processing {
                enabled: !root.reduceMotion
                Anim { type: Anim.DefaultEffects }
            }
        }

        Item {
            id: microphone

            anchors.centerIn: parent
            width: 40
            height: width
            scale: root.reduceMotion ? 1 : 1 + root.envelope * 0.10

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                border.width: 1
                border.color: Qt.alpha(root.accent, root.listening ? 0.35 + root.envelope * 0.20 : 0.28)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.tint(Colours.palette.m3surfaceContainerHigh, Qt.alpha(root.accent, 0.13))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colours.palette.m3surface, 0.97)
                    }
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                fontStyle: Tokens.font.icon.large
                color: root.accent
                fill: 1
                animate: root.presented && !root.reduceMotion
                text: root.failed ? "error" : root.finished ? "check"
                    : root.phase === "empty" ? "mic_off" : "mic"
            }
        }
    }

    StyledText {
        id: captionText

        property real rise: 0

        anchors.top: signalField.bottom
        anchors.topMargin: -5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        horizontalAlignment: Text.AlignHCenter
        opacity: root.subtitle ? 1 : 0
        text: root.subtitle
        onTextChanged: if (root.presented && !root.reduceMotion && root.subtitle) captionRise.restart()
        transform: Translate { y: captionText.rise }
        NumberAnimation {
            id: captionRise

            target: captionText
            property: "rise"
            from: 2
            to: 0
            duration: Math.round(170 / root.animationSpeed)
            easing.type: Easing.OutCubic
        }
        textFormat: Text.PlainText
        font: root.caption ? Tokens.font.body.small : Tokens.font.label.medium
        color: root.failed ? root.accent : root.draft ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
        style: Text.Outline
        styleColor: Qt.alpha(Colours.palette.m3surface, 0.92)
        wrapMode: root.failed ? Text.Wrap : Text.NoWrap
        maximumLineCount: root.failed ? 2 : 1
        elide: root.failed ? Text.ElideRight : Text.ElideLeft

        Behavior on opacity {
            enabled: !root.reduceMotion
            Anim { type: Anim.FastEffects }
        }
    }
}
