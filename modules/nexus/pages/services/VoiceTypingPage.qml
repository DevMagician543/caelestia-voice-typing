pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus.common
import qs.modules.voicetyping
import qs.services

PageBase {
    id: root

    title: qsTr("Voice Typing")
    readonly property ThemeDefinition theme: ThemeRegistry.resolve(VoiceTyping.prefs.theme)
    readonly property var themeOptions: VoiceTyping.themeOptionsFor(theme.themeId)

    ColumnLayout {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: qsTr("Dictation") }

        PreferenceToggle {
            first: true
            setting: "enabled"
            text: qsTr("Voice Typing")
            subtext: qsTr("Dictate into the focused application")
        }

        TextFieldRow {
            label: qsTr("Start / stop shortcut")
            subtext: VoiceTyping.bindingError || (VoiceTyping.installedShortcut
                ? qsTr("Active shortcut  %1 · Esc finishes").arg(VoiceTyping.installedShortcut)
                : qsTr("Use a modifier and a letter, digit or function key"))
            value: VoiceTyping.prefs.shortcut
            maximumLength: 55
            onEditingFinished: value => VoiceTyping.setPref("shortcut", value.trim())
        }

        ChoiceRow {
            last: true
            setting: "microphone"
            label: qsTr("Microphone")
            subtext: qsTr("PipeWire capture source")
            choices: [["", qsTr("System default")]].concat(
                Audio.sources.filter(node => node.name && (node.properties?.["media.class"] ?? "").startsWith("Audio/Source"))
                    .map(node => [node.name, node.description || node.name]))
            missingText: qsTr("Selected microphone unavailable")
        }

        SectionHeader { text: qsTr("Appearance / Theme") }

        VoiceTypingThemePicker {
            currentTheme: root.theme.themeId
            onSelected: themeId => VoiceTyping.setPref("theme", themeId)
        }

        ChoiceRow {
            first: true
            setting: "position"
            label: qsTr("Position on active monitor")
            choices: [["bottom", qsTr("Bottom center")], ["top", qsTr("Top center")]]
        }

        StepperRow {
            label: qsTr("Widget scale (%)")
            from: 75
            to: 135
            stepSize: 5
            value: VoiceTyping.prefs.widgetScale
            onMoved: value => VoiceTyping.setPref("widgetScale", value)
        }

        StepperRow {
            label: qsTr("Animation speed (%)")
            from: 50
            to: 150
            stepSize: 10
            value: VoiceTyping.prefs.animationSpeed
            onMoved: value => VoiceTyping.setPref("animationSpeed", value)
        }

        ToggleRow {
            text: qsTr("Enable animations")
            checked: !VoiceTyping.prefs.reduceMotion
            onToggled: VoiceTyping.setPref("reduceMotion", !checked)
        }

        ToggleRow {
            text: qsTr("Transcription preview")
            subtext: qsTr("Applies to the selected theme")
            checked: root.themeOptions.preview ?? VoiceTyping.prefs.preview
            onToggled: VoiceTyping.setThemeOption(root.theme.themeId, "preview", checked)
        }

        ToggleRow {
            text: qsTr("Live waveform")
            subtext: qsTr("Applies to the selected theme")
            checked: root.themeOptions.waveform ?? VoiceTyping.prefs.waveform
            onToggled: VoiceTyping.setThemeOption(root.theme.themeId, "waveform", checked)
        }
        PreferenceToggle {
            last: true
            setting: "sounds"
            text: qsTr("Confirmation sound")
        }

        Loader {
            Layout.fillWidth: true
            active: root.theme.settings !== null
            sourceComponent: root.theme.settings
        }

        SectionHeader { text: qsTr("Speech recognition") }

        ChoiceRow {
            first: true
            setting: "language"
            label: qsTr("Language")
            choices: [["", qsTr("Automatic")], ["ru", "Русский"], ["en", "English"],
                      ["es", "Español"], ["ca", "Català / Valencià"]]
        }

        ChoiceRow {
            setting: "model"
            label: qsTr("Model")
            choices: [["tiny", qsTr("Tiny · lowest resource use")], ["base", qsTr("Base · fast")],
                      ["small", qsTr("Small · more accurate")], ["medium", qsTr("Medium")],
                      ["large-v3-turbo", qsTr("Large v3 Turbo · recommended")]]
        }

        NavRow {
            icon: "download"
            text: VoiceTyping.installing ? qsTr("Installing speech model…") : qsTr("Install selected model")
            subtext: VoiceTyping.setupStatus || qsTr("One-time download for local recognition")
            onClicked: VoiceTyping.setup()
        }

        ChoiceRow {
            setting: "device"
            label: qsTr("Processing")
            choices: [["auto", qsTr("Automatic")], ["cpu", "CPU"], ["gpu", qsTr("Prefer NVIDIA GPU")]]
        }

        ChoiceRow {
            setting: "behavior"
            label: qsTr("Transcription behavior")
            subtext: qsTr("Set how often stable words can appear as you speak")
            choices: [["responsive", qsTr("Responsive")], ["balanced", qsTr("Balanced")],
                      ["context", qsTr("More context")]]
        }

        TextFieldRow {
            last: true
            label: qsTr("Vocabulary hints")
            placeholderText: qsTr("Project names, abbreviations, technical terms")
            value: VoiceTyping.prefs.vocabulary
            maximumLength: 300
            onEditingFinished: value => VoiceTyping.setPref("vocabulary", value.trim())
        }
    }

    component PreferenceToggle: ToggleRow {
        required property string setting
        checked: VoiceTyping.prefs[setting]
        onToggled: VoiceTyping.setPref(setting, checked)
    }

    component ChoiceRow: SelectRow {
        id: choice
        required property string setting
        required property var choices
        property string missingText: ""
        readonly property string selectedValue: VoiceTyping.prefs[setting]

        menuItems: items.instances
        active: menuItems.find(item => item.choiceValue === selectedValue) ?? null
        fallbackText: missingText || selectedValue
        onSelected: item => VoiceTyping.setPref(setting, item["choiceValue"])

        Variants {
            id: items
            model: choice.choices
            MenuItem {
                required property var modelData
                readonly property string choiceValue: modelData[0]
                text: modelData[1]
            }
        }
    }
}
