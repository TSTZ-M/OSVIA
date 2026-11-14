import Foundation
import SwiftUI

// MARK: 回答过程：每一步（回忆、搜索、读网页、计算、调用 MCP……）都记录下来，对话里以时间线显示
enum StepKind: String, Codable {
    case memory, think, search, read, calc, mcp, skill, action, connector, time

    var icon: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .think: return "sparkles"
        case .search: return "magnifyingglass"
        case .read: return "doc.text.magnifyingglass"
        case .calc: return "function"
        case .mcp: return "puzzlepiece.extension"
        case .skill: return "wand.and.stars"
        case .action: return "checkmark.seal"
        case .connector: return "link"
        case .time: return "clock"
        }
    }
}

struct Step: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: StepKind
    var title: String
    var detail = ""
    var state = 0        // 0 进行中 1 完成 2 失败
    var secs = 0.0
}

struct Source: Identifiable, Codable, Equatable {
    var id = UUID()
    var n: Int
    var title: String
    var url: String

    var host: String {
        (URL(string: url)?.host ?? url).replacingOccurrences(of: "www.", with: "")
    }
}

// 随消息一起存进数据库
struct MsgMeta: Codable {
    var steps: [Step] = []
    var sources: [Source] = []
    var dur = 0.0

    var isEmpty: Bool { steps.isEmpty && sources.isEmpty }
}

// 一次回答的记录器：模型和工具在运行中往它里面报告进度，界面立刻更新
@MainActor
final class Tracer {
    let mid: UUID
    private var starts: [UUID: Date] = [:]
    private var seen: [String: Int] = [:]
    private var count = 0

    init(_ mid: UUID) { self.mid = mid }

    @discardableResult
    func begin(_ kind: StepKind, _ title: String, _ detail: String = "") -> UUID {
        let s = Step(kind: kind, title: L10n.tr(title), detail: detail)
        starts[s.id] = Date()
        Agent.shared.mutate(mid) { $0.steps.append(s) }
        return s.id
    }

    func end(_ id: UUID, ok: Bool = true, detail: String? = nil) {
        let secs = Date().timeIntervalSince(starts[id] ?? Date())
        starts[id] = nil
        Agent.shared.mutate(mid) { m in
            guard let i = m.steps.firstIndex(where: { $0.id == id }) else { return }
            m.steps[i].state = ok ? 1 : 2
            m.steps[i].secs = secs
            if let d = detail { m.steps[i].detail = d }
        }
    }

    func detail(_ id: UUID, _ text: String) {
        Agent.shared.mutate(mid) { m in
            if let i = m.steps.firstIndex(where: { $0.id == id }) { m.steps[i].detail = text }
        }
    }

    // 一步就做完的事（比如「调用了 3 条记忆」）
    func note(_ kind: StepKind, _ title: String, _ detail: String = "") {
        end(begin(kind, title, detail))
    }

    // 登记来源，返回全局编号（回答里用 [编号] 引用）
    func register(_ hits: [WebSearch.Hit]) -> [Int] {
        var ns: [Int] = []
        var add: [Source] = []
        for h in hits {
            if let n = seen[h.url] {
                ns.append(n)
                continue
            }
            count += 1
            seen[h.url] = count
            add.append(Source(n: count, title: h.title, url: h.url))
            ns.append(count)
        }
        if !add.isEmpty { Agent.shared.mutate(mid) { $0.sources += add } }
        return ns
    }

    func register(url: String, title: String) -> Int {
        if let n = seen[url] { return n }
        count += 1
        seen[url] = count
        let s = Source(n: count, title: title.isEmpty ? url : title, url: url)
        Agent.shared.mutate(mid) { $0.sources.append(s) }
        return count
    }
}
