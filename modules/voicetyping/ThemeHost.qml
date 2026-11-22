pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property ThemePresentation presentation
    property Component source
    property ThemeWidget visual: null

    onSourceChanged: rebuild()
    Component.onCompleted: {
        ready = true;
        rebuild();
    }

    property bool ready: false

    function rebuild(): void {
        if (!ready)
            return;
        if (visual) {
            visual.visible = false;
            visual.destroy();
            visual = null;
        }
        if (source) {
            visual = source.createObject(root, {
                presentation: root.presentation,
                width: Qt.binding(() => root.width),
                height: Qt.binding(() => root.height)
            });
        }
    }
}
