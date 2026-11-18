import ActivityKit
import AlarmKit
import AppIntents
import Foundation

// 系统闹钟（AlarmKit）的附带信息。应用和灵动岛扩展共用同一个类型，所以放在 Shared。
// 所有字段可选：以前用空结构登记的闹钟（JSON 是 {}）仍然能解码。
struct NoMeta: AlarmMetadata {
    var kind: String?
}

// 系统偶尔会在闹钟停止后留下空白的灵动岛条（Apple 论坛 FB22295664）。
// 按官方工程师的建议：闹钟停止 / 取消后显式结束对应的实时活动；启动和回到前台时再兜底清一遍。
enum AlarmLive {
    // 结束指定闹钟的实时活动
    static func end(_ id: UUID) async {
        for a in Activity<AlarmAttributes<NoMeta>>.activities where a.content.state.alarmID == id {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    // 兜底：没有对应闹钟、或闹钟已回到「待响」状态的活动一律结束
    static func sweep() async {
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        for a in Activity<AlarmAttributes<NoMeta>>.activities {
            let id = a.content.state.alarmID
            let running = alarms.first(where: { $0.id == id }).map { $0.state != .scheduled } ?? false
            if !running { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// 灵动岛 / 锁屏上倒计时的按钮：暂停、继续、取消。在应用进程里执行。
struct AlarmPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停"
    @Parameter(title: "id") var alarmID: String
    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult {
        if let u = UUID(uuidString: alarmID) { try? AlarmManager.shared.pause(id: u) }
        return .result()
    }
}

struct AlarmResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续"
    @Parameter(title: "id") var alarmID: String
    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult {
        if let u = UUID(uuidString: alarmID) { try? AlarmManager.shared.resume(id: u) }
        return .result()
    }
}

struct AlarmStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止"
    @Parameter(title: "id") var alarmID: String
    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult {
        if let u = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: u)
            await AlarmLive.end(u)
        }
        return .result()
    }
}
