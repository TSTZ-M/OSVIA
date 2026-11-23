import WidgetKit
import SwiftUI
import AppIntents

// 控制中心 / 锁屏底部按钮 / 操作按钮：一键语音、一键新对话（iOS 18+）。
// 动作是共享的 OpenOSVIAIntent（Shared/OpenIntents.swift），应用和扩展两个 target 都编译它。
struct OSVIAVoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OSVIAVoiceControl") {
            ControlWidgetButton(action: OpenOSVIAIntent(entry: .voice)) {
                Label(String(localized: "OSVIA Voice"), systemImage: "mic.fill")
            }
            .tint(BrandPalette.mint)
        }
        .displayName("OSVIA Voice")
        .description("Open OSVIA and start voice input.")
    }
}

struct OSVIAChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OSVIAChatControl") {
            ControlWidgetButton(action: OpenOSVIAIntent(entry: .chat)) {
                Label(String(localized: "OSVIA Chat"), systemImage: "bubble.left.fill")
            }
            .tint(BrandPalette.mint)
        }
        .displayName("OSVIA Chat")
        .description("Open OSVIA and start a new chat.")
    }
}
