import SwiftUI
import MetricKit
import Darwin

// 崩溃现场：Swift 运行时陷阱（SIGTRAP）等信号发生时，把调用栈（含函数名）直接写进文件。
// 信号处理函数里只做最基本的写文件，写完恢复默认处理并重新抛出，让系统照常生成崩溃报告。
private var crashFD: Int32 = -1
private let crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 64)

private func crashHandler(_ sig: Int32) {
    if crashFD >= 0 {
        var head: [UInt8] = Array("\n=== SIGNAL ".utf8)
        head.append(UInt8(48 + (sig / 10) % 10))
        head.append(UInt8(48 + sig % 10))
        head.append(10)
        _ = head.withUnsafeBufferPointer { write(crashFD, $0.baseAddress, $0.count) }
        let n = backtrace(crashFrames, 64)
        backtrace_symbols_fd(crashFrames, n, crashFD)
        fsync(crashFD)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

// MARK: 诊断：记录关键步骤（崩溃后能看到最后做了什么）+ 接收系统的崩溃报告（MetricKit，次日送达）
enum Diag {
    private static let queue = DispatchQueue(label: "osvia.diag")
    private static var fileURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent("diag.log")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    // 记一条。直接追加到文件，进程崩溃了也已经落盘
    static func mark(_ s: String) {
        let line = stamp.string(from: Date()) + " " + s + "\n"
        queue.async {
            let u = fileURL
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: u)
            }
        }
    }

    static func tail(_ n: Int = 40) -> String {
        queue.sync {
            guard let t = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
            return t.split(separator: "\n").suffix(n).joined(separator: "\n")
        }
    }

    // 上一次是不是在前台异常结束（崩溃或被系统杀掉）：启动时看标记
    private static let activeKey = "diag.active"
    static var lastAbnormal: String { UserDefaults.standard.string(forKey: "diag.abnormal") ?? "" }

    private static var traceURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("crash-trace.txt")
    }

    // 上一次崩溃留下的调用栈（没有就是空串）
    static func trace() -> String {
        guard let t = try? String(contentsOf: traceURL, encoding: .utf8) else { return "" }
        return String(t.suffix(6000))
    }

    private static func installCrashHandler() {
        let u = traceURL
        // 保留上一次的现场，满 20KB 就重新开始
        if let a = try? FileManager.default.attributesOfItem(atPath: u.path), (a[.size] as? Int ?? 0) > 20_000 { try? FileManager.default.removeItem(at: u) }
        crashFD = open(u.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        for s in [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] { signal(s, crashHandler) }
    }

    static func launch() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: activeKey) {
            let t = tail(14)
            ud.set(stamp.string(from: Date()) + " 上次在前台异常结束，最后的记录：\n" + t, forKey: "diag.abnormal")
        }
        installCrashHandler()
        ud.set(false, forKey: activeKey)
        trimLog()
        mark("—— 启动 v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))
        MXMetricManager.shared.add(Subscriber.shared)
    }

    static func phase(active: Bool) {
        UserDefaults.standard.set(active, forKey: activeKey)
        mark(active ? "回到前台" : "进入后台")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: "diag.abnormal")
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
        if crashFD >= 0 { ftruncate(crashFD, 0) }
        try? FileManager.default.removeItem(at: traceURL)
        crashFD = open(traceURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        for u in reports() { try? FileManager.default.removeItem(at: u) }
    }

    private static func trimLog() {
        queue.sync {
            guard let t = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            let lines = t.split(separator: "\n")
            if lines.count > 400 { try? lines.suffix(200).joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8) }
        }
    }

    // 系统送来的崩溃报告
    static func reports() -> [URL] {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let all = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("crash-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // 把崩溃报告里最有用的部分提出来：异常类型、信号、终止原因、调用栈前几帧
    static func summary(_ u: URL) -> String {
        guard let d = try? Data(contentsOf: u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "" }
        var out = ""
        for (i, c) in ((j["crashDiagnostics"] as? [[String: Any]]) ?? []).prefix(2).enumerated() {
            if let m = c["diagnosticMetaData"] as? [String: Any] {
                out += "崩溃 \(i + 1)：" + ["exceptionType", "signal", "terminationReason", "appVersion", "osVersion"].compactMap { k in m[k].map { "\(k)=\($0)" } }.joined(separator: "，") + "\n"
            }
            if let tree = c["callStackTree"] as? [String: Any], let stacks = tree["callStacks"] as? [[String: Any]] {
                for st in stacks where (st["threadAttributed"] as? Bool) == true {
                    var frames: [String] = []
                    var cur = (st["callStackRootFrames"] as? [[String: Any]])?.first
                    while let f = cur, frames.count < 14 {
                        let name = (f["symbolName"] as? String) ?? "\(f["binaryName"] ?? "?")+\(f["offsetIntoBinaryTextSegment"] ?? "")"
                        frames.append(name)
                        cur = (f["subFrames"] as? [[String: Any]])?.first
                    }
                    out += frames.joined(separator: "\n") + "\n"
                }
            }
        }
        return out
    }

    final class Subscriber: NSObject, MXMetricManagerSubscriber {
        static let shared = Subscriber()
        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            for p in payloads where !(p.crashDiagnostics ?? []).isEmpty {
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd-HHmmss"
                try? p.jsonRepresentation().write(to: d.appendingPathComponent("crash-" + f.string(from: p.timeStampEnd) + ".json"))
            }
        }
    }
}

// MARK: 设置里的「诊断」页：上次异常退出的线索、系统崩溃报告、最近记录
struct DiagView: View {
    @State private var abnormal = Diag.lastAbnormal
    @State private var reports: [URL] = Diag.reports()
    @State private var log = Diag.tail(60)
    @State private var trace = Diag.trace()

    private var all: String {
        var s = "OSVIA 诊断（\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")，构建 \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")）\n"
        if !trace.isEmpty { s += "\n崩溃现场：\n" + trace + "\n" }
        if !abnormal.isEmpty { s += "\n" + abnormal + "\n" }
        for r in reports.prefix(2) { s += "\n系统崩溃报告 " + r.lastPathComponent + "\n" + Diag.summary(r) }
        s += "\n最近记录：\n" + log
        return s
    }

    var body: some View {
        List {
            Section {
                Text("遇到闪退或异常时，这里会留下线索。点「复制全部」发给开发者，就能快速定位问题。系统的崩溃报告通常在崩溃后一天内送达。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { UIPasteboard.general.string = all } label: { Label("复制全部", systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    Diag.clear()
                    abnormal = ""
                    reports = []
                    log = ""
                    trace = ""
                } label: { Label("清除记录", systemImage: "trash") }
            }
            if !trace.isEmpty {
                Section("崩溃现场") {
                    Text(verbatim: trace).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                }
            }
            if !abnormal.isEmpty {
                Section("上次异常退出") {
                    Text(verbatim: abnormal).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
            ForEach(reports, id: \.self) { r in
                Section(r.lastPathComponent) {
                    Text(verbatim: Diag.summary(r)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
            Section("最近记录") {
                Text(verbatim: log.isEmpty ? "（没有记录）" : log).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            abnormal = Diag.lastAbnormal
            reports = Diag.reports()
            log = Diag.tail(60)
            trace = Diag.trace()
        }
    }
}
