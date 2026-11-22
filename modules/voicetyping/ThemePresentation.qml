import QtQuick

QtObject {
    property string phase: "listening"
    property string draftText: ""
    property string committedText: ""
    property string message: ""
    property real level: 0
    property bool presented: false
    property bool previewSample: false
    property bool showPreview: true
    property bool showWaveform: true
    property bool reduceMotion: false
    property real animationSpeed: 1
    property var options: ({})

    readonly property bool live: phase === "listening" || phase === "transcribing"
    readonly property bool draft: live && showPreview && draftText.length > 0
    readonly property string caption: phase === "error" ? message
        : live && showPreview ? draftText || committedText : ""
}
