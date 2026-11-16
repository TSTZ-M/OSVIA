import ActivityKit
import Foundation

// 灵动岛 / 锁屏实时活动：聆听、思考、搜索、执行、完成，以及闹钟与任务倒计时。
// 所有操作排成一条队列依次执行，避免「结束」和「更新」互相抢先。显示的文字按应用当前语言翻译。
enum Live {
    enum Phase: String {
        case listening, thinking, searching, working, done

        var text: String {
            switch self {
            case .listening: return "聆听中"
            case .thinking: return "思考中"
            case .searching: return "正在搜索网页"
            case .working: return "正在执行任务"
            case .done: return "任务已完成"
            }
        }
    }

    private static var enabled: Bool {
        (UserDefaults.standard.object(forKey: "liveOn") as? Bool ?? true) && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // 当前这次请求的一句话概述，显示在岛上
    static var query = ""

    private static let lock = NSLock()
    private static var last: Task<Void, Never>?

    private static func enqueue(_ op: @escaping () async -> Void) {
        lock.lock()
        let prev = last
        last = Task {
            _ = await prev?.value
            await op()
        }
        lock.unlock()
    }

    private static func assistant() -> Activity<BotActivityAttributes>? {
        Activity<BotActivityAttributes>.activities.first(where: { $0.attributes.kind == "think" })
    }

    // 切换到某个状态（已有就更新，没有就新建）
    static func set(_ p: Phase, _ subtitle: String? = nil) {
        guard enabled else { return }
        let sub = L10n.tr(subtitle ?? p.text)
        let detail: String? = query.isEmpty ? nil : query
        enqueue {
            let st = BotActivityAttributes.ContentState(title: Brand.name, subtitle: sub, end: nil, phase: p.rawValue, detail: detail)
            let content = ActivityContent(state: st, staleDate: Date().addingTimeInterval(180))
            if let a = assistant() {
                await a.update(content)
            } else {
                _ = try? Activity.request(attributes: BotActivityAttributes(kind: "think"), content: content, pushType: nil)
            }
        }
    }

    // 语音输入：开始时显示「聆听中」，结束时如果还停在聆听状态就收起
    static func listening(_ on: Bool) {
        if on {
            set(.listening)
        } else {
            guard enabled else { return }
            enqueue {
                if let a = assistant(), a.content.state.phase == Phase.listening.rawValue {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // 开始思考 / 思考结束（结束时先显示「任务已完成」两秒再收起）
    static func thinking(_ on: Bool, query q: String? = nil) {
        if on {
            if let q { query = String(q.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(30)) }
            set(.thinking)
        } else {
            finish()
        }
    }

    static func finish() {
        guard enabled else { return }
        let sub = L10n.tr(Phase.done.text)
        let detail: String? = query.isEmpty ? nil : query
        enqueue {
            guard let a = assistant() else { return }
            let st = BotActivityAttributes.ContentState(title: Brand.name, subtitle: sub, end: nil, phase: Phase.done.rawValue, detail: detail)
            await a.update(ActivityContent(state: st, staleDate: Date().addingTimeInterval(30)))
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            enqueue {
                if let a = assistant(), a.content.state.phase == Phase.done.rawValue {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // 清理残留：旧版本留下的倒计时、过期没收起的状态，一律结束。启动和回到前台时调用。
    // 闹钟与倒计时现在交给系统（AlarmKit），到点由系统自己收起，这里不再自建。
    static func sweep() {
        Task {
            let busy = await MainActor.run { Agent.shared.busy }
            for a in Activity<BotActivityAttributes>.activities {
                let stale = a.activityState == .stale || a.activityState == .ended
                if a.attributes.kind == "timer" || a.content.state.end != nil || (stale && !busy) {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
