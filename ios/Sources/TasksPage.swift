import SwiftUI
import AlarmKit
import UserNotifications

extension Tasks {
    // state：0 开启，1 已完成，2 已关闭
    static func setEnabled(_ id: Int, _ on: Bool) async {
        if on {
            DB.shared.run("UPDATE task SET state=0, notified=0 WHERE id=?", [id])
            _ = await refresh()
        } else {
            DB.shared.run("UPDATE task SET state=2 WHERE id=?", [id])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["task-\(id)"])
        }
    }
}

extension Sys {
    static func alarmOn(_ id: String) -> Bool { DB.shared.kv("alarmoff." + id) != "1" }

    static func plainLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "（[^）]*）$", with: "", options: .regularExpression)
    }

    // 开关内置闹钟：关 = 取消系统里的闹钟与通知（保留记录）；开 = 用同一个编号重新登记。返回空字符串表示成功
    static func setAlarmEnabled(_ id: String, _ on: Bool) async -> String {
        guard let r = DB.shared.rows("SELECT * FROM alarm WHERE id=?", [id]).first, let u = UUID(uuidString: id) else { return "" }
        if !on {
            try? AlarmManager.shared.cancel(id: u)
            await AlarmLive.end(u)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["alarm-\(id)"])
            DB.shared.setKV("alarmoff." + id, "1")
            return ""
        }
        let due = Date(timeIntervalSince1970: r.d("due"))
        let rep = r.i("rep")
        let title = plainLabel(r.s("label"))
        if rep == 0 && due <= Date() { return "这个闹钟的时间已经过了，请重新创建一个。" }
        await ensureNotif()
        do {
            let mgr = AlarmManager.shared
            if mgr.authorizationState == .notDetermined { _ = try await mgr.requestAuthorization() }
            guard mgr.authorizationState == .authorized else { return "没有闹钟权限，请到 设置 → TSTZ Bot 里允许闹钟。" }
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title.isEmpty ? "闹钟" : title),
                stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
            )
            let attrs = AlarmAttributes<NoMeta>(presentation: AlarmPresentation(alert: alert), tintColor: .green)
            let schedule: Alarm.Schedule
            if rep > 0 {
                let c = Calendar.current.dateComponents([.hour, .minute], from: due)
                schedule = .relative(Alarm.Schedule.Relative(
                    time: Alarm.Schedule.Relative.Time(hour: c.hour ?? 8, minute: c.minute ?? 0),
                    repeats: .weekly(weekdays(rep, due))
                ))
            } else {
                schedule = .fixed(due)
            }
            let cfg = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attrs)
            _ = try await mgr.schedule(id: u, configuration: cfg)
            DB.shared.run("DELETE FROM kv WHERE k=?", ["alarmoff." + id])
            notify(id: "alarm-\(id)", title: "闹钟", body: title, at: due, rep: rep, sound: false)
            return ""
        } catch {
            return "重新开启失败：\(error.localizedDescription)"
        }
    }
}

// MARK: 任务：每个闹钟、定时任务都有简介和开关
struct TasksView: View {
    @State private var tasks: [Row] = []
    @State private var alarms: [Row] = []
    @State private var text = ""
    @State private var info = ""
    @State private var busy = false
    @State private var note = ""
    @State private var preparing = false
    @State private var prepInfo = ""

    private var alarmOnCount: Int {
        alarms.filter { Sys.alarmOn($0.s("id")) && !($0.i("rep") == 0 && $0.d("due") < Date().timeIntervalSince1970) }.count
    }

    private var taskOnCount: Int { tasks.filter { $0.i("state") == 0 }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("闹钟和定时任务都在这里。右侧开关随时开启或关闭，关闭后不再响铃或提醒，记录会保留。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
                Section("新建") {
                    TextField("例：明早十点叫我起床", text: $text, axis: .vertical).lineLimit(1...3)
                    Button { create() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() }
                            Text(busy ? "创建中…" : "创建").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.clear)
                    if !info.isEmpty { Text(info).foregroundStyle(Brand.ink) }
                }
                Section {
                    if alarms.isEmpty { Text("没有闹钟").foregroundStyle(Brand.sub) }
                    ForEach(Array(alarms.enumerated()), id: \.offset) { i, elem in alarmRow(elem) }
                        .onDelete { idx in
                            for i in idx { Sys.cancelAlarm(alarms[i].s("id")) }
                            reload()
                        }
                } header: {
                    Text("闹钟 · \(alarmOnCount)/\(alarms.count) 个开启")
                }
                Section {
                    if tasks.isEmpty { Text("没有定时任务").foregroundStyle(Brand.sub) }
                    ForEach(Array(tasks.enumerated()), id: \.offset) { i, elem in taskRow(elem) }
                        .onDelete { idx in
                            for i in idx { Tasks.remove(tasks[i].i("id")) }
                            reload()
                        }
                    Button {
                        preparing = true
                        prepInfo = ""
                        Task {
                            let n = await Tasks.refresh()
                            prepInfo = n > 0 ? "已为 \(n) 个任务准备好内容并安排了通知" : "没有需要准备的任务"
                            preparing = false
                            reload()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if preparing { ProgressView() }
                            Text(preparing ? "正在准备…" : "立即准备并安排通知")
                        }
                    }
                    .disabled(preparing)
                    if !prepInfo.isEmpty { Text(prepInfo).foregroundStyle(Brand.ink) }
                } header: {
                    Text("定时任务 · \(taskOnCount)/\(tasks.count) 个开启")
                }
                if !note.isEmpty {
                    Section { Text(note).font(.subheadline).foregroundStyle(Brand.ink) }
                }
                Section("进化") {
                    NavigationLink("进化与记忆") { EvolvePage() }
                }
            }
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
            .onAppear(perform: reload)
        }
    }

    func alarmRow(_ r: Row) -> some View {
        let id = r.s("id")
        let rep = r.i("rep")
        let due = Date(timeIntervalSince1970: r.d("due"))
        let expired = rep == 0 && due < Date()
        let inClock = r.s("label").contains("已写入时钟")
        let on = Sys.alarmOn(id) && !expired
        let when = (rep > 0 ? Sys.repText(rep) + " " : "") + Sys.friendly(due)
        let intro = inClock ? "已写入系统「时钟」，请在「时钟」App 里开关" : (expired ? "已响过" : "内置闹钟：到点响铃，静音和专注模式下也会响")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: on ? "alarm.fill" : "alarm").foregroundStyle(on ? Brand.ink : Brand.sub).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(Sys.plainLabel(r.s("label"))).font(.headline)
                Text(when).font(.subheadline).foregroundStyle(Brand.sub)
                Text(intro).font(.footnote).foregroundStyle(Brand.sub)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { on }, set: { v in
                Task {
                    note = await Sys.setAlarmEnabled(id, v)
                    reload()
                }
            }))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .disabled(expired || inClock)
        }
        .padding(.vertical, 3)
    }

    func taskRow(_ r: Row) -> some View {
        let id = r.i("id")
        let state = r.i("state")
        let rep = r.i("rep")
        let due = Date(timeIntervalSince1970: r.d("due"))
        let useModel = r.i("use_model") == 1
        let status = state == 1 ? "已完成" : (state == 2 ? "已关闭" : "已开启")
        let when = (rep > 0 ? Sys.repText(rep) + " " : "") + Sys.friendly(due)
        let what = String(r.s("instr").prefix(40))
        let how = useModel ? "提前由本机模型准备内容，到点通知送达" : "到点发送通知提醒"
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: state == 0 ? "checklist" : "checklist.unchecked").foregroundStyle(state == 0 ? Brand.ink : Brand.sub).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.s("title")).font(.headline)
                Text(when + " · " + status).font(.subheadline).foregroundStyle(Brand.sub)
                if !what.isEmpty { Text("内容：" + what).font(.footnote).foregroundStyle(Brand.sub) }
                Text(how).font(.footnote).foregroundStyle(Brand.sub)
                if !r.s("result").isEmpty { Text("已准备：" + String(r.s("result").prefix(80))).font(.footnote).foregroundStyle(Brand.ink) }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { state == 0 }, set: { v in
                Task {
                    await Tasks.setEnabled(id, v)
                    reload()
                }
            }))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .disabled(state == 1)
        }
        .padding(.vertical, 3)
    }

    func create() {
        let t = text
        hideKeyboard()
        busy = true
        info = ""
        Task {
            let r = await Router.handle(t)
            info = r ?? "没能识别时间，请说得具体一些，比如「明早十点叫我起床」"
            if r != nil { text = "" }
            busy = false
            reload()
        }
    }

    func reload() {
        tasks = Tasks.list()
        alarms = Tasks.alarms()
    }
}

// MARK: 进化
struct EvolvePage: View {
    @State private var log: [Row] = []
    @State private var vers: [Row] = []
    @State private var busy = false
    @State private var info = ""
    @State private var profile = Evolve.profile()

    var body: some View {
        List {
            Section {
                Text("助理会从对话里提炼你的长期偏好并存进知识库；对话足够多时，还会谨慎改进自己的系统提示（可随时回滚）。聊几轮后自动进行，也可以手动触发。")
                    .font(.subheadline).foregroundStyle(Brand.sub)
                Text("上次进化：" + (Evolve.lastTime().map { Sys.friendly($0) } ?? "尚未进行")).foregroundStyle(Brand.sub)
                Button {
                    busy = true
                    info = ""
                    Task {
                        info = await Evolve.run(force: true)
                        busy = false
                        reload()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(busy ? "正在进化…" : "立即进化")
                    }
                }
                .disabled(busy)
                if !info.isEmpty { Text(info).foregroundStyle(Brand.ink) }
            }
            if !profile.isEmpty {
                Section {
                    Text(verbatim: profile).font(.subheadline).foregroundStyle(Brand.ink)
                } header: { Text("助理眼中的你") } footer: { Text("由你的记忆自动总结，每次对话都会带上。") }
            }
            Section("每次进化都做了什么") {
                if log.isEmpty { Text("还没有进化记录。多聊几轮会自动进化，也可以点上面的「立即进化」。").foregroundStyle(Brand.sub) }
                ForEach(Array(log.enumerated()), id: \.offset) { i, elem in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Sys.fmt(Date(timeIntervalSince1970: elem.d("ts")))).font(.subheadline).foregroundStyle(Brand.sub)
                        Text(elem.s("summary")).font(.headline)
                        if !elem.s("facts").isEmpty {
                            ForEach(elem.s("facts").split(separator: "\n").map(String.init), id: \.self) { f in
                                Label(f, systemImage: "leaf").font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("系统提示版本") {
                ForEach(Array(vers.enumerated()), id: \.offset) { i, elem in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(elem.i("ver")) 版" + (i == 0 ? "（当前）" : "")).font(.headline)
                        Text(elem.s("body")).font(.subheadline).foregroundStyle(Brand.sub)
                        if i > 0 {
                            Button("回滚到这一版") {
                                Evolve.saveVersion(elem.s("body"))
                                reload()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if vers.isEmpty { Text("当前使用默认提示").foregroundStyle(Brand.sub) }
            }
        }
        .navigationTitle("进化")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    func reload() {
        log = Evolve.log()
        vers = Evolve.versions()
        profile = Evolve.profile()
    }
}

// 从侧栏打开的进化页
struct EvolveHome: View {
    var body: some View {
        NavigationStack { EvolvePage() }
    }
}
