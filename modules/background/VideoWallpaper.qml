import QtQuick
import QtMultimedia

Item {
    id: root

    property url videoSource
    property bool autoStart: true
    readonly property var validVideoExtensions: ["mp4", "webm", "mkv"]

    // Expose active player state
    property alias playbackState: root._activePlaybackState
    property alias mediaStatus: root._activeMediaStatus
    property alias error: root._activeError
    property alias errorString: root._activeErrorString

    // Internal: track which player is active (true = A, false = B)
    property bool _usePlayerA: true
    property int _activePlaybackState: _usePlayerA ? playerA.playbackState : playerB.playbackState
    property int _activeMediaStatus: _usePlayerA ? playerA.mediaStatus : playerB.mediaStatus
    property int _activeError: _usePlayerA ? playerA.error : playerB.error
    property string _activeErrorString: _usePlayerA ? playerA.errorString : playerB.errorString

    // Prevent re-entrant swaps during load
    property bool _swapping: false
    property bool forceFrameRenderA: false
    property bool forceFrameRenderB: false

    function play() {
        const active = _swapping ? (_pendingSwapToA ? playerA : playerB) : (_usePlayerA ? playerA : playerB);
        if (videoSource != "" && videoSource.toString() !== "")
            active.play();
    }

    function pause() {
        const active = _swapping ? (_pendingSwapToA ? playerA : playerB) : (_usePlayerA ? playerA : playerB);
        active.pause();
    }

    function stop() {
        // No-op: clearing source handles cleanup
    }

    anchors.fill: parent

    // ── Player A ──

    VideoOutput {
        id: outputA
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root._usePlayerA
    }

    AudioOutput {
        id: mutedOutputA
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: playerA

        videoOutput: outputA
        audioOutput: mutedOutputA
        loops: MediaPlayer.Infinite
        autoPlay: false

        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                console.warn("VideoPlayer A: error:", errorString);
        }

        onPositionChanged: {
            if (root.forceFrameRenderA && position > 0) {
                root.forceFrameRenderA = false;
                playerA.pause();
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.InvalidMedia)
                console.warn("VideoPlayer A: invalid media:", playerA.source, playerA.errorString);

            // If this is the INCOMING player and it's ready, perform the swap
            if (!root._usePlayerA && !root._swapping && mediaStatus === MediaPlayer.LoadedMedia) {
                root._performSwap(true);
            }

            // First load: player A loaded and is already the active player
            if (root._usePlayerA && mediaStatus === MediaPlayer.LoadedMedia && playerB.source == "" && !root._swapping) {
                if (root.autoStart) {
                    playerA.play();
                } else {
                    root.forceFrameRenderA = true;
                    playerA.play();
                }
            }
        }
    }

    // ── Player B ──

    VideoOutput {
        id: outputB
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: !root._usePlayerA
    }

    AudioOutput {
        id: mutedOutputB
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: playerB

        videoOutput: outputB
        audioOutput: mutedOutputB
        loops: MediaPlayer.Infinite
        autoPlay: false

        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError)
                console.warn("VideoPlayer B: error:", errorString);
        }

        onPositionChanged: {
            if (root.forceFrameRenderB && position > 0) {
                root.forceFrameRenderB = false;
                playerB.pause();
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.InvalidMedia)
                console.warn("VideoPlayer B: invalid media:", playerB.source, playerB.errorString);

            // If this is the INCOMING player and it's ready, perform the swap
            if (root._usePlayerA && !root._swapping && mediaStatus === MediaPlayer.LoadedMedia) {
                root._performSwap(false);
            }
        }
    }

    // Deferred swap: store pending direction for the timer
    property bool _pendingSwapToA: true

    // Timer to defer play() so the picker UI can process click feedback
    // before the main thread blocks on FFmpeg/Vulkan initialization (~2s).
    Timer {
        id: deferredPlayTimer
        interval: 100  // ~6 frames at 60fps — enough for picker click feedback
        repeat: false
        onTriggered: root._executeDeferredSwap()
    }

    function _performSwap(swapToA) {
        _swapping = true;
        _pendingSwapToA = swapToA;

        // Pause old player immediately (frees Vulkan resources, <1ms)
        const oldPlayer = swapToA ? playerB : playerA;
        oldPlayer.pause();

        // Defer play() so picker UI gets time to render
        deferredPlayTimer.restart();
    }

    function _executeDeferredSwap() {
        const swapToA = _pendingSwapToA;
        const newPlayer = swapToA ? playerA : playerB;
        const oldPlayer = swapToA ? playerB : playerA;

        if (root.autoStart) {
            newPlayer.play();
        } else {
            if (swapToA)
                root.forceFrameRenderA = true;
            else
                root.forceFrameRenderB = true;
            newPlayer.play();
        }

        // Swap visibility
        root._usePlayerA = swapToA;

        // Clean up old player source asynchronously
        Qt.callLater(() => {
            oldPlayer.source = "";
            root._swapping = false;
        });
    }

    onVideoSourceChanged: {
        if (videoSource == "" || videoSource.toString() === "") {
            playerA.source = "";
            playerB.source = "";
            return;
        }

        if (playerA.source == "" && playerB.source == "") {
            playerA.source = videoSource;
            _usePlayerA = true;
            return;
        }

        const inactivePlayer = _usePlayerA ? playerB : playerA;
        inactivePlayer.source = videoSource;
    }

    Component.onCompleted: {
        if (videoSource != "" && videoSource.toString() !== "") {
            playerA.source = videoSource;
            _usePlayerA = true;
        }
    }
}
