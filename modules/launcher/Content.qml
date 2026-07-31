pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onTextChanged: {
            if (text === `${GlobalConfig.launcher.actionPrefix}wallpaper `) {
                Wallpapers.updateWallpapers();
            }
        }

        onAccepted: {
            const currentItem = list.currentList?.currentItem;
            if (!currentItem)
                return;

            if (list.showWallpapers) {
                const path = currentItem.modelData.path;
                if (Colours.scheme === "dynamic" && path !== Wallpapers.actualCurrent)
                    Wallpapers.previewColourLock = true;
                Wallpapers.setWallpaper(path);
                root.screenState.launcher = false;
                return;
            }

            if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `)) {
                currentItem.onClicked();
            } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                currentItem.modelData.onClicked(list.currentList);
            } else {
                Apps.launch(currentItem.modelData);
                root.screenState.launcher = false;
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            // Ctrl + Tab now switches between static and animated tabs.
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Tab) {
                if (Wallpapers.wallpaperMode === "static") {
                    Wallpapers.setWallpaperMode("animated");
                } else {
                    Wallpapers.setWallpaperMode("static");
                }
                event.accepted = true;
                return;
            }

            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: {
            forceActiveFocus();
            if (Wallpapers.restoreWallpaperMode) {
                const target = `${GlobalConfig.launcher.actionPrefix}wallpaper `;
                if (text !== target)
                    text = target;
                Wallpapers.restoreWallpaperMode = false;
            }
        }

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
