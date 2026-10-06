import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "lyrics"

    StyledText {
        text: "歌词 / Lyrics"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "状态栏优先显示网易云现成译文，无译文时显示原文；弹窗逐行显示双语。不调用 AI 翻译。\nPrefer supplied translations in the bar, with original lyrics as fallback and bilingual lines in the popout. No AI translation."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    SelectionSetting {
        settingKey: "lyricsSource"
        label: "歌词源优先级 / Lyrics source"
        description: "选择网易云优先以获取现成译文；lrclib 仅提供原文。\nChoose Netease first for supplied translations; lrclib provides original lyrics only."
        defaultValue: "netease"
        options: [
            { label: "网易云优先 / Netease first", value: "netease" },
            { label: "lrclib 优先 / lrclib first", value: "lrclib" },
            { label: "仅网易云 / Netease only", value: "netease_only" },
            { label: "仅 lrclib / lrclib only", value: "lrclib_only" }
        ]
    }

    SliderSetting {
        settingKey: "maxWidth"
        label: "组件最大宽度 / Max width (px)"
        description: "歌词文字的最大宽度，超出会横向滚动。\nMaximum width of the lyric text; longer lines scroll horizontally."
        minimum: 80
        maximum: 600
        defaultValue: 280
    }

    SelectionSetting {
        settingKey: "gapMode"
        label: "间奏显示方式 / Instrumental display"
        description: "歌曲间奏/停顿时状态栏的显示方式，避免歌词整条消失闪烁。\nHow the bar behaves during instrumental gaps, to avoid flicker."
        defaultValue: "dots"
        options: [
            { label: "跳动圆点 / Pulsing dots", value: "dots" },
            { label: "保留上一句(变暗) / Keep last line", value: "linger" },
            { label: "仅图标占位 / Icon only", value: "blank" }
        ]
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        width: parent.width
        text: "依赖 / Requires: 一个支持 MPRIS 的播放器（经 DMS 内置的 MprisController 读取，无需 playerctl / python3 / 额外进程）。仅显示有同步歌词的曲目；视频/纯音乐会自动隐藏。\nNeeds an MPRIS-capable player (read via DMS's built-in MprisController; no playerctl / python3 / extra process). Only songs with synced lyrics are shown; videos/instrumentals are hidden."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
