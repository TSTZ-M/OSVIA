import WidgetKit
import SwiftUI
import AppIntents

// 主屏 / 锁屏小组件：一点就进入对话、语音、邮箱、任务（通过 osvia:// 链接直达）。
// 小尺寸和锁屏圆形可以在「编辑小组件」里选入口；适配 iOS 26 的着色 / 强调色渲染。

struct QuickConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "OSVIA"
    static var description = IntentDescription("选择点击后进入的位置")

    @Parameter(title: "入口", default: .chat) var entry: OSVIAEntry

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
        case .chat: return lt("对话", "Chat")
        case .voice: return lt("语音", "Voice")
        case .mail: return lt("邮箱", "Mail")
        case .tasks: return lt("任务", "Tasks")
        }
    }

    var hint: String {
        switch self {
        case .chat: return lt("点一下开始对话", "Tap to start")
        case .voice: return lt("点一下，说出你的需求", "Tap and speak")
        case .mail: return lt("查看并处理邮件", "Review your mail")
        case .tasks: return lt("查看今天的任务", "See today's tasks")
        }
    }

    var title: String {
        switch self {
        case .chat: return lt("问点什么？", "Ask anything")
        case .voice: return lt("说出你的需求", "Say it")
        case .mail: return lt("邮箱", "Mail")
        case .tasks: return lt("任务", "Tasks")
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                    Text(e.entry.hint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
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
        .description(lt("一点就开始对话、语音，或直达邮箱和任务。小尺寸和锁屏可选入口。", "Jump into chat, voice, mail or tasks. Pick the entry for small and Lock Screen widgets."))
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
