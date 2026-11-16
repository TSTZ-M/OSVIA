import WidgetKit
import SwiftUI
import ActivityKit

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

// 四格进度：思考 → 搜索 → 执行 → 完成。一眼看出做到哪一步
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
                    .fill(i < index ? BrandPalette.mint : BrandPalette.line)
                    .frame(height: 3)
            }
        }
    }
}

// 主标题：优先显示这次请求的一句话概述，没有就显示当前状态；状态作为副标题
private struct Heading: View {
    let state: BotActivityAttributes.ContentState
    var big: CGFloat = 16

    var body: some View {
        let hasDetail = !(state.detail ?? "").isEmpty
        VStack(alignment: .leading, spacing: 2) {
            Text("OSVIA")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.mint)
            Text(hasDetail ? (state.detail ?? "") : state.subtitle)
                .font(.system(size: big, weight: .semibold))
                .foregroundStyle(BrandPalette.ink)
                .lineLimit(1)
            if hasDetail {
                Text(state.subtitle)
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
                    Heading(state: ctx.state)
                    Spacer(minLength: 8)
                    PhaseIcon(phase: ctx.state.phase, size: 28)
                }
                if ctx.state.phase != "listening" { StepBar(phase: ctx.state.phase) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
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
                    Heading(state: ctx.state, big: 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if ctx.state.phase != "listening" {
                        StepBar(phase: ctx.state.phase).padding(.top, 6).padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                BrandGlyph(size: 20)
            } compactTrailing: {
                PhaseIcon(phase: ctx.state.phase, size: 16)
            } minimal: {
                BrandGlyph(size: 18)
            }
            .keylineTint(BrandPalette.mint)
        }
    }
}
