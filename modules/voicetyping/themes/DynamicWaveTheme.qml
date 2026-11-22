pragma ComponentBehavior: Bound

import QtQuick
import ".."

ThemeWidget {
    id: root

    VoiceTypingWave {
        anchors.fill: parent
        phase: root.presentation.phase
        presented: root.presentation.presented
        draft: root.presentation.draft
        caption: root.presentation.caption
        level: root.presentation.level
        showWaveform: root.presentation.showWaveform
        reduceMotion: root.presentation.reduceMotion
        previewSample: root.presentation.previewSample
        animationSpeed: root.presentation.animationSpeed
    }
}
