import WidgetKit
import SwiftUI

// 主屏 / 锁屏小组件：一点就进入对话、语音、邮箱、任务（通过 osvia:// 链接直达）
private func tr(_ zh: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "zh" ? zh : en
}

struct QuickEntry: TimelineEntry { let date: Date }

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) { completion(QuickEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: .now)], policy: .never))
    }
}

private struct Tile: View {
    let icon: String
    let title: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(BrandPalette.mint)
                    .frame(width: 44, height: 44)
                    .background(BrandPalette.bubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                BrandGlyph(size: 38)
                Spacer(minLength: 0)
                Text(tr("问点什么？", "Ask anything"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                Text(tr("点一下开始对话", "Tap to start"))
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.sub)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "osvia://new"))
            .containerBackground(BrandPalette.bg, for: .widget)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BrandGlyph(size: 22)
                    Text("OSVIA")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(BrandPalette.mint)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Tile(icon: "bubble.left.fill", title: tr("对话", "Chat"), url: "osvia://new")
                    Tile(icon: "mic.fill", title: tr("语音", "Voice"), url: "osvia://voice")
                    Tile(icon: "envelope.fill", title: tr("邮箱", "Mail"), url: "osvia://mail")
                    Tile(icon: "checklist", title: tr("任务", "Tasks"), url: "osvia://tasks")
                }
            }
            .containerBackground(BrandPalette.bg, for: .widget)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                BrandGlyph(size: 30)
            }
            .widgetURL(URL(string: "osvia://voice"))
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                BrandGlyph(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OSVIA").font(.system(size: 13, weight: .semibold))
                    Text(tr("点一下，说出你的需求", "Tap and speak")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .widgetURL(URL(string: "osvia://voice"))
            .containerBackground(.clear, for: .widget)
        default:
            Text("OSVIA · " + tr("问点什么", "Ask"))
                .widgetURL(URL(string: "osvia://new"))
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct OSVIAQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OSVIAQuick", provider: QuickProvider()) { _ in
            QuickView()
        }
        .configurationDisplayName("OSVIA")
        .description(tr("一点就开始对话、语音，或直达邮箱和任务。", "Jump into chat, voice, mail or tasks."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct OSVIALiveBundle: WidgetBundle {
    var body: some Widget {
        OSVIALiveActivity()
        OSVIAAlarmLiveActivity()
        OSVIAQuickWidget()
    }
}
