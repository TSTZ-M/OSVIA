import WidgetKit
import SwiftUI
import AppIntents

// 主屏 / 锁屏小组件：一点就进入对话、语音、邮箱、任务（通过 osvia:// 链接直达）。
// 小尺寸和锁屏圆形可以在「编辑小组件」里选入口；适配 iOS 26 的着色 / 强调色渲染。

struct QuickConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "OSVIA"
    static var description = IntentDescription("Choose where a tap leads")

    @Parameter(title: "Entry", default: .chat) var entry: OSVIAEntry

    init() {}
}

struct QuickEntry: TimelineEntry {
    let date: Date
    let entry: OSVIAEntry
}

struct QuickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now, entry: .chat) }
    func snapshot(for configuration: QuickConfig, in context: Context) async -> QuickEntry {
        QuickEntry(date: .now, entry: configuration.entry)
    }
    func timeline(for configuration: QuickConfig, in context: Context) async -> Timeline<QuickEntry> {
        // 内容固定，不需要定时刷新；改配置时系统会自己重新取
        Timeline(entries: [QuickEntry(date: .now, entry: configuration.entry)], policy: .never)
    }
}

private extension OSVIAEntry {
    var name: String {
        switch self {
        case .chat: return String(localized: "Chat")
        case .voice: return String(localized: "Voice")
        case .mail: return String(localized: "Mail")
        case .tasks: return String(localized: "Tasks")
        }
    }

    var hint: String {
        switch self {
        case .chat: return String(localized: "Tap to start")
        case .voice: return String(localized: "Tap and speak")
        case .mail: return String(localized: "Review your mail")
        case .tasks: return String(localized: "See today's tasks")
        }
    }

    var title: String {
        switch self {
        case .chat: return String(localized: "Ask anything")
        case .voice: return String(localized: "Say it")
        case .mail: return String(localized: "Mail")
        case .tasks: return String(localized: "Tasks")
        }
    }

    var url: URL { URL(string: "osvia://\(link)")! }
}

private struct Tile: View {
    let entry: OSVIAEntry

    var body: some View {
        Link(destination: entry.url) {
            VStack(spacing: 7) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(BrandPalette.mint)
                    .frame(width: 44, height: 44)
                    .background(BrandPalette.bubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .widgetAccentable()
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickView: View {
    @Environment(\.widgetFamily) private var family
    let e: QuickEntry

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    BrandGlyph(size: 34).widgetAccentable()
                    Spacer(minLength: 0)
                    if e.entry != .chat {
                        Image(systemName: e.entry.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BrandPalette.mint)
                            .widgetAccentable()
                    }
                }
                Spacer(minLength: 0)
                Text(e.entry.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(e.entry.hint)
                    .font(.system(size: 12))
                    .foregroundStyle(BrandPalette.sub)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(e.entry.url)
            .containerBackground(BrandPalette.bg, for: .widget)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BrandGlyph(size: 22).widgetAccentable()
                    Text("OSVIA")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(BrandPalette.mint)
                        .widgetAccentable()
                    Spacer()
                }
                HStack(spacing: 6) {
                    ForEach([OSVIAEntry.chat, .voice, .mail, .tasks], id: \.self) { Tile(entry: $0) }
                }
            }
            .containerBackground(BrandPalette.bg, for: .widget)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if e.entry == .chat {
                    BrandGlyph(size: 30)
                } else {
                    Image(systemName: e.entry.symbol).font(.system(size: 20, weight: .semibold))
                }
            }
            .widgetURL(e.entry.url)
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                BrandGlyph(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OSVIA").font(.system(size: 13, weight: .semibold)).widgetAccentable()
                    Text(e.entry.hint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.85)
                }
            }
            .widgetURL(e.entry.url)
            .containerBackground(.clear, for: .widget)
        default:
            Text("OSVIA · " + e.entry.name)
                .widgetURL(e.entry.url)
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct OSVIAQuickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OSVIAQuick", intent: QuickConfig.self, provider: QuickProvider()) { e in
            QuickView(e: e)
        }
        .configurationDisplayName("OSVIA")
        .description(String(localized: "Jump into chat, voice, mail or tasks. Pick the entry for small and Lock Screen widgets."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct OSVIALiveBundle: WidgetBundle {
    var body: some Widget {
        OSVIALiveActivity()
        OSVIAAlarmLiveActivity()
        OSVIAQuickWidget()
        OSVIAVoiceControl()
        OSVIAChatControl()
    }
}
