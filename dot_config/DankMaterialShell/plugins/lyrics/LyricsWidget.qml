pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "LyricsFetcher.js" as Fetcher

PluginComponent {
    id: root

    property string currentLine: ""
    property int currentIndex: -1
    property real currentProgress: 0.0
    property string currentSongTitle: ""
    property string currentSongArtist: ""

    property string currentSongKey: ""

    // settings, read reactively to solve reactivity bug
    readonly property string settingsJson: JSON.stringify(SettingsData.pluginSettings[pluginId] ?? {})
    readonly property var pd: JSON.parse(settingsJson)
    readonly property string lyricsSource: pd.lyricsSource ?? "netease"
    readonly property int maxWidth: pd.maxWidth ?? 280
    // 间奏/停顿(当前无歌词行)时状态栏的显示方式: dots | linger | blank
    readonly property string gapMode: pd.gapMode ?? "dots"

    // Preserve the preferred display text through instrumental gaps.
    property string lastNonEmpty: ""
    onCurrentLineChanged: if (currentLine !== "") lastNonEmpty = currentLine

    // "间奏"判定：已加载带歌词的歌曲，但当前行为空(前奏/间奏/空 LRC 行)
    readonly property bool inGap: currentLine === "" && lyricsModel.count > 0

    // 状态栏 marquee 实际显示的内容与方式
    readonly property string barText: !inGap ? currentLine
                                             : (gapMode === "linger" ? lastNonEmpty : "")
    readonly property bool barShowDots: inGap && gapMode === "dots"
    readonly property real barDimOpacity: (inGap && gapMode === "linger") ? 0.45 : 1.0

    // Set popout dimensions
    popoutWidth: 400
    popoutHeight: 480

    // 仅当没有可显示的歌词(无媒体/无同步歌词)时整条隐藏；
    // 间奏/空行时保持可见，避免整条消失再出现的闪烁。
    _visibilityOverride: true
    _visibilityOverrideValue: lyricsModel.count > 0

    // 当前活动播放器：由 DMS 的 MprisController 统一管理(播放器选择、切换、
    // D-Bus 连接与自愈都由它负责,这里只需读取)。
    readonly property var player: MprisController.activePlayer
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying
    // 播放器"停止"(区别于暂停):MprisController 仅在元数据同时清空时才会移除
    // activePlayer,保留元数据的播放器停止后 player 不变、任何信号都不会触发,
    // 必须显式监听 Stopped 状态,否则歌词永远残留(本插件曾有此 Bug)。
    readonly property bool stopped: hasPlayer && player.playbackState === MprisPlaybackState.Stopped

    ListModel {
        id: lyricsModel
    }

    readonly property int lyricsCount: lyricsModel.count
    property Component lyricsView: Component {
        LyricsView {
            model: lyricsModel
            activeIndex: root.currentIndex
        }
    }

    // 本地平滑驱动 currentProgress,消除 D-Bus position 抖动
    NumberAnimation {
        id: progressAnim
        target: root
        property: "currentProgress"
        easing.type: Easing.Linear
    }

    // ---- 歌词加载与同步 ----

    function clearAll() {
        currentSongKey = "";
        lyricsModel.clear();
        currentLine = "";
        lastNonEmpty = "";
        currentIndex = -1;
        currentProgress = 0.0;
        currentSongTitle = "";
        currentSongArtist = "";
        progressAnim.running = false;
    }

    // 检测换歌;若为新曲则异步拉取歌词
    function songChanged() {
        if (!hasPlayer || stopped) {
            clearAll();
            return;
        }
        var title = player.trackTitle || "";
        var artist = player.trackArtist || "";
        if (title === "") {
            clearAll();
            return;
        }

        var album = player.trackAlbum || "";
        var duration = (player.lengthSupported && player.length > 0) ? Math.round(player.length) : 0;
        var key = JSON.stringify([artist, title, album, duration]);
        if (key === currentSongKey)
            return;
        currentSongKey = key;

        // 立即复位显示,避免残留上一首的歌词
        lyricsModel.clear();
        currentLine = "";
        lastNonEmpty = "";
        currentIndex = -1;
        currentProgress = 0.0;
        progressAnim.running = false;
        currentSongTitle = title;
        currentSongArtist = artist;

        Fetcher.fetchLyrics(lyricsSource, title, artist, album, duration, function (lyrics) {
            // 异步回调:确认仍是同一首(可能已切歌或已切歌词源)
            if (key !== currentSongKey)
                return;
            lyricsModel.clear();
            for (var i = 0; i < lyrics.length; i++)
                lyricsModel.append({
                    time: lyrics[i].time,
                    text: lyrics[i].text,
                    translation: lyrics[i].translation
                });
            currentIndex = -1;
            currentProgress = 0.0;
            progressAnim.running = false;
            if (lyricsModel.count > 0)
                updateSync(); // 立即定位到当前行
        });
    }

    // 按当前播放位置返回应高亮的歌词行下标(-1 表示前奏/间奏)
    function currentIndexAt(pos) {
        var idx = -1;
        for (var i = 0; i < lyricsModel.count; i++) {
            if (lyricsModel.get(i).time <= pos + 0.2)
                idx = i;
            else
                break;
        }
        return idx;
    }

    // 依据播放位置刷新当前行与进度动画
    function updateSync() {
        if (lyricsModel.count === 0 || !hasPlayer)
            return;

        var pos = player.position || 0;
        // 单曲循环修复:Quickshell 的 position 是客户端插值,基线仅在 seek/换轨/播放暂停时
        // 刷新;循环重播同一轨(不发 Seeked)时它会越过曲长且永不归零,导致行号卡在最后一行、
        // 歌词不再推进。越过曲长即按曲长取模,还原当前循环内的真实位置(N×曲长+pos → pos)。
        // 正常播放(pos ≤ 曲长)时为 no-op,零副作用。
        var len = (player.lengthSupported && player.length > 0) ? player.length : 0;
        if (len > 0 && pos >= len)
            pos = pos % len;
        var i = currentIndexAt(pos);
        if (i !== currentIndex) {
            currentIndex = i;
            currentLine = (i >= 0 && i < lyricsModel.count) ? Fetcher.preferredText(lyricsModel.get(i)) : "";
        }

        var progress = 0.0;
        var lineDuration = 5.0;
        if (i >= 0 && i < lyricsModel.count) {
            var curT = lyricsModel.get(i).time;
            var nextT;
            if (i + 1 < lyricsModel.count)
                nextT = lyricsModel.get(i + 1).time;
            else if (player.lengthSupported && player.length > 0)
                nextT = player.length;
            else
                nextT = curT + 8.0;
            lineDuration = nextT - curT;
            if (lineDuration > 0)
                progress = Math.max(0.0, Math.min(1.0, (pos - curT) / lineDuration));
        }

        progressAnim.running = false;
        currentProgress = progress;
        if (playing && i >= 0 && progress < 1.0) {
            progressAnim.from = progress;
            progressAnim.to = 1.0;
            progressAnim.duration = (lineDuration * (1.0 - progress)) * 1000;
            progressAnim.running = true;
        }
    }

    // 播放中定时刷新 D-Bus 位置并同步歌词(取代 Rust 后端的 FAST 轮询)
    Timer {
        id: posTimer
        interval: 250
        repeat: true
        running: root.playing && lyricsModel.count > 0
        onTriggered: {
            if (root.hasPlayer)
                root.player.positionChanged(); // 强制刷新 position
            root.updateSync();
        }
    }

    // 换歌检测:监听当前播放器的标题/艺术家变化
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.songChanged(); }
        function onTrackArtistChanged() { root.songChanged(); }
        function onTrackAlbumChanged() { root.songChanged(); }
        function onLengthChanged() { root.songChanged(); }
        // 进度跳转(seek):Quickshell 在 seek 时会自主 emit positionChanged(播放/暂停均如此),
        // 立即重算当前行,不必等 250ms 轮询;尤其修复"暂停时拖动进度 posTimer 不跑、歌词不跟"。
        function onPositionChanged() { root.updateSync(); }
    }

    // 活动播放器本身切换(或消失)
    onPlayerChanged: {
        if (hasPlayer)
            songChanged();
        else
            clearAll();
    }

    // 暂停/播放切换时立即重算一次(与 Rust 的 status_changed 一致)
    onPlayingChanged: updateSync()

    // 停止→清空;从停止恢复→重新加载(clearAll 已清 currentSongKey,会重新抓词)。
    // 暂停不清空:歌词保留在当前行。
    onStoppedChanged: songChanged()

    // 切换歌词源:清缓存并对当前曲目重新抓取
    onLyricsSourceChanged: {
        Fetcher.clearCache();
        currentSongKey = "";
        songChanged();
    }

    Component.onCompleted: if (hasPlayer) songChanged()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "lyrics"
                size: 16
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                id: marqueeContainer
                width: root.barShowDots ? dotsRow.implicitWidth
                                        : Math.min(lyricText.implicitWidth, root.maxWidth)
                height: lyricText.implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                // linger 模式间奏时整体调暗；其它模式保持 1.0
                opacity: root.barDimOpacity
                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }

                StyledText {
                    id: lyricText
                    text: ""
                    textFormat: Text.PlainText
                    visible: !root.barShowDots
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig ? root.barConfig.fontScale : undefined)
                    color: Theme.widgetTextColor
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.NoWrap

                    readonly property real maxScroll: implicitWidth - marqueeContainer.width
                    x: maxScroll > 0 ? -root.currentProgress * maxScroll : 0

                    // 文本内容切换时的淡入淡出
                    opacity: 1.0
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                    }

                    Component.onCompleted: {
                        lyricText.text = root.barText;
                    }

                    Connections {
                        target: root
                        function onBarTextChanged() {
                            fadeTransition.restart();
                        }
                    }

                    SequentialAnimation {
                        id: fadeTransition
                        NumberAnimation { target: lyricText; property: "opacity"; to: 0.0; duration: 150; easing.type: Easing.InOutQuad }
                        ScriptAction { script: lyricText.text = root.barText }
                        NumberAnimation { target: lyricText; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.InOutQuad }
                    }
                }

                // 间奏跳动圆点指示器 (dots 模式)
                Row {
                    id: dotsRow
                    visible: root.barShowDots
                    spacing: 3
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: 3
                        Rectangle {
                            id: gapDot
                            required property int index
                            width: 4
                            height: 4
                            radius: 2
                            color: Theme.widgetTextColor
                            opacity: 0.3
                            SequentialAnimation on opacity {
                                running: dotsRow.visible
                                loops: Animation.Infinite
                                PauseAnimation { duration: gapDot.index * 180 }
                                NumberAnimation { to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 0.3; duration: 350; easing.type: Easing.InOutQuad }
                                PauseAnimation { duration: (2 - gapDot.index) * 180 }
                            }
                        }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "lyrics"
            size: 16
            color: lyricsModel.count > 0 ? Theme.primary : Theme.widgetTextColor
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // Popout content containing the Apple Music style scrolling lyrics
    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot
            headerText: root.currentSongTitle !== "" ? root.currentSongTitle : "歌词 / Lyrics"
            showCloseButton: true

            Item {
                width: parent.width
                height: 420

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        text: root.currentSongArtist
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.italic: true
                        color: Theme.surfaceVariantText
                        Layout.fillWidth: true
                        visible: root.currentSongArtist !== ""
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        color: Theme.surfaceVariant
                        Layout.preferredHeight: 1
                        Layout.fillWidth: true
                        visible: root.currentSongArtist !== ""
                    }

                    StyledText {
                        text: "当前无歌词播放\nNo lyrics playing"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        visible: lyricsModel.count === 0
                    }

                    Loader {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: lyricsModel.count > 0
                        sourceComponent: root.lyricsView
                    }
                }
            }
        }
    }
}
