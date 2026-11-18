import WidgetKit
import SwiftUI
import ActivityKit

// 扩展里的中英文文案：跟随系统语言（应用内的状态文字由应用按应用语言翻译后传进来）
func lt(_ zh: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "zh" ? zh : en
}

// 状态图标（按 OSVIA 设计包）：聆听=声波，思考/执行=开口圆环，搜索=放大镜，完成=对勾圆圈
struct PhaseIcon: View {
    let phase: String
    var size: CGFloat = 26

    private let bars: [CGFloat] = [0.38, 0.72, 0.5, 1.0, 0.45]

    var body: some View {
        switch phase {
        case "listening":
            HStack(spacing: size * 0.12) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule().fill(BrandPalette.mint).frame(width: size * 0.13, height: size * bars[i])
                }
            }
            .frame(height: size)
        case "searching":
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.85, weight: .regular))
                .foregroundStyle(BrandPalette.mint)
        case "done":
            Image(systemName: "checkmark.circle")
                .font(.system(size: size * 0.95, weight: .regular))
                .foregroundStyle(BrandPalette.mint)
        default:
            BrandGlyph(size: size, dot: false, weight: 0.1)
        }
    }
}

// 四格进度：思考 → 搜索 → 执行 → 完成。一眼看出做到哪一步，当前这一格高亮
struct StepBar: View {
    let phase: String

    private var index: Int {
        switch phase {
        case "searching": return 2
        case "working": return 3
        case "done": return 4
        default: return 1
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < index ? BrandPalette.mint.opacity(i == index - 1 && phase != "done" ? 1 : 0.55) : BrandPalette.line)
                    .frame(height: 3)
            }
        }
        .animation(.smooth, value: index)
    }
}

// 已用时：系统自己走字，不需要应用不断更新
private struct Elapsed: View {
    let start: Date?
    let phase: String

    var body: some View {
        if let s = start, phase != "done" {
            Text(s, style: .timer)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(BrandPalette.sub)
                .multilineTextAlignment(.trailing)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

// 进度条 + 已用时，放在最下面一行
private struct ProgressRow: View {
    let state: BotActivityAttributes.ContentState

    var body: some View {
        if state.phase != "listening" {
            HStack(spacing: 10) {
                StepBar(phase: state.phase)
                Elapsed(start: state.started, phase: state.phase)
            }
        } else if state.started != nil {
            HStack {
                Spacer(minLength: 0)
                Elapsed(start: state.started, phase: state.phase)
            }
        }
    }
}

// 主标题：优先显示这次请求的一句话概述，没有就显示当前状态；状态作为副标题。超时没更新时提示一下
private struct Heading: View {
    let state: BotActivityAttributes.ContentState
    var stale = false
    var big: CGFloat = 16

    var body: some View {
        let hasDetail = !(state.detail ?? "").isEmpty
        let sub = stale ? lt("已超时，请回到应用查看", "Timed out - open the app") : state.subtitle
        VStack(alignment: .leading, spacing: 2) {
            Text("OSVIA")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.mint)
            Text(hasDetail && !stale ? (state.detail ?? "") : sub)
                .font(.system(size: big, weight: .semibold))
                .foregroundStyle(BrandPalette.ink)
                .lineLimit(1)
            if hasDetail && !stale {
                Text(sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(BrandPalette.sub)
                    .lineLimit(1)
            }
        }
    }
}

struct OSVIALiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotActivityAttributes.self) { ctx in
            // 锁屏与通知中心
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BrandPalette.panel)
                        BrandGlyph(size: 26)
                    }
                    .frame(width: 42, height: 42)
                    Heading(state: ctx.state, stale: ctx.isStale)
                    Spacer(minLength: 8)
                    PhaseIcon(phase: ctx.state.phase, size: 28)
                }
                ProgressRow(state: ctx.state)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .opacity(ctx.isStale ? 0.6 : 1)
            .activityBackgroundTint(BrandPalette.bg)
            .activitySystemActionForegroundColor(BrandPalette.mint)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BrandGlyph(size: 32).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseIcon(phase: ctx.state.phase, size: 28).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Heading(state: ctx.state, stale: ctx.isStale, big: 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressRow(state: ctx.state)
                        .padding(.top, 6)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                BrandGlyph(size: 20)
            } compactTrailing: {
                PhaseIcon(phase: ctx.state.phase, size: 16)
            } minimal: {
                // 多个活动同时占岛时只露这一小格：完成时给对勾，其余显示品牌圆环
                if ctx.state.phase == "done" {
                    PhaseIcon(phase: "done", size: 16)
                } else {
                    BrandGlyph(size: 18)
                }
            }
            .keylineTint(BrandPalette.mint)
        }
    }
}
