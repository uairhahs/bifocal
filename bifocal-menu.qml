// bifocal-menu.qml: the picker window, run by bifocal-menu with Qt's qml tool.
//
// The shape is bifocal's own; the colours, font and icons come from the
// current colour scheme, system font and icon theme.
//
// The last command-line argument is a directory: every file that appears in it
// is one more press of the shortcut and moves the highlight down a row, so
// repeated presses step through the layouts without reopening the window.
// Once the shortcut has moved the highlight, the highlighted layout is applied
// when Meta is released, or a moment after the last press if that release is
// never seen. Moving with the arrow keys (or Tab, j, k) cancels that, so the
// highlight can be moved freely and confirmed with Enter.
//
// Exits with 10 + the chosen row (10 laptop, 11 external, 12 extended), or 0
// when closed without a choice. Codes below 10 are left for qml's own errors.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell

Window {
    id: root

    // The same icons as KDE's own display switcher; bifocal's notifications
    // use them too
    readonly property var layouts: [
        { icon: "osd-shutd-screen", label: "Laptop Only" },
        { icon: "osd-shutd-laptop", label: "External Only" },
        { icon: "osd-sbs-left", label: "Extend Both" }
    ]

    // Palette, from the colour scheme
    readonly property color bg: Kirigami.Theme.backgroundColor
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color accentText: Kirigami.Theme.highlightedTextColor
    readonly property color surface: buttonColors.Kirigami.Theme.backgroundColor
    readonly property color surfaceHover: Kirigami.ColorUtils.tintWithAlpha(surface, Kirigami.Theme.hoverColor, 0.25)

    property int current: 0
    property int presses: 0
    property bool wasActive: false
    // Set when the shortcut moves the highlight: stopping applies the layout
    property bool cycling: false

    function choose(row) {
        Qt.exit(10 + row);
    }

    function step(delta) {
        current = (current + delta + layouts.length) % layouts.length;
    }

    // Free movement with the keyboard: no longer apply on stopping
    function move(delta) {
        cycling = false;
        settle.stop();
        step(delta);
    }

    function pressed(count) {
        cycling = true;
        settle.restart();
        step(count);
    }

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    width: 432
    height: box.implicitHeight
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: true

    LayerShell.Window.scope: "bifocal"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorNone
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand

    // Clicking elsewhere closes the menu
    onActiveChanged: {
        if (active)
            wasActive = true;
        else if (wasActive)
            Qt.exit(0);
    }

    // Only here to read the colour scheme's button colours
    Item {
        id: buttonColors

        Kirigami.Theme.colorSet: Kirigami.Theme.Button
        Kirigami.Theme.inherit: false
    }

    // Repeated presses of the shortcut: one row down per new press file
    FolderListModel {
        folder: "file://" + Qt.application.arguments[Qt.application.arguments.length - 1]
        showDirs: false
        showHidden: true
        onCountChanged: {
            if (count > root.presses)
                root.pressed(count - root.presses);
            root.presses = count;
        }
    }

    // Fallback for when the release of Meta never reaches the window
    Timer {
        id: settle

        interval: 1000
        onTriggered: {
            if (root.cycling)
                root.choose(root.current);
        }
    }

    Rectangle {
        id: box

        anchors.fill: parent
        implicitHeight: column.implicitHeight + 2 * 15
        radius: 28
        color: root.bg
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.35)

        focus: true
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Down:
            case Qt.Key_Tab:
            case Qt.Key_J:
                root.move(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_Backtab:
            case Qt.Key_K:
                root.move(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.choose(root.current);
                break;
            case Qt.Key_Escape:
                Qt.exit(0);
                break;
            default:
                return;
            }
            event.accepted = true;
        }
        Keys.onReleased: event => {
            switch (event.key) {
            case Qt.Key_Meta:
            case Qt.Key_Super_L:
            case Qt.Key_Super_R:
                if (root.cycling)
                    root.choose(root.current);
                event.accepted = true;
                break;
            }
        }

        Column {
            id: column

            anchors.fill: parent
            anchors.margins: 15
            spacing: 8

            Repeater {
                model: root.layouts

                Rectangle {
                    id: entry

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current

                    width: column.width
                    height: Math.max(label.implicitHeight, icon.height) + 2 * 16
                    radius: 18
                    color: selected ? root.accent : hover.hovered ? root.surfaceHover : root.surface

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Kirigami.Icon {
                        id: icon

                        anchors.verticalCenter: parent.verticalCenter
                        x: 22
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: entry.modelData.icon
                    }

                    Text {
                        id: label

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: icon.right
                        anchors.leftMargin: 22
                        text: entry.modelData.label
                        font.family: Kirigami.Theme.defaultFont.family
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        font.weight: Font.DemiBold
                        color: entry.selected ? root.accentText : root.fg
                    }

                    HoverHandler { id: hover }
                    TapHandler { onTapped: root.choose(entry.index) }
                }
            }
        }
    }
}
