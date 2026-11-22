import Foundation
import UIKit
import EventKit
import Contacts

// MARK: 动手工具（第二批）：让助理自己创建和管理定时任务、提醒事项、日程、联系人，并能直接打开系统设置去修权限。
// 删除、改期、写通讯录这类会改变用户数据的动作，先问用户；创建定时任务和查询不用问。
@MainActor
enum Hands2 {
    static func doc() -> String {
        var s = ""
        s += "- schedule_task {\"title\":\"标题\",\"instruction\":\"到点要做的事\",\"time\":\"yyyy-MM-dd'T'HH:mm\",\"repeat\":\"none|daily|weekly\",\"ai\":true}：创建定时任务。ai=true 表示到点前由助理先查资料、写好内容再通知（每天播报天气、新闻、日报）；false 只是准时通知\n"
        s += "- list_tasks {}：列出用户的定时任务和闹钟；cancel_task {\"id\":任务编号}：取消定时任务（先 list_tasks 拿编号）\n"
        s += "- reminders {\"action\":\"list|complete|delete\",\"q\":\"标题关键词\"}：查看、完成、删除系统提醒事项（删除会先问用户）\n"
        s += "- events {\"action\":\"find|delete|move\",\"q\":\"标题关键词\",\"days\":14,\"time\":\"yyyy-MM-dd'T'HH:mm\"}：在日历里找日程；delete 删除、move 改到 time 开始（保持时长），都会先问用户\n"
        s += "- contact_add {\"name\":\"姓名\",\"phone\":\"电话\",\"email\":\"邮箱\",\"org\":\"公司\"}：新建联系人（会先问用户）\n"
        s += "- date_calc {\"from\":\"yyyy-MM-dd 或 now\",\"days\":0,\"months\":0,\"weekday\":\"周三\",\"to\":\"yyyy-MM-dd\"}：日期推算，别心算。给 days/months 得到偏移后的日期和星期；给 weekday（周一…周日）得到 from 之后最近的那一天；给 to 得到两个日期相差的天数和周数\n"
        s += "- open_settings {}：打开本应用的系统设置页（权限被拒绝时，让用户去开启；先告诉用户要开哪一项）\n"
        return s
    }

    // 需要顺序执行的（会弹确认或改状态）名字，AgentTools.sequential 用
    nonisolated static let sequentialNames = ["schedule_task", "cancel_task", "reminders", "events", "contact_add", "open_settings"]

    static func run(_ c: ToolCall, trace: Tracer, cloud: Bool) async -> ToolResult? {
        let a = c.args
        switch c.name {
        case "schedule_task": return await scheduleTask(a, trace)
        case "list_tasks": return listTasks(trace)
        case "cancel_task": return cancelTask(a, trace)
        case "reminders": return await reminders(a, trace)
        case "events": return await events(a, trace)
        case "contact_add": return await contactAdd(a, trace)
        case "open_settings": return await openSettings(trace)
        case "date_calc": return dateCalc(a, trace)
        default: return nil
        }
    }

    // MARK: 小工具
    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func shown(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    // MARK: 日期推算
    private static func dateCalc(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        func parse(_ s: String) -> Date? {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.lowercased() == "now" || t == "今天" { return cal.startOfDay(for: Date()) }
            return f.date(from: String(t.prefix(10))).map { cal.startOfDay(for: $0) }
        }
        func show(_ d: Date) -> String {
            let w = DateFormatter()
            w.locale = Locale(identifier: "zh_CN")
            w.dateFormat = "yyyy年M月d日 EEEE"
            return w.string(from: d) + "（" + f.string(from: d) + "）"
        }
        guard let from = parse(str(a, "from")) else { return ToolResult(text: "from 的格式不对，用 yyyy-MM-dd 或 now。", ok: false) }
        trace.note(.time, "日期推算", str(a, "from").isEmpty ? "今天" : str(a, "from"))
        if !str(a, "to").isEmpty {
            guard let to = parse(str(a, "to")) else { return ToolResult(text: "to 的格式不对，用 yyyy-MM-dd。", ok: false) }
            let d = cal.dateComponents([.day], from: from, to: to).day ?? 0
            return ToolResult(text: "从 \(show(from)) 到 \(show(to))：相差 \(abs(d)) 天（约 \(String(format: "%.1f", Double(abs(d)) / 7)) 周），\(d >= 0 ? "后者在后" : "后者在前")。")
        }
        if !str(a, "weekday").isEmpty {
            let names = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7,
                         "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            let w = str(a, "weekday").lowercased()
            guard let target = names.first(where: { w.hasSuffix($0.key) || w.hasPrefix($0.key) })?.value else {
                return ToolResult(text: "weekday 请写 周一…周日。", ok: false)
            }
            let cur = cal.component(.weekday, from: from)
            var add = (target - cur + 7) % 7
            if add == 0 { add = 7 }
            // “下周X”：本周的 X 已过或就是今天时才进入下一周；用户明确说“下周”时，调用方可再加 days:7
            let extra = min(max(((a["days"] as? NSNumber)?.intValue) ?? 0, -100_000), 100_000)
            let d = cal.date(byAdding: .day, value: add + extra, to: from) ?? from
            return ToolResult(text: "\(show(from)) 之后最近的\(str(a, "weekday"))是 \(show(d))。")
        }
        var d = from
        let months = min(max((a["months"] as? NSNumber)?.intValue ?? 0, -12_000), 12_000)
        let days = min(max((a["days"] as? NSNumber)?.intValue ?? 0, -400_000), 400_000)
        if months != 0 { d = cal.date(byAdding: .month, value: months, to: d) ?? d }
        if days != 0 { d = cal.date(byAdding: .day, value: days, to: d) ?? d }
        return ToolResult(text: "\(show(from)) \(months != 0 ? "加 \(months) 个月 " : "")\(days != 0 ? "加 \(days) 天 " : "")= \(show(d))。")
    }

    // MARK: 定时任务
    private static func scheduleTask(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let instr = str(a, "instruction").isEmpty ? str(a, "title") : str(a, "instruction")
        guard !instr.isEmpty else { return ToolResult(text: "需要说明到点要做什么。", ok: false) }
        guard let d = date(str(a, "time")) else { return ToolResult(text: "时间格式不对，请用 yyyy-MM-dd'T'HH:mm。", ok: false) }
        let rep: Int
        switch str(a, "repeat").lowercased() {
        case "daily", "每天": rep = 1
        case "weekly", "每周": rep = 7
        default: rep = 0
        }
        guard rep > 0 || d > Date() else { return ToolResult(text: "这个时间已经过了，换一个时间。", ok: false) }
        let ai = (a["ai"] as? Bool) ?? ((a["ai"] as? NSNumber)?.boolValue ?? true)
        let title = str(a, "title").isEmpty ? String(instr.prefix(14)) : String(str(a, "title").prefix(20))
        let id = Tasks.add(title, instr, d, useModel: ai, rep: rep)
        trace.note(.time, "创建定时任务", title)
        await Tasks.refresh()
        let when = (rep > 0 ? Sys.repText(rep) + " " : "") + Sys.friendly(d)
        return ToolResult(text: "定时任务已创建（编号 \(id)）：\(when)「\(title)」。" + (ai ? "到点前我会先准备好内容，再用通知送达。" : ""), final: true)
    }

    private static func listTasks(_ trace: Tracer) -> ToolResult {
        let tasks = Tasks.list().filter { $0.i("state") == 0 }
        let alarms = Tasks.alarms()
        trace.note(.time, "查看定时任务", L10n.f("{} 个任务，{} 个闹钟", "\(tasks.count)", "\(alarms.count)"))
        if tasks.isEmpty && alarms.isEmpty { return ToolResult(text: "现在没有定时任务和闹钟。") }
        var out = ""
        if !tasks.isEmpty {
            out += "定时任务：\n"
            for t in tasks.prefix(30) {
                let rep = t.i("rep") > 0 ? "（" + Sys.repText(t.i("rep")) + "）" : ""
                out += "- 编号 \(t.i("id"))：\(shown(Date(timeIntervalSince1970: t.d("due")))) \(t.s("title"))\(rep)\n"
            }
        }
        if !alarms.isEmpty {
            out += "闹钟：\n"
            for r in alarms.prefix(20) { out += "- \(shown(Date(timeIntervalSince1970: r.d("due")))) \(r.s("label"))\n" }
        }
        return ToolResult(text: out)
    }

    private static func cancelTask(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        guard let id = Int(str(a, "id")) else { return ToolResult(text: "需要任务编号，先用 list_tasks 查看。", ok: false) }
        guard let row = Tasks.list().first(where: { $0.i("id") == id }) else { return ToolResult(text: "没有编号 \(id) 的任务。", ok: false) }
        Tasks.remove(id)
        trace.note(.time, "取消定时任务", row.s("title"))
        return ToolResult(text: "已取消定时任务「\(row.s("title"))」。", final: true)
    }

    // MARK: 提醒事项
    private static func fetchReminders(_ store: EKEventStore) async -> [EKReminder] {
        let pred = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
            store.fetchReminders(matching: pred) { @Sendable r in c.resume(returning: r ?? []) }
        }
    }

    private static func reminders(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let action = str(a, "action").isEmpty ? "list" : str(a, "action").lowercased()
        let q = str(a, "q").lowercased()
        let sid = trace.begin(.time, "提醒事项", action == "list" ? "查看" : (action == "complete" ? "完成" : "删除"))
        let store = EKEventStore()
        guard let ok = try? await store.requestFullAccessToReminders(), ok else {
            trace.end(sid, ok: false, detail: L10n.tr("没有提醒事项权限"))
            return ToolResult(text: "没有提醒事项权限，可以用 open_settings 打开设置页让用户开启。", ok: false)
        }
        let todo = await fetchReminders(store).filter { !$0.isCompleted }
        let hits = q.isEmpty ? todo : todo.filter { ($0.title ?? "").lowercased().contains(q) }
        switch action {
        case "complete":
            guard let r = hits.first else {
                trace.end(sid, ok: false, detail: L10n.tr("没找到"))
                return ToolResult(text: "没有找到包含「\(q)」的未完成提醒。", ok: false)
            }
            r.isCompleted = true
            do { try store.save(r, commit: true) } catch {
                trace.end(sid, ok: false, detail: error.localizedDescription)
                return ToolResult(text: "标记完成失败：\(error.localizedDescription)", ok: false)
            }
            trace.end(sid, detail: r.title ?? "")
            return ToolResult(text: "已把提醒「\(r.title ?? "")」标为完成。", final: true)
        case "delete":
            guard let r = hits.first else {
                trace.end(sid, ok: false, detail: L10n.tr("没找到"))
                return ToolResult(text: "没有找到包含「\(q)」的未完成提醒。", ok: false)
            }
            guard await Agent.shared.requestConfirm(title: L10n.f("删除提醒事项：{}", r.title ?? ""), detail: L10n.tr("删除后无法恢复。")) else {
                trace.end(sid, ok: false, detail: L10n.tr("用户拒绝"))
                return ToolResult(text: "用户拒绝了删除，已取消。")
            }
            do { try store.remove(r, commit: true) } catch {
                trace.end(sid, ok: false, detail: error.localizedDescription)
                return ToolResult(text: "删除失败：\(error.localizedDescription)", ok: false)
            }
            trace.end(sid, detail: r.title ?? "")
            return ToolResult(text: "已删除提醒「\(r.title ?? "")」。", final: true)
        default:
            trace.end(sid, detail: L10n.f("{} 项未完成", "\(hits.count)"))
            if hits.isEmpty { return ToolResult(text: q.isEmpty ? "没有未完成的提醒事项。" : "没有包含「\(q)」的未完成提醒。") }
            let cal = Calendar.current
            let lines = hits.prefix(30).map { r -> String in
                let d = r.dueDateComponents.flatMap { cal.date(from: $0) }
                return "- " + (d.map { shown($0) + " " } ?? "") + (r.title ?? "")
            }
            return ToolResult(text: "未完成的提醒事项（\(hits.count) 项）：\n" + lines.joined(separator: "\n"))
        }
    }

    // MARK: 日历日程
    private static func events(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let action = str(a, "action").isEmpty ? "find" : str(a, "action").lowercased()
        let q = str(a, "q").lowercased()
        let days = min(max(Int(str(a, "days")) ?? 14, 1), 90)
        let sid = trace.begin(.time, "日历日程", action == "find" ? "查找" : (action == "delete" ? "删除" : "改期"))
        let store = EKEventStore()
        guard let ok = try? await store.requestFullAccessToEvents(), ok else {
            trace.end(sid, ok: false, detail: L10n.tr("没有日历权限"))
            return ToolResult(text: "没有日历权限，可以用 open_settings 打开设置页让用户开启。", ok: false)
        }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
        let end = cal.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
        let all = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
        let hits = q.isEmpty ? all : all.filter { ($0.title ?? "").lowercased().contains(q) }
        guard action == "delete" || action == "move" else {
            trace.end(sid, detail: L10n.f("{} 项", "\(hits.count)"))
            if hits.isEmpty { return ToolResult(text: "没有找到相关日程。") }
            return ToolResult(text: "日程（\(hits.count) 项）：\n" + hits.prefix(30).map { "- \(shown($0.startDate)) \($0.title ?? "")" }.joined(separator: "\n"))
        }
        guard let e = hits.first(where: { $0.endDate > Date() }) ?? hits.first else {
            trace.end(sid, ok: false, detail: L10n.tr("没找到"))
            return ToolResult(text: "没有找到包含「\(q)」的日程。", ok: false)
        }
        let name = e.title ?? ""
        if action == "delete" {
            guard await Agent.shared.requestConfirm(title: L10n.f("删除日程：{}", name), detail: shown(e.startDate)) else {
                trace.end(sid, ok: false, detail: L10n.tr("用户拒绝"))
                return ToolResult(text: "用户拒绝了删除，已取消。")
            }
            do { try store.remove(e, span: .thisEvent, commit: true) } catch {
                trace.end(sid, ok: false, detail: error.localizedDescription)
                return ToolResult(text: "删除失败：\(error.localizedDescription)", ok: false)
            }
            trace.end(sid, detail: name)
            return ToolResult(text: "已删除日程「\(name)」（\(shown(e.startDate))）。", final: true)
        }
        guard let to = date(str(a, "time")) else {
            trace.end(sid, ok: false, detail: L10n.tr("缺少新时间"))
            return ToolResult(text: "改期需要新的开始时间 time（yyyy-MM-dd'T'HH:mm）。", ok: false)
        }
        guard await Agent.shared.requestConfirm(title: L10n.f("把日程「{}」改到 {}", name, shown(to)), detail: L10n.f("原时间 {}", shown(e.startDate))) else {
            trace.end(sid, ok: false, detail: L10n.tr("用户拒绝"))
            return ToolResult(text: "用户拒绝了改期，已取消。")
        }
        let length = e.endDate.timeIntervalSince(e.startDate)
        let old = e.startDate ?? Date()
        e.startDate = to
        e.endDate = to.addingTimeInterval(max(length, 300))
        do { try store.save(e, span: .thisEvent, commit: true) } catch {
            trace.end(sid, ok: false, detail: error.localizedDescription)
            return ToolResult(text: "改期失败：\(error.localizedDescription)", ok: false)
        }
        trace.end(sid, detail: name)
        return ToolResult(text: "已把日程「\(name)」从 \(shown(old)) 改到 \(shown(to))。", final: true)
    }

    // MARK: 联系人
    private static func contactAdd(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let name = str(a, "name")
        guard !name.isEmpty else { return ToolResult(text: "需要联系人姓名。", ok: false) }
        let phone = str(a, "phone")
        let email = str(a, "email")
        let org = str(a, "org")
        guard await Agent.shared.requestConfirm(title: L10n.f("新建联系人：{}", name), detail: [phone, email, org].filter { !$0.isEmpty }.joined(separator: " · ")) else {
            return ToolResult(text: "用户拒绝了新建联系人，已取消。")
        }
        let sid = trace.begin(.phone, "新建联系人", name)
        let store = CNContactStore()
        do {
            if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined { _ = try await store.requestAccess(for: .contacts) }
            let st = CNContactStore.authorizationStatus(for: .contacts)
            guard st == .authorized else {
                trace.end(sid, ok: false, detail: L10n.tr("没有通讯录权限"))
                return ToolResult(text: "没有通讯录权限，可以用 open_settings 打开设置页让用户开启。", ok: false)
            }
            let c = CNMutableContact()
            c.givenName = name
            if !org.isEmpty { c.organizationName = org }
            if !phone.isEmpty { c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))] }
            if !email.isEmpty { c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)] }
            let req = CNSaveRequest()
            req.add(c, toContainerWithIdentifier: nil)
            try store.execute(req)
            trace.end(sid, detail: name)
            return ToolResult(text: "已新建联系人「\(name)」。", final: true)
        } catch {
            trace.end(sid, ok: false, detail: error.localizedDescription)
            return ToolResult(text: "新建联系人失败：\(error.localizedDescription)", ok: false)
        }
    }

    // MARK: 系统设置
    private static func openSettings(_ trace: Tracer) async -> ToolResult {
        guard let u = URL(string: UIApplication.openSettingsURLString) else { return ToolResult(text: "打不开设置。", ok: false) }
        trace.note(.phone, "打开系统设置", Brand.name)
        let ok = await UIApplication.shared.open(u)
        return ToolResult(text: ok ? "已打开 \(Brand.name) 的系统设置页，请用户在里面开启需要的权限。" : "没能打开设置页。", ok: ok)
    }
}
