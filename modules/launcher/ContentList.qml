pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    readonly property var currentList: showWallpapers ? (wallpaperList.item ? wallpaperList.item.realList : null) : appList.item
    property string animState: showWallpapers ? "wallpapers" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight + 56
                wallpaperList.active: root.screenState.launcher
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: ColumnLayout {
            readonly property var realList: listComp
            readonly property int count: listComp.count
            spacing: root.Tokens.spacing.normal
            implicitWidth: listComp.implicitWidth

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: root.Tokens.spacing.normal * 1.06

                IconTextButton {
                    icon: "image"
                    text: qsTr("Static")
                    font.pointSize: root.Tokens.font.size.small
                    isRound: true
                    horizontalPadding: root.Tokens.padding.medium
                    verticalPadding: root.Tokens.padding.extraSmall
                    type: Wallpapers.wallpaperMode === "static" ? IconTextButton.Filled : IconTextButton.Tonal
                    onClicked: Wallpapers.setWallpaperMode("static")
                }

                IconTextButton {
                    icon: "movie"
                    text: qsTr("Animated")
                    font.pointSize: root.Tokens.font.size.small
                    isRound: true
                    horizontalPadding: root.Tokens.padding.medium
                    verticalPadding: root.Tokens.padding.extraSmall
                    type: Wallpapers.wallpaperMode === "animated" ? IconTextButton.Filled : IconTextButton.Tonal
                    onClicked: Wallpapers.setWallpaperMode("animated")
                }

                IconTextButton {
                    icon: "refresh"
                    text: qsTr("Refresh")
                    font.pointSize: root.Tokens.font.size.small
                    isRound: true
                    horizontalPadding: root.Tokens.padding.medium
                    verticalPadding: root.Tokens.padding.extraSmall
                    visible: Wallpapers.wallpaperMode === "animated"
                    type: IconTextButton.Tonal
                    onClicked: {
                        Wallpapers.refreshAnimatedThumbs();
                    }
                }

                Timer {
                    id: processingDotsTimer
                    running: Wallpapers._refreshing && Wallpapers.wallpaperMode === "animated"
                    repeat: true
                    interval: 400
                    onTriggered: processingText.dotCount = (processingText.dotCount % 3) + 1
                }

                Text {
                    id: processingText
                    font.pointSize: root.Tokens.font.size.small
                    color: Colours.palette.m3secondary
                    visible: processingDotsTimer.running
                    Layout.alignment: Qt.AlignVCenter

                    property int dotCount: 1
                    text: "Processing" + ".".repeat(dotCount)
                }
            }

            WallpaperList {
                id: listComp
                objectName: "launcherWallpaperList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                search: root.search
                screenState: root.screenState
                panels: root.panels
                content: root.content
            }
        }
    }

    Row {
        id: empty

        readonly property int count: root.currentList?.count ?? 0
        opacity: count === 0 ? 1 : 0
        scale: count === 0 ? 1 : 0.5

        spacing: root.Tokens.spacing.medium
        padding: root.Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: root.Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results")
                color: Colours.palette.m3onSurfaceVariant
                font: root.Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: root.state === "wallpapers" && Wallpapers.list.length === 0 ? qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir)) : qsTr("Try searching for something else")
                color: Colours.palette.m3onSurfaceVariant
                font: root.Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher
        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher
        Anim {}
    }
}
