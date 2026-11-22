pragma ComponentBehavior: Bound

import QtQuick
import ".."

ThemeWidget {
    id: root

    required property bool compact

    Loader {
        anchors.centerIn: parent
        sourceComponent: root.compact ? compactPill : classicPill
    }

    Component {
        id: classicPill
        ClassicPill {
            width: implicitWidth
            height: implicitHeight
            availableWidth: root.width - 32
            phase: root.presentation.phase
            presented: root.presentation.presented
            draft: root.presentation.draft
            caption: root.presentation.caption
            level: root.presentation.level
            showWaveform: root.presentation.showWaveform
            reduceMotion: root.presentation.reduceMotion
        }
    }

    Component {
        id: compactPill
        CompactPill {
            width: implicitWidth
            height: implicitHeight
            availableWidth: root.width - 32
            phase: root.presentation.phase
            presented: root.presentation.presented
            draft: root.presentation.draft
            caption: root.presentation.caption
            level: root.presentation.level
            showWaveform: root.presentation.showWaveform
            reduceMotion: root.presentation.reduceMotion
        }
    }
}
