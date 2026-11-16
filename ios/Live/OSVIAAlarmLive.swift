import WidgetKit
import SwiftUI
import ActivityKit
import AlarmKit
import AppIntents

// 系统闹钟 / 倒计时的灵动岛与锁屏界面（AlarmKit）。到点、停止、取消后由系统自己收起，不会残留。
struct OSVIAAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<NoMeta>.self) { ctx in
            AlarmLockView(attrs: ctx.attributes, state: ctx.state)
                .activityBackgroundTint(BrandPalette.bg)
                .activitySystemActionForegroundColor(BrandPalette.mint)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BrandGlyph(size: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTime(state: ctx.state, size: 30).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    AlarmHeading(attrs: ctx.attributes, state: ctx.state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmButtons(attrs: ctx.attributes, state: ctx.state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            } compactLeading: {
                BrandGlyph(size: 20)
            } compactTrailing: {
                AlarmTime(state: ctx.state, size: 13)
                    .frame(width: 50)
            } minimal: {
                BrandGlyph(size: 18)
            }
            .keylineTint(BrandPalette.mint)
        }
    }
}

private struct AlarmLockView: View {
    let attrs: AlarmAttributes<NoMeta>
    let state: AlarmPresentationState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandGlyph(size: 34)
            VStack(alignment: .leading, spacing: 10) {
                AlarmHeading(attrs: attrs, state: state)
                AlarmButtons(attrs: attrs, state: state)
            }
            Spacer(minLength: 8)
            AlarmTime(state: state, size: 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct AlarmHeading: View {
    let attrs: AlarmAttributes<NoMeta>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OSVIA")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.mint)
            switch state.mode {
            case .countdown:
                if let t = attrs.presentation.countdown?.title { Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(BrandPalette.ink).lineLimit(1) }
            case .paused:
                if let t = attrs.presentation.paused?.title { Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(BrandPalette.ink).lineLimit(1) }
            default:
                Text(attrs.presentation.alert.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(BrandPalette.ink).lineLimit(1)
            }
        }
    }
}

private struct AlarmTime: View {
    let state: AlarmPresentationState
    var size: CGFloat

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let c):
                let now = Date.now
                Text(timerInterval: now ..< max(c.fireDate, now.addingTimeInterval(1)), countsDown: true)
            case .paused(let p):
                Text(Self.format(p.totalCountdownDuration - p.previouslyElapsedDuration))
            default:
                Image(systemName: "bell.fill")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(BrandPalette.mint)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.trailing)
    }

    static func format(_ x: TimeInterval) -> String {
        let s = Int(max(0, x))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct AlarmButtons: View {
    let attrs: AlarmAttributes<NoMeta>
    let state: AlarmPresentationState

    private func pill(_ text: LocalizedStringResource, _ icon: String, _ tint: Color) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon) }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    var body: some View {
        let id = state.alarmID.uuidString
        HStack(spacing: 8) {
            switch state.mode {
            case .countdown:
                if let b = attrs.presentation.countdown?.pauseButton {
                    Button(intent: AlarmPauseIntent(alarmID: id)) { pill(b.text, b.systemImageName, BrandPalette.mint) }.buttonStyle(.plain)
                }
                Button(intent: AlarmStopIntent(alarmID: id)) { pill(attrs.presentation.alert.stopButton.text, "xmark", BrandPalette.sub) }.buttonStyle(.plain)
            case .paused:
                if let b = attrs.presentation.paused?.resumeButton {
                    Button(intent: AlarmResumeIntent(alarmID: id)) { pill(b.text, b.systemImageName, BrandPalette.mint) }.buttonStyle(.plain)
                }
                Button(intent: AlarmStopIntent(alarmID: id)) { pill(attrs.presentation.alert.stopButton.text, "xmark", BrandPalette.sub) }.buttonStyle(.plain)
            default:
                Button(intent: AlarmStopIntent(alarmID: id)) { pill(attrs.presentation.alert.stopButton.text, attrs.presentation.alert.stopButton.systemImageName, BrandPalette.mint) }.buttonStyle(.plain)
            }
        }
    }
}
