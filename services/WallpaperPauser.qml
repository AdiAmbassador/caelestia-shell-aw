pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Io

import qs.services

Singleton {
    id: root

    property bool pauseOnBattery: false
    property bool paused: false
    property bool _loaded: false

    Process {
        id: loadProcess
        command: ["cat", Quickshell.env("HOME") + "/.cache/caelestia/pauseOnBattery.txt"]
        running: true
        stdout: SplitParser {
            onRead: data => { 
                root.pauseOnBattery = (data.trim() === "true"); 
                root._loaded = true; 
                root.recalculate(); 
            }
        }
        onExited: {
            if (!root._loaded) {
                root._loaded = true;
                root.recalculate();
            }
        }
    }

    Process {
        id: saveProcess
    }

    function saveSetting() {
        saveProcess.command = ["sh", "-c", "echo '" + root.pauseOnBattery + "' > ~/.cache/caelestia/pauseOnBattery.txt"];
        saveProcess.running = true;
    }

    function recalculate() {
        if (!_loaded) return;

        let newPaused = false;
        let reason = "None";
        
        // Rule #1 — Battery
        if (pauseOnBattery && UPower.onBattery) {
            newPaused = true;
            reason = "Battery";
        } else {
            const monitor = Hyprland.focusedMonitor;
            const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace : Hyprland.focusedWorkspace;
            
            if (ws) {
                // Strictly filter global toplevels to ONLY the focused workspace
                const toplevels = Hyprland.toplevels.values.filter(t => {
                    const obj = t.lastIpcObject;
                    return obj && obj.workspace && obj.workspace.id === ws.id;
                });
                
                // Rule #3 — 2+ visible windows
                if (toplevels.length >= 2) {
                    newPaused = true;
                    reason = "2+ windows (" + toplevels.length + " total)";
                } else {
                    // Rule #2 — 70% of monitor area
                    const monitor = Hyprland.focusedMonitor;
                    if (monitor) {
                        const screen = Quickshell.screens.find(s => s.name === monitor.name);
                        if (screen) {
                            const screenArea = screen.width * screen.height;
                            if (screenArea > 0) {
                                const threshold = screenArea * 0.7;
                                for (const t of toplevels) {
                                    const size = t.lastIpcObject.size;
                                    if (size && size.length >= 2 && size[0] * size[1] >= threshold) {
                                        newPaused = true;
                                        reason = "70% area rule by: " + t.lastIpcObject.title + " (" + size[0] + "x" + size[1] + ")";
                                        console.log("[DEBUG] 70% rule triggered by:", t.lastIpcObject.title, size);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        paused = newPaused;
        console.log("[DEBUG] WallpaperPauser recalculated. Final paused state:", paused, "Reason:", reason);
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.recalculate(); }
        function onFocusedMonitorChanged() { root.recalculate(); }
        function onRawEvent(event) {
            const n = event.name;
            if (n.startsWith("workspace") || n.startsWith("activewindow") || n.startsWith("createworkspace") || n.startsWith("destroyworkspace") ||
                ["fullscreen", "changefloatingmode", "minimize", "movewindow", "openwindow", "closewindow", "moveworkspace", "focusedmon"].includes(n)) {
                recalcTimer.restart();
            }
        }
    }

    Timer {
        id: recalcTimer
        interval: 16
        onTriggered: root.recalculate()
    }

    onPauseOnBatteryChanged: {
        if (_loaded) {
            saveSetting();
            recalculate();
        }
    }
}
