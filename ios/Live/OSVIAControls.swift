import WidgetKit
import SwiftUI
import AppIntents

// 控制中心 / 锁屏底部按钮 / 操作按钮：一键语音、一键新对话（iOS 18+）。
// 动作是共享的 OpenOSVIAIntent（Shared/OpenIntents.swift），应用和扩展两个 target 都编译它。
struct OSVIAVoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OSVIAVoiceControl") {
            ControlWidgetButton(action: OpenOSVIAIntent(entry: .voice)) {
                Label(lt("OSVIA 语音", "OSVIA Voice"), systemImage: "mic.fill")
            }
            .tint(BrandPalette.mint)
        }
        .displayName(LocalizedStringResource(stringLiteral: lt("OSVIA 语音", "OSVIA Voice")))
        .description(LocalizedStringResource(stringLiteral: lt("一键打开 OSVIA 并开始语音输入。", "Open OSVIA and start voice input.")))
    }
}

struct OSVIAChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OSVIAChatControl") {
            ControlWidgetButton(action: OpenOSVIAIntent(entry: .chat)) {
                Label(lt("OSVIA 对话", "OSVIA Chat"), systemImage: "bubble.left.fill")
            }
            .tint(BrandPalette.mint)
        }
        .displayName(LocalizedStringResource(stringLiteral: lt("OSVIA 对话", "OSVIA Chat")))
        .description(LocalizedStringResource(stringLiteral: lt("一键打开 OSVIA 并开始新对话。", "Open OSVIA and start a new chat.")))
    }
}
