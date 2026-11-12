import WidgetKit
import SwiftUI
import ActivityKit

struct Countdown: View {
    let end: Date
    var body: some View {
        let s = Date.now
        Text(timerInterval: s...max(end, s.addingTimeInterval(1)), countsDown: true)
            .monospacedDigit()
    }
}

// 状态图标（按 OSVIA 设计包）：聆听=声波，思考/执行=开口圆环，搜索=放大镜，完成=对勾圆圈，倒计时=数字
struct PhaseIcon: View {
    let phase: String
    var end: Date?
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
        case "timer":
            if let end {
                Countdown(end: end)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(BrandPalette.mint)
            }
        default:
            BrandGlyph(size: size, dot: false, weight: 0.1)
        }
    }
}

struct OSVIALiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BotActivityAttributes.self) { ctx in
            // 锁屏与通知中心：黑底，左边标志，中间 OSVIA + 状态，右边状态图标
            HStack(spacing: 14) {
                BrandGlyph(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.state.title).font(.system(size: 17, weight: .bold)).foregroundStyle(BrandPalette.ink).lineLimit(1)
                    Text(ctx.state.subtitle).font(.system(size: 13)).foregroundStyle(BrandPalette.sub).lineLimit(1)
                }
                Spacer(minLength: 8)
                PhaseIcon(phase: ctx.state.phase, end: ctx.state.end, size: 28)
                    .frame(minWidth: ctx.state.phase == "timer" ? 80 : 0, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .activityBackgroundTint(BrandPalette.bg)
            .activitySystemActionForegroundColor(BrandPalette.mint)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BrandGlyph(size: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseIcon(phase: ctx.state.phase, end: ctx.state.end, size: 26)
                        .frame(minWidth: ctx.state.phase == "timer" ? 70 : 0, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ctx.state.title).font(.system(size: 16, weight: .bold)).foregroundStyle(BrandPalette.ink).lineLimit(1)
                        Text(ctx.state.subtitle).font(.system(size: 13)).foregroundStyle(BrandPalette.sub).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                BrandGlyph(size: 20)
            } compactTrailing: {
                if ctx.state.phase == "timer", let e = ctx.state.end {
                    Countdown(end: e)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandPalette.mint)
                        .frame(width: 48)
                } else {
                    PhaseIcon(phase: ctx.state.phase, end: ctx.state.end, size: 16)
                }
            } minimal: {
                BrandGlyph(size: 18)
            }
            .keylineTint(BrandPalette.mint)
        }
    }
}

@main
struct OSVIALiveBundle: WidgetBundle {
    var body: some Widget { OSVIALiveActivity() }
}
