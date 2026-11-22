pragma Singleton

import QtQuick
import "themes"

QtObject {
    id: registry

    readonly property string currentDefault: "dynamic-wave"
    readonly property list<ThemeDefinition> themes: [
        ThemeDefinition {
            themeId: "classic"
            name: qsTr("Default · Classic")
            description: qsTr("Two-line recording pill")
            width: 434
            height: 110
            widget: LegacyTheme { compact: false }
        },
        ThemeDefinition {
            themeId: "compact"
            name: qsTr("Compact")
            description: qsTr("Single-row recording pill")
            width: 406
            entranceScale: 0.97
            height: 84
            widget: LegacyTheme { compact: true }
        },
        ThemeDefinition {
            themeId: "dynamic-wave"
            name: qsTr("Dynamic Wave")
            description: qsTr("Floating audio ribbons")
            width: 470
            entranceScale: 0.86
            height: 140
            widget: DynamicWaveTheme {}
        }
    ]

    function resolve(id: string): ThemeDefinition {
        return themes.find(theme => theme.themeId === id)
            ?? themes.find(theme => theme.themeId === registry.currentDefault);
    }
}
