import SwiftUI
import UIKit
import AlarmKit

// 系统「时钟」App 桥接。
// iOS 不提供任何公开接口让第三方 App 直接往「时钟」写闹钟，唯一的官方通道是「快捷指令」的「创建闹钟」动作。
// 做法：本 App 通过 x-callback 运行用户的快捷指令「TSTZ闹钟」，并把时间 HH:mm 作为输入传入；运行结果回调回本 App。
enum ClockBridge {
    static let onceName = "TSTZ闹钟"
    static let dailyName = "TSTZ每日闹钟"
    private static var ud: UserDefaults { .standard }

    // 0 自动：已连接时钟就写入时钟；1 只用内置闹钟
    static var mode: Int { ud.object(forKey: "alarmMode") as? Int ?? 0 }

    static func ready(daily: Bool) -> Bool { ud.bool(forKey: daily ? "clockDailyReady" : "clockOnceReady") }

    // 「时钟」里的闹钟只有时分、没有日期：一次性闹钟必须在 24 小时内才不会提前响；每天重复可直接写入
    static func supports(_ d: Date, _ rep: Int) -> Bool {
        if rep == 0 { return d.timeIntervalSinceNow > 0 && d.timeIntervalSinceNow < 24 * 3600 }
        return rep == 1
    }

    static func eligible(_ d: Date, _ rep: Int) -> Bool {
        mode != 1 && supports(d, rep) && ready(daily: rep == 1)
    }

    // 「连接时钟」的提示只显示前 2 次，避免每次设闹钟都啰嗦
    static func bumpHint() -> Bool {
        let n = ud.integer(forKey: "clockHintCount")
        if n >= 2 { return false }
        ud.set(n + 1, forKey: "clockHintCount")
        return true
    }

    static func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    // 打开快捷指令运行「创建闹钟」，结果经 osvia://clock 回到本 App
    @MainActor
    static func run(daily: Bool, at d: Date, alarmId: String, test: Bool) async -> Bool {
        let base = "osvia://clock?daily=\(daily ? 1 : 0)&test=\(test ? 1 : 0)&alarm=\(alarmId)&time=\(hhmm(d))"
        let name = daily ? dailyName : onceName
        let link = "shortcuts://x-callback-url/run-shortcut?name=\(enc(name))&input=text&text=\(enc(hhmm(d)))"
            + "&x-success=\(enc(base + "&ok=1"))&x-cancel=\(enc(base + "&ok=0&cancel=1"))&x-error=\(enc(base + "&ok=0"))"
        guard let url = URL(string: link) else { return false }
        return await UIApplication.shared.open(url)
    }

    // 快捷指令运行完回到本 App
    @MainActor
    static func callback(_ q: [String: String]) {
        let ok = q["ok"] == "1"
        let daily = q["daily"] == "1"
        let test = q["test"] == "1"
        let time = q["time"] ?? ""
        let kind = daily ? "每日" : "一次性"
        if ok {
            ud.set(true, forKey: daily ? "clockDailyReady" : "clockOnceReady")
            if test {
                let msg = "已写入系统「时钟」（\(kind)闹钟，\(time)）。请打开「时钟」App 确认出现了这条闹钟，确认后可以删除它。"
                ud.set("✅ " + msg, forKey: "clockLast")
                Agent.shared.post("assistant", msg)
            } else {
                if let id = q["alarm"], !id.isEmpty { Sys.dropBackup(id, note: "时钟") }
                Agent.shared.post("assistant", "已写入系统「时钟」：\(time)。内置备份闹钟已取消，不会重复响铃。")
            }
        } else {
            let cancelled = q["cancel"] == "1"
            if !cancelled { ud.set(false, forKey: daily ? "clockDailyReady" : "clockOnceReady") }
            let why = cancelled ? "你取消了运行" : "快捷指令「\(daily ? dailyName : onceName)」运行失败，可能名称不一致或还没创建"
            let tail = test ? "请按「系统时钟闹钟」页的步骤检查。" : "内置闹钟已保留，到点照样会响。请在「+」→「系统时钟闹钟」检查连接。"
            ud.set("⚠️ " + why, forKey: "clockLast")
            Agent.shared.post("assistant", "没能写入系统「时钟」：\(why)。\(tail)")
        }
    }
}

// 连接系统「时钟」的向导 + 内置闹钟自检
struct ClockSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alarmMode") private var mode = 0
    @AppStorage("clockOnceReady") private var onceReady = false
    @AppStorage("clockDailyReady") private var dailyReady = false
    @AppStorage("clockLast") private var last = ""
    @State private var diag = ""
    @State private var info = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("苹果不允许 App 直接往「时钟」里写闹钟，唯一的官方通道是「快捷指令」里的「创建闹钟」。按下面做一次，以后说一句话就会写进时钟。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("闹钟方式") {
                    Picker("闹钟方式", selection: $mode) {
                        Text("自动").tag(0)
                        Text("只用内置").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Text(mode == 0
                         ? "已连接时钟时写入「时钟」App；同时先登记一个内置闹钟作保底，写入成功后自动取消，不会重复响。"
                         : "只用内置闹钟：会响铃，静音和专注模式下也响，但不出现在「时钟」列表里。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                shortcutSection(daily: false)
                shortcutSection(daily: true)
                Section("内置闹钟自检") {
                    Text(diag).font(.subheadline)
                    Button {
                        Task {
                            info = await Sys.alarm(Date().addingTimeInterval(65), "测试闹钟", rep: 0, builtinOnly: true)
                            refresh()
                        }
                    } label: { Label("测试内置闹钟（约 1 分钟后响）", systemImage: "alarm") }
                    if !info.isEmpty { Text(info).font(.footnote).foregroundStyle(Color.accentColor) }
                }
                if !last.isEmpty {
                    Section("最近一次结果") { Text(last).font(.subheadline) }
                }
            }
            .navigationTitle("系统时钟闹钟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear(perform: refresh)
        }
    }

    @ViewBuilder
    func shortcutSection(daily: Bool) -> some View {
        let name = daily ? ClockBridge.dailyName : ClockBridge.onceName
        let ready = daily ? dailyReady : onceReady
        Section {
            Label(ready ? "已连接" : "未连接", systemImage: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
            Text(daily
                 ? "做法同上，名称改成「TSTZ每日闹钟」，并在「创建闹钟」里把重复选成每天（周日到周六全选）。"
                 : "1. 点「新建快捷指令」，再点「添加操作」，搜索「创建闹钟」并选中\n2. 点其中的「时间」，选「快捷指令输入」\n3. 把名称改成「TSTZ闹钟」（先点下面的复制），点完成\n4. 回到这里点「测试」")
                .font(.subheadline)
            Button {
                UIPasteboard.general.string = name
                info = "已复制名称「\(name)」"
            } label: { Label("复制快捷指令名称", systemImage: "doc.on.doc") }
            Button {
                if let u = URL(string: "shortcuts://create-shortcut") { UIApplication.shared.open(u) }
            } label: { Label("新建快捷指令", systemImage: "plus.square") }
            Button {
                Task { _ = await ClockBridge.run(daily: daily, at: Date().addingTimeInterval(150), alarmId: "", test: true) }
            } label: { Label("测试（写入一个约 2 分钟后的闹钟）", systemImage: "play.circle") }
        } header: {
            Text(daily ? "每日闹钟（「每天早上七点叫我起床」）" : "一次性闹钟（「明早七点叫我起床」）")
        }
    }

    func refresh() {
        diag = "闹钟权限：\(Sys.alarmAuth())；系统已登记 \(Sys.systemAlarmCount()) 个内置闹钟"
    }
}
