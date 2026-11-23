import AppIntents
import Foundation

// 小组件、控制中心按钮、锁屏按钮、操作按钮共用的「打开 OSVIA 的某个入口」。
enum OSVIAEntry: String, AppEnum {
    case chat, voice, mail, tasks

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Entry")
    static var caseDisplayRepresentations: [OSVIAEntry: DisplayRepresentation] = [
        .chat: DisplayRepresentation(title: "Chat", image: .init(systemName: "bubble.left.fill")),
        .voice: DisplayRepresentation(title: "Voice", image: .init(systemName: "mic.fill")),
        .mail: DisplayRepresentation(title: "Mail", image: .init(systemName: "envelope.fill")),
        .tasks: DisplayRepresentation(title: "Tasks", image: .init(systemName: "checklist")),
    ]

    // 对应 osvia:// 链接的 host（URLRouter 处理）
    var link: String {
        switch self {
        case .chat: return "new"
        case .voice: return "voice"
        case .mail: return "mail"
        case .tasks: return "tasks"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.fill"
        case .voice: return "mic.fill"
        case .mail: return "envelope.fill"
        case .tasks: return "checklist"
        }
    }
}

// 不在这里直接调用应用内的路由：冷启动时界面还没就绪，状态会被后面的初始化覆盖。
// 交给系统用 osvia:// 打开应用，走和小组件链接完全相同的 onOpenURL 通路。
struct OpenOSVIAIntent: AppIntent {
    static var title: LocalizedStringResource = "Open OSVIA"

    @Parameter(title: "Entry") var entry: OSVIAEntry

    init() { entry = .chat }
    init(entry: OSVIAEntry) { self.entry = entry }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "osvia://\(entry.link)")!))
    }
}
