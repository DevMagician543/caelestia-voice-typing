pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.modules.voicetyping
import qs.services

GridLayout {
    id: root

    required property string currentTheme
    signal selected(string themeId)

    Layout.fillWidth: true
    columns: width >= 442 ? 2 : 1
    columnSpacing: Tokens.spacing.small
    rowSpacing: Tokens.spacing.small

    Repeater {
        model: ThemeRegistry.themes

        Button {
            id: card

            required property ThemeDefinition modelData

            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            implicitHeight: 126
            hoverEnabled: true
            readonly property bool selected: modelData.themeId === root.currentTheme
            Accessible.checkable: true
            Accessible.checked: selected
            Accessible.name: modelData.name
            Accessible.description: modelData.description
            onClicked: root.selected(modelData.themeId)

            background: StyledRect {
                radius: Tokens.rounding.large
                color: card.selected ? Colours.palette.m3secondaryContainer
                    : card.hovered ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh
                border.width: card.selected || card.visualFocus ? 1 : 0
                border.color: Colours.palette.m3primary
            }

            contentItem: ColumnLayout {
                spacing: 6

                Item {
                    id: swatch

                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    Layout.minimumHeight: 61
                    clip: true

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        gradient: Gradient {
                            GradientStop { position: 0; color: Colours.palette.m3surfaceContainerLow }
                            GradientStop {
                                position: 1
                                color: Qt.tint(Colours.palette.m3surface, Qt.alpha(Colours.palette.m3tertiary, 0.08))
                            }
                        }
                    }

                    ThemePresentation {
                        id: sample

                        phase: "transcribing"
                        committedText: qsTr("Your words, as you speak")
                        level: 0.63
                        previewSample: true
                        options: VoiceTyping.themeOptionsFor(card.modelData.themeId)
                        reduceMotion: true
                        presented: false
                    }

                    ThemeHost {
                        anchors.centerIn: parent
                        width: card.modelData.width
                        height: card.modelData.height
                        scale: Math.min((swatch.width - 8) / width, (swatch.height - 3) / height)
                        source: card.modelData.preview
                        presentation: sample
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        font: Tokens.font.label.large
                        elide: Text.ElideRight
                        color: card.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    }
                    MaterialIcon {
                        visible: card.selected
                        text: "check_circle"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData.description
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                    color: card.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }

            padding: 8
        }
    }
}
