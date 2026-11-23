import ActivityKit
import Foundation
import UIKit

// 灵动岛 / 锁屏实时活动：聆听、思考、搜索、执行、完成。闹钟与倒计时交给系统（AlarmKit）。
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
    private static var beat: Task<Void, Never>?

    // 心跳：任务跑得久（长转写、大文件处理）时，每 90 秒续一次过期时间，岛上不会在干活时误显示「已超时」
    private static func startBeat() {
        lock.lock()
        defer { lock.unlock() }
        guard beat == nil else { return }
        beat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if Task.isCancelled { break }
                await enqueue {
                    guard let a = await assistant(), a.content.state.phase != Phase.done.rawValue else { return }
                    await a.update(ActivityContent(state: a.content.state, staleDate: Date().addingTimeInterval(180), relevanceScore: 80))
                }.value
            }
        }
    }

    private static func stopBeat() {
        lock.lock()
        beat?.cancel()
        beat = nil
        lock.unlock()
    }

    @discardableResult
    private static func enqueue(_ op: @escaping () async -> Void) -> Task<Void, Never> {
        lock.lock()
        let prev = last
        let t = Task {
            _ = await prev?.value
            await op()
        }
        last = t
        lock.unlock()
        return t
    }

    // 当前可更新的助理活动。已结束的不算（否则之后的更新全部落空，岛上再也不出现）；重复的顺手结束
    private static func assistant() async -> Activity<BotActivityAttributes>? {
        let usable = Activity<BotActivityAttributes>.activities.filter {
            $0.attributes.kind == "think" && ($0.activityState == .active || $0.activityState == .stale)
        }
        for extra in usable.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        return usable.first
    }

    // 切换到某个状态（已有就更新，没有就新建）
    static func set(_ p: Phase, _ subtitle: String? = nil) {
        guard enabled else { return }
        let sub = L10n.tr(subtitle ?? p.text)
        let detail: String? = query.isEmpty ? nil : query
        startBeat()
        enqueue {
            let existing = await assistant()
            // 上一次已经显示「完成」的话，这是一次新请求，计时从头开始
            let prev = existing?.content.state
            let started = (prev?.phase == Phase.done.rawValue ? nil : prev?.started) ?? Date()
            let st = BotActivityAttributes.ContentState(title: Brand.name, subtitle: sub, end: nil, phase: p.rawValue, detail: detail, started: started)
            let content = ActivityContent(state: st, staleDate: Date().addingTimeInterval(180), relevanceScore: 80)
            if let a = existing {
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
            stopBeat()
            enqueue {
                if let a = await assistant(), a.content.state.phase == Phase.listening.rawValue {
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
        stopBeat()
        guard enabled else { return }
        let sub = L10n.tr(Phase.done.text)
        let detail: String? = query.isEmpty ? nil : query
        enqueue {
            guard let a = await assistant() else { return }
            let st = BotActivityAttributes.ContentState(title: Brand.name, subtitle: sub, end: nil, phase: Phase.done.rawValue, detail: detail, started: a.content.state.started)
            await a.update(ActivityContent(state: st, staleDate: Date().addingTimeInterval(30), relevanceScore: 80))
        }
        // 两秒后收起。用后台任务护住这段等待：用户刚好切走应用时也能收掉，不会残留
        Task { @MainActor in
            let bg = UIApplication.shared.beginBackgroundTask(withName: "osvia.live.finish", expirationHandler: nil)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await enqueue {
                if let a = await assistant(), a.content.state.phase == Phase.done.rawValue {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }.value
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }
    }

    // 清理残留：旧版本留下的倒计时、过期没收起的状态、上次被杀掉时没来得及收起的状态，一律结束。启动和回到前台时调用。
    // 闹钟与倒计时交给系统（AlarmKit），这里只兜底清掉停止后残留的空白闹钟岛。
    static func sweep() {
        Task {
            let busy = await MainActor.run { Agent.shared.busy }
            for a in Activity<BotActivityAttributes>.activities {
                let stale = a.activityState == .stale || a.activityState == .ended
                // 没有任务在跑、也不是正在聆听，但岛上还停在「思考 / 执行」：是上一个进程留下的，收掉
                let orphan = !busy && a.content.state.phase != Phase.listening.rawValue
                if a.attributes.kind == "timer" || a.content.state.end != nil || stale && !busy || orphan {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
            await AlarmLive.sweep()
        }
    }
}
