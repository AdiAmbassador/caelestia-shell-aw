pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    property bool enableAnimation: true
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv"]
    property string wallpaperMode: "static"
    property string cacheBuster: ""
    property string rollbackPath: ""
    property string rollbackMode: ""
    property bool isTrackingRollback: false
    
    // Track and restore the last used wallpaper per mode using low-overhead execution
    property string lastStatic: ""
    property string lastAnimated: ""

    property var _hashCache: ({})

    Timer {
        id: colorReleaseTimer
        interval: 180 
        repeat: false
        onTriggered: {
            // Safety check: only clear the preview if no new lock has been engaged
            if (!previewColourLock && pendingPreviewClear) {
                Colours.showPreview = false;
                pendingPreviewClear = false;
            }
        }
    }

    function djb2_hash(s) {
        if (!s) return "0";
        if (_hashCache[s] !== undefined) return _hashCache[s];

        let h = 5381;
        for (let i = 0; i < s.length; i++) {
            h = ((h << 5) + h) + s.charCodeAt(i);
            h |= 0;
        }
        const res = (h >>> 0).toString(10);
        _hashCache[s] = res;
        return res;
    }

    function getWallpaperThumb(path, buster) {
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        let b = buster !== undefined ? buster : cacheBuster;
        return "file://" + Paths.cache + "/videothumbs/" + djb2_hash(clean) + ".jpg" + (b ? "?v=" + b : "");
    }

    function isVideo(path: string): bool {
        if (!path) return false;
        const clean = String(path).split(/[?#]/)[0].toLowerCase();
        const index = clean.lastIndexOf(".");
        const ext = index >= 0 ? clean.slice(index + 1) : "";
        return validVideoExtensions.includes(ext);
    }

    function indexOf(path: string): int {
        if (!path) return -1;
        let clean = String(path).split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);

        for (let i = 0; i < list.length; i++) {
            let p = String(list[i].path || "").split(/[?#]/)[0];
            if (p.indexOf("file://") === 0) p = p.substring(7);
            if (p === clean) return i;
        }
        return -1;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setWallpaperMode(mode) {
        wallpaperMode = mode;
    }

    function captureRollbackState() {
        if (!isTrackingRollback) {
            rollbackPath = actualCurrent;
            rollbackMode = wallpaperMode;
            isTrackingRollback = true;
        }
    }

    onWallpaperModeChanged: {
        captureRollbackState();
        
        const target = wallpaperMode === "animated" ? lastAnimated : lastStatic;

        if (target !== "") {
            actualCurrent = target;
            if (showPreview) {
                previewPath = target;
                if (String(Colours.scheme).startsWith("dynamic")) {
                    if (!getPreviewColoursProc.running) {
                        getPreviewColoursProc.startFor(target);
                    }
                }
            } else {
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", target, ...smartArg]);
            }
        }
    }

    onEnableAnimationChanged: {
        Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + (enableAnimation ? "1" : "0") + "' > '" + Paths.state + "/wallpaper/enable_animation.txt'"]);
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        if (!clean) return;

        actualCurrent = clean;
        isTrackingRollback = false;

        // Hold the preview palette locked while the backend executes
        previewColourLock = true;
        pendingPreviewClear = false;
        
        if (isVideo(clean)) {
            lastAnimated = clean;
            wallpaperMode = "animated";
            // Save animated path to disk
            Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + clean + "' > '" + Paths.state + "/wallpaper/last_animated.txt'"]);
        } else {
            lastStatic = clean;
            wallpaperMode = "static";
            // Save static path to disk
            Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + clean + "' > '" + Paths.state + "/wallpaper/last_static.txt'"]);
        }

        stopPreview();
        
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", clean, ...smartArg]);
    }

    function preview(path: string): void {
        captureRollbackState();
        
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        if (!clean) return;

        if (previewPath === clean && showPreview) return;

        previewPath = clean;
        showPreview = true;

        if (String(Colours.scheme).startsWith("dynamic")) {
            if (!getPreviewColoursProc.running) {
                getPreviewColoursProc.startFor(clean);
            }
        }
    }

    function stopPreview(): void {
        showPreview = false;
        
        if (getPreviewColoursProc.running) {
            getPreviewColoursProc.running = false;
        }

        if (isTrackingRollback) {
            wallpaperMode = rollbackMode;
            actualCurrent = rollbackPath;
            isTrackingRollback = false;
            
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", rollbackPath, ...smartArg]);
        }

        if (previewColourLock) {
            pendingPreviewClear = true;
        } else {
            Colours.showPreview = false;
            pendingPreviewClear = false;
        }
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear) {
            colorReleaseTimer.restart();
        }
    }

    list: wallpaperMode === "animated" ? animatedWallpapers.entries : staticWallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({ forward: false })

    IpcHandler {
        function get(): string { return root.actualCurrent; }
        function set(path: string): void { root.setWallpaper(path); }
        function list(): string { return root.list.map(w => w.path).join("\n"); }
        target: "wallpaper"
    }

    FileView {
        path: `${Paths.state}/wallpaper/enable_animation.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val === "0") root.enableAnimation = false;
            else if (val === "1") root.enableAnimation = true;
        }
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;

            // Set initial wallpaper mode based on current file type on boot
            if (root.isVideo(root.actualCurrent)) {
                wallpaperMode = "animated";
                if (!root.lastAnimated) root.lastAnimated = wall;
            } else {
                wallpaperMode = "static";
                if (!root.lastStatic) root.lastStatic = wall;
            }
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    // Read persisted static wallpaper state on startup
    FileView {
        path: `${Paths.state}/wallpaper/last_static.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val) root.lastStatic = val;
        }
    }
    
    // Read persisted animated wallpaper state on startup
    FileView {
        path: `${Paths.state}/wallpaper/last_animated.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val) root.lastAnimated = val;
        }
    }

    FileSystemModel {
        id: staticWallpapers
        watchChanges: true
        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.tif", "*.tiff", "*.svg", "*.gif"]
    }

    FileSystemModel {
        id: animatedWallpapers
        watchChanges: true
        recursive: true
        path: Paths.wallsdir + "/Animated"
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4", "*.webm", "*.mkv"]
    }

    Process {
        id: getPreviewColoursProc

        property string currentProcessingPath: ""

        command: ["caelestia", "wallpaper", "-p", currentProcessingPath, ...root.smartArg]

        function startFor(path) {
            if (!path) return;
            currentProcessingPath = path;
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.showPreview) return;

                const raw = text ? text.trim() : "";
                if (raw) {
                    try {
                        JSON.parse(raw);
                        Colours.load(raw, true);
                        Colours.showPreview = true;
                    } catch (e) {
                        // Ignore incomplete or invalid output during cancellation
                    }
                }

                if (root.showPreview && root.previewPath !== "" && root.previewPath !== getPreviewColoursProc.currentProcessingPath) {
                    getPreviewColoursProc.startFor(root.previewPath);
                }
            }
        }
    }

    property bool _refreshing: false
    property bool restoreWallpaperMode: false
    property var itemBusters: ({})

    FileView {
        path: "/tmp/caelestia_thumb_ready.txt"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const raw = text().trim();
            if (!raw) return;
            
            const lines = raw.split("\n");
            let busters = Object.assign({}, root.itemBusters);
            let changed = false;
            const now = Date.now().toString();

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("file://") === 0) line = line.substring(7);
                if (line && !busters[line]) {
                    busters[line] = now;
                    busters["file://" + line] = now;
                    changed = true;
                }
            }
            if (changed) {
                root.itemBusters = busters;
            }
        }
    }

    function refreshAnimatedThumbs() {
        if (_refreshing) return;
        itemBusters = {};
        _refreshing = true;
        _extractThumbsProc.running = true;
    }

    Process {
        id: _extractThumbsProc

        command: ["caelestia", "wallpaper", "--extract-thumbs"]
        onExited: (exitCode, exitStatus) => {
            root._refreshing = false;
            root.cacheBuster = Date.now().toString();
            root.restoreWallpaperMode = true;
        }
    }
}
