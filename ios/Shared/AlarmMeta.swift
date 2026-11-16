import AlarmKit
import AppIntents
import Foundation

// 系统闹钟（AlarmKit）的附带信息。应用和灵动岛扩展共用同一个类型，所以放在 Shared。
// 所有字段可选：以前用空结构登记的闹钟（JSON 是 {}）仍然能解码。
struct NoMeta: AlarmMetadata {
    var kind: String?
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
        if let u = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: u) }
        return .result()
    }
}
