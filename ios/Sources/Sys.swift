import Foundation
import AlarmKit
import EventKit
import UserNotifications
import SwiftUI


enum Sys {
    static let store = EKEventStore()

    static func date(_ off: Int, _ h: Int, _ m: Int) -> Date? {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: off, to: cal.startOfDay(for: Date())) else { return nil }
        return cal.date(bySettingHour: min(max(h, 0), 23), minute: min(max(m, 0), 59), second: 0, of: day)
    }

    // 日期格式跟随应用当前语言（简繁中文保持原来的写法，其他语言用系统的本地化模板）
    private static var chineseDates: Bool { L10n.code == "zh-Hans" || L10n.code == "zh-Hant" }

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        if chineseDates { f.dateFormat = "M月d日 EEEE HH:mm" } else { f.setLocalizedDateFormatFromTemplate("MMMd EEEE jm") }
        return f.string(from: d)
    }

    static func fmtFull(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        if chineseDates { f.dateFormat = "yyyy年M月d日 EEEE HH:mm" } else { f.setLocalizedDateFormatFromTemplate("yMMMd EEEE jm") }
        return f.string(from: d)
    }

    // 今天 / 明天 / 后天 / 日期 + 时间
    static func friendly(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 99
        let t = DateFormatter()
        t.dateFormat = "HH:mm"
        let time = t.string(from: d)
        switch days {
        case 0: return L10n.tr("今天") + " \(time)"
        case 1: return L10n.tr("明天") + " \(time)"
        case 2: return L10n.tr("后天") + " \(time)"
        default:
            let f = DateFormatter()
            f.locale = L10n.locale
            if chineseDates { f.dateFormat = "M月d日 EEE" } else { f.setLocalizedDateFormatFromTemplate("MMMd EEE") }
            return "\(f.string(from: d)) \(time)"
        }
    }

    static func repText(_ rep: Int) -> String { rep == 1 ? L10n.tr("每天") : rep == 7 ? L10n.tr("每周") : "" }

    static func ensureNotif() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // rep：0 一次，1 每天，7 每周。通知的标题和正文按应用当前语言翻译（用户自己写的内容原样保留）
    static func notify(id: String, title: String, body: String, at d: Date, rep: Int = 0, sound: Bool = true) {
        let c = UNMutableNotificationContent()
        c.title = L10n.tr(title)
        c.body = L10n.tr(body)
        if sound { c.sound = .default }
        let cal = Calendar.current
        let comps: DateComponents
        switch rep {
        case 1: comps = cal.dateComponents([.hour, .minute], from: d)
        case 7: comps = cal.dateComponents([.weekday, .hour, .minute], from: d)
        default: comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        }
        let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: rep > 0)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trig))
    }

    static func weekdays(_ rep: Int, _ d: Date) -> [Locale.Weekday] {
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        if rep == 1 { return all }
        let w = Calendar.current.component(.weekday, from: d)
        return [all[min(max(w - 1, 0), 6)]]
    }

    static func systemAlarmCount() -> Int { (try? AlarmManager.shared.alarms)?.count ?? 0 }

    static func alarmAuth() -> String {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return "已允许"
        case .denied: return "已拒绝（请到 设置 → \(Brand.name) 开启闹钟）"
        default: return "还没询问"
        }
    }

    // 闹钟分两层：① 内置闹钟（AlarmKit，真正响铃，静音与专注模式下也响，但不在「时钟」列表里）
    // ② 系统「时钟」写入（经快捷指令「创建闹钟」，需连接一次）。② 成功后自动取消 ① 的备份，避免重复响。
    // 返回的是中文确定性回复，显示前由 Agent 按当前语言逐句翻译。
    static func alarm(_ d: Date, _ label: String, rep: Int = 0, builtinOnly: Bool = false) async -> String {
        guard rep > 0 || d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        await ensureNotif()
        let title = label.isEmpty ? "闹钟" : label
        let when = (rep > 0 ? repText(rep) + " " : "") + friendly(d)
        let id = UUID()
        var kitOK = false
        var kitErr = ""
        do {
            let mgr = AlarmManager.shared
            if mgr.authorizationState == .notDetermined { _ = try await mgr.requestAuthorization() }
            if mgr.authorizationState == .authorized {
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: L10n.tr(title)),
                    stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: L10n.tr("停止")), textColor: .white, systemImageName: "stop.fill")
                )
                let attrs = AlarmAttributes<NoMeta>(presentation: AlarmPresentation(alert: alert), tintColor: .green)
                let schedule: Alarm.Schedule
                if rep > 0 {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    schedule = .relative(Alarm.Schedule.Relative(
                        time: Alarm.Schedule.Relative.Time(hour: c.hour ?? 8, minute: c.minute ?? 0),
                        repeats: .weekly(weekdays(rep, d))
                    ))
                } else {
                    schedule = .fixed(d)
                }
                let cfg = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attrs)
                _ = try await mgr.schedule(id: id, configuration: cfg)
                // 回查：确认系统真的登记了这个闹钟
                kitOK = ((try? mgr.alarms) ?? []).contains { $0.id == id }
                if !kitOK { kitErr = "系统没有登记这个闹钟" }
            } else {
                kitErr = "没有闹钟权限，请到 设置 → \(Brand.name) 里允许闹钟"
            }
        } catch {
            kitErr = error.localizedDescription
        }
        DB.shared.run("INSERT OR REPLACE INTO alarm(id,label,due,rep) VALUES(?,?,?,?)",
                      [id.uuidString, kitOK ? title : title + "（仅通知）", d.timeIntervalSince1970, rep])
        // 通知保底：内置闹钟成功时无声（只在锁屏留痕）；失败时带声音，但它只是通知
        notify(id: "alarm-\(id.uuidString)", title: "闹钟", body: title, at: d, rep: rep, sound: !kitOK)

        var clockStarted = false
        if !builtinOnly && ClockBridge.eligible(d, rep) {
            clockStarted = await ClockBridge.run(daily: rep == 1, at: d, alarmId: id.uuidString, test: false)
        }

        if kitOK {
            var s = "闹钟已设置：\(when)「\(title)」。到点会像系统闹钟一样响铃，静音和专注模式下也会响。"
            if clockStarted {
                s += "正在写入系统「时钟」，完成后会提示。"
            } else if !builtinOnly && ClockBridge.mode != 1 && ClockBridge.supports(d, rep) && !ClockBridge.ready(daily: rep == 1) && ClockBridge.bumpHint() {
                s += "它不在「时钟」App 的列表里；点输入框左边「+」→「系统时钟闹钟」连接一次，以后就会写进时钟。"
            }
            return s
        }
        if clockStarted {
            return "闹钟已设置：\(when)「\(title)」。内置闹钟不可用（\(kitErr)），已改为写入系统「时钟」，完成后会提示。"
        }
        return "闹钟没能设置成响铃：\(kitErr)。已先用通知提醒你，到点只会弹通知、不会响铃。"
    }

    // 倒计时：交给系统（AlarmKit 的计时器）。灵动岛和锁屏的倒计时由系统管理，结束或取消后自己收起，不会残留。
    // 没有闹钟权限时返回空，调用方改用普通闹钟。
    static func timer(_ secs: TimeInterval, _ label: String) async -> String? {
        let title = label.isEmpty ? "倒计时" : label
        do {
            let mgr = AlarmManager.shared
            if mgr.authorizationState == .notDetermined { _ = try await mgr.requestAuthorization() }
            guard mgr.authorizationState == .authorized else { return nil }
            await ensureNotif()
            let id = UUID()
            func res(_ s: String) -> LocalizedStringResource { LocalizedStringResource(stringLiteral: L10n.tr(s)) }
            let alert = AlarmPresentation.Alert(title: res(title), stopButton: AlarmButton(text: res("停止"), textColor: .white, systemImageName: "stop.fill"))
            let countdown = AlarmPresentation.Countdown(title: res(title), pauseButton: AlarmButton(text: res("暂停"), textColor: .white, systemImageName: "pause.fill"))
            let paused = AlarmPresentation.Paused(title: res("已暂停"), resumeButton: AlarmButton(text: res("继续"), textColor: .white, systemImageName: "play.fill"))
            let attrs = AlarmAttributes<NoMeta>(presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
                                                metadata: NoMeta(kind: "timer"), tintColor: Color(red: 0, green: 0.9, blue: 0.66))
            _ = try await mgr.schedule(id: id, configuration: AlarmManager.AlarmConfiguration.timer(duration: secs, attributes: attrs))
            guard ((try? mgr.alarms) ?? []).contains(where: { $0.id == id }) else { return nil }
            let d = Date().addingTimeInterval(secs)
            DB.shared.run("INSERT OR REPLACE INTO alarm(id,label,due,rep) VALUES(?,?,?,?)", [id.uuidString, title, d.timeIntervalSince1970, 0])
            notify(id: "alarm-\(id.uuidString)", title: "闹钟", body: title, at: d, rep: 0, sound: false)
            return "倒计时已设置：\(friendly(d))「\(title)」。灵动岛和锁屏会显示倒计时（可暂停、取消），到点像系统计时器一样响铃，静音和专注模式下也会响。"
        } catch {
            return nil
        }
    }

    // 90 分钟内的一次性闹钟按倒计时处理（灵动岛有倒计时、到点系统收起）；更远的或重复闹钟走普通闹钟
    static func alarmSmart(_ d: Date, _ label: String, rep: Int = 0) async -> String {
        let secs = d.timeIntervalSinceNow
        if rep == 0, secs >= 5, secs <= 90 * 60, let r = await timer(secs, label) { return r }
        return await alarm(d, label, rep: rep)
    }

    // 写入「时钟」成功后，取消内置备份，避免同一时间响两次
    static func dropBackup(_ id: String, note: String) {
        if let u = UUID(uuidString: id) {
            try? AlarmManager.shared.cancel(id: u)
            Task { await AlarmLive.end(u) }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-\(id)"])
        DB.shared.run("UPDATE alarm SET label=label||? WHERE id=?", ["（已写入\(note)）", id])
    }

    static func cancelAlarm(_ id: String) {
        if let u = UUID(uuidString: id) {
            try? AlarmManager.shared.cancel(id: u)
            Task { await AlarmLive.end(u) }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-\(id)"])
        DB.shared.run("DELETE FROM alarm WHERE id=?", [id])
    }

    static func reminder(_ title: String, _ d: Date, rep: Int = 0, notes: String = "", freq: String = "") async -> String {
        let longRep = freq == "monthly" || freq == "yearly"
        guard rep > 0 || longRep || d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        var inReminders = false
        do {
            if try await store.requestFullAccessToReminders() {
                let r = EKReminder(eventStore: store)
                r.title = title
                r.notes = notes
                r.calendar = store.defaultCalendarForNewReminders()
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                r.addAlarm(EKAlarm(absoluteDate: d))
                if longRep {
                    r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: freq == "monthly" ? .monthly : .yearly, interval: 1, end: nil))
                } else if rep > 0 {
                    r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: rep == 1 ? .daily : .weekly, interval: 1, end: nil))
                }
                try store.save(r, commit: true)
                inReminders = true
            }
        } catch {}
        // 已写入系统提醒事项时由它负责提醒，不再重复发通知
        if !inReminders { Sys.notify(id: "remind-\(UUID().uuidString)", title: "提醒", body: title, at: d, rep: rep) }
        let repShown = longRep ? (freq == "monthly" ? L10n.tr("每月") : L10n.tr("每年")) + " " : (rep > 0 ? repText(rep) + " " : "")
        return "提醒已设置：\(repShown)\(friendly(d))「\(title)」" + (inReminders ? "，已写入系统提醒事项。" : "，将以通知提醒你。")
    }

    // 时长、地点、备注、重复、提前提醒、全天都可选；保存前先查有没有时间冲突，写进回复里
    static func event(_ title: String, _ d: Date, minutes: Int = 60, location: String = "", notes: String = "",
                      freq: String = "", alert: Int = 10, allDay: Bool = false) async -> String {
        let cal = Calendar.current
        guard allDay ? d >= cal.startOfDay(for: Date()) : d > Date() else { return "这个时间已经过了，换一个时间试试。" }
        do {
            guard try await store.requestFullAccessToEvents() else { return "没有日历权限，请到 设置 → \(Brand.name) 里允许日历。" }
            let e = EKEvent(eventStore: store)
            e.title = title
            let mins = min(max(minutes, 5), 24 * 60)
            if allDay {
                e.isAllDay = true
                e.startDate = cal.startOfDay(for: d)
                e.endDate = cal.startOfDay(for: d)
            } else {
                e.startDate = d
                e.endDate = d.addingTimeInterval(Double(mins) * 60)
            }
            if !location.isEmpty { e.location = location }
            if !notes.isEmpty { e.notes = notes }
            e.calendar = store.defaultCalendarForNewEvents
            if alert >= 0 { e.addAlarm(EKAlarm(relativeOffset: -Double(min(alert, 7 * 24 * 60)) * 60)) }
            var repShown = ""
            let rule: EKRecurrenceFrequency?
            switch freq {
            case "daily": rule = .daily; repShown = L10n.tr("每天")
            case "weekly": rule = .weekly; repShown = L10n.tr("每周")
            case "monthly": rule = .monthly; repShown = L10n.tr("每月")
            case "yearly": rule = .yearly; repShown = L10n.tr("每年")
            default: rule = nil
            }
            if let rule { e.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: rule, interval: 1, end: nil)) }
            // 冲突：同一时间段里已有的非全天日程
            var clash: [String] = []
            if !allDay {
                let pred = store.predicateForEvents(withStart: e.startDate, end: e.endDate, calendars: nil)
                clash = store.events(matching: pred).filter { !$0.isAllDay }.prefix(3).compactMap { $0.title }
            }
            try store.save(e, span: rule == nil ? .thisEvent : .futureEvents)
            var out = "日程已添加：" + (repShown.isEmpty ? "" : repShown + " ") + (allDay ? friendly(d).replacingOccurrences(of: " 00:00", with: "") : friendly(d)) + "「\(title)」"
            out += allDay ? "（全天）" : "（\(mins) 分钟）"
            if !location.isEmpty { out += "，地点 \(location)" }
            out += alert >= 0 ? (alert == 0 ? "，开始时提醒。" : "，提前 \(alert) 分钟提醒。") : "。"
            if !clash.isEmpty { out += " 注意：这个时间段已有日程「" + clash.joined(separator: "」「") + "」，可能冲突。" }
            return out
        } catch {
            return "日程添加失败：\(error.localizedDescription)"
        }
    }
}
