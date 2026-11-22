import QtQuick

QtObject {
    required property string themeId
    required property string name
    required property string description
    required property real width
    required property real height
    required property Component widget
    property real entranceScale: 0.94
    property Component preview: widget
    property Component settings: null
}
