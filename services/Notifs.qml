pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n.popup)
    property alias dnd: props.dnd

    property bool loaded

    // --- TTS queue state ---
    property var ttsQueue: []
    property bool ttsBusy: false

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1))
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        if (props.dnd || ShellState.anySidebarOpen())
            return false;
        if (GlobalConfig.notifs.fullscreen === "off" && hasFullscreen())
            return false;
        return true;
    }

    function enqueueTts(comp): void {
        root.ttsQueue.push(comp);
        root.processTtsQueue();
    }

    function processTtsQueue(): void {
        console.log("[Notifs] processTtsQueue: busy=", root.ttsBusy, "queueLen=", root.ttsQueue.length);
        if (root.ttsBusy || root.ttsQueue.length === 0)
            return;

        root.ttsBusy = true;
        const comp = root.ttsQueue.shift();

        // If popup shouldn't show at all (DND/fullscreen), skip TTS and finish immediately
        if (!root.shouldShowPopup()) {
            console.log("[Notifs] shouldShowPopup() false — skipping TTS");
            comp.popup = false;
            root.ttsBusy = false;
            root.processTtsQueue();
            return;
        }

        ttsTimeoutTimer.target = comp;
        ttsTimeoutTimer.restart();

        const appName = comp.appName ?? "";
        const summary = comp.summary ?? "";
        const body = comp.body ?? "";

        console.log("[Notifs] starting ttsProcess for", appName, summary, body);
        ttsProcess.pendingComp = comp;
        ttsProcess.command = ["fish", "/home/ivan/.local/bin/notify-tts.fish", appName, summary, body];
        ttsProcess.running = true;
    }

    onDndChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(qsTr("Do not disturb enabled"), qsTr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(qsTr("Do not disturb disabled"), qsTr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    image: n.image,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            console.log("[Notifs] onNotification fired:", notif.appName, notif.summary);

            // Popup starts false — TTS gating decides when (or if) it flips true
            const comp = notifComp.createObject(root, {
                popup: false,
                notification: notif
            });
            root.list = [comp, ...root.list];
            root.enqueueTts(comp);
        }
    }

    // --- TTS process handling ---
    Process {
        id: ttsProcess

        property var pendingComp: null

        stdout: SplitParser {
            onRead: function(line) {
                console.log("[ttsProcess stdout]", Date.now(), line);
                if (line.trim() !== "ready") return;
                console.log("[Notifs] READY signal received at", Date.now(), "— flipping popup true");

                const comp = ttsProcess.pendingComp;
                if (comp) {
                    comp.popup = true;
                }
                ttsTimeoutTimer.stop();
            }
        }

        stderr: SplitParser {
            onRead: function(line) {
                console.log("[ttsProcess stderr]", line);
            }
        }

        onExited: {
            console.log("[Notifs] ttsProcess onExited");
            // Always advance the queue once the process is done, whether it
            // completed cleanly, timed out, or failed — never block on TTS.
            const comp = ttsProcess.pendingComp;
            if (comp && !comp.popup) {
                // TTS never signaled ready (failure) — show notification anyway
                comp.popup = true;
            }
            ttsProcess.pendingComp = null;
            ttsTimeoutTimer.stop();
            root.ttsBusy = false;
            root.processTtsQueue();
        }
    }

    Timer {
        id: ttsTimeoutTimer

        property var target: null
        interval: 120000
        repeat: false
        onTriggered: {
            console.log("[Notifs] TIMEOUT FALLBACK fired at", Date.now(), "— ready signal never arrived in time");
            // Safety net fallback — show notification even if TTS is stuck
            if (target) {
                target.popup = true;
            }
            // The process itself is stuck (e.g. a hung ollama call) — kill it
            // so onExited fires, ttsBusy resets, and the queue doesn't
            // deadlock. Without this, only this comp's popup would show;
            // every subsequent queued notification would wait forever.
            if (ttsProcess.running) {
                ttsProcess.running = false;
            }
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            for (const notif of data) {
                const properties = Object.assign({}, notif);

                // Backwards compatibility for old notifications
                if (properties.notificationId === undefined && properties.id !== undefined)
                    properties.notificationId = properties.id;

                delete properties.id;
                root.list.push(notifComp.createObject(root, properties));
            }
            root.list.sort((a, b) => b.time - a.time);
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
