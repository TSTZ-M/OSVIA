import Foundation
import CryptoKit
import UIKit
import BackgroundTasks

// MARK: Bark：把提醒、闹钟、定时任务、重要邮件同步推送到 Bark（iPhone、iPad、Mac、手表上的 Bark 都能收到）
// 本机通知照常发出；Bark 只是多一条通道。推送内容可选 AES-GCM 加密，服务器看不到正文。
// 到点推送在 App 运行时（前台每 15 秒检查一次）和系统给的后台刷新机会里发出；App 被完全关闭时，系统不允许它联网，
// 所以「准时」靠本机通知保证，Bark 是尽力而为。
enum Bark {
    enum Event: String, CaseIterable, Identifiable {
        case remind, alarm, task, mail, agent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .remind: return "提醒事项"
            case .alarm: return "闹钟与倒计时"
            case .task: return "定时任务"
            case .mail: return "重要邮件"
            case .agent: return "助理主动消息"
            }
        }
        var icon: String {
            switch self {
            case .remind: return "checklist"
            case .alarm: return "alarm"
            case .task: return "clock.badge.checkmark"
            case .mail: return "envelope.badge"
            case .agent: return "sparkles"
            }
        }
        // 点开 Bark 通知时回到 OSVIA 的哪里
        var link: String {
            switch self {
            case .mail: return "osvia://mail"
            case .task, .remind, .alarm: return "osvia://tasks"
            case .agent: return ""
            }
        }
    }

    nonisolated static let bgID = "com.Hao-Yi-Miao.TSTZ-Agent.bark"
    static let defaultServer = "https://api.day.app"
    static let levels: [(String, String)] = [("timeSensitive", "时效性通知"), ("active", "普通"), ("passive", "静默"), ("critical", "重要警告")]

    private static var ud: UserDefaults { .standard }

    // MARK: 设置
    static var enabled: Bool { ud.bool(forKey: "bark.on") }
    static var server: String { (ud.string(forKey: "bark.server") ?? "").isEmpty ? defaultServer : ud.string(forKey: "bark.server") ?? defaultServer }
    static var level: String { ud.string(forKey: "bark.level") ?? "timeSensitive" }
    static var sound: String { ud.string(forKey: "bark.sound") ?? "" }
    static var group: String { (ud.string(forKey: "bark.group") ?? "").isEmpty ? "OSVIA" : ud.string(forKey: "bark.group") ?? "OSVIA" }
    static func on(_ e: Event) -> Bool { ud.object(forKey: "bark.ev." + e.rawValue) as? Bool ?? true }
    static func setOn(_ e: Event, _ v: Bool) { ud.set(v, forKey: "bark.ev." + e.rawValue) }

    static var keys: [String] {
        SecretStore.get("bark.keys").components(separatedBy: CharacterSet(charactersIn: ",;，；\n ")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static var encryptionKey: String { SecretStore.get("bark.enc") }
    static var ready: Bool { enabled && !keys.isEmpty }

    // 用户可能直接粘贴 Bark 里复制的完整推送地址：https://api.day.app/AbCdEf/这里改成推送内容
    // 返回（服务器，密钥）；只是一串密钥时服务器为空
    static func parse(_ raw: String) -> (server: String, key: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.contains("://"), let u = URLComponents(string: s), let host = u.host, let key = u.path.split(separator: "/").first else {
            return ("", s)
        }
        let port = u.port.map { ":\($0)" } ?? ""
        return ((u.scheme ?? "https") + "://" + host + port, String(key))
    }

    static func normalizedServer(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { t = defaultServer }
        if !t.contains("://") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        guard let u = URL(string: t), u.scheme == "https", u.host != nil else { return nil }
        return u
    }

    // MARK: 加密（Bark 的 AES-GCM：密钥 16/24/32 个字符，随机 12 位 iv 随请求发送，密文 = 密文 + 标签，Base64）
    static func encrypt(_ obj: [String: Any], key: String) -> (cipher: String, iv: String)? {
        let kd = Data(key.utf8)
        guard [16, 24, 32].contains(kd.count), JSONSerialization.isValidJSONObject(obj),
              let plain = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let iv = String((0..<12).map { _ in chars[Int.random(in: 0..<chars.count)] })
        guard let nonce = try? AES.GCM.Nonce(data: Data(iv.utf8)),
              let box = try? AES.GCM.seal(plain, using: SymmetricKey(data: kd), nonce: nonce) else { return nil }
        return ((box.ciphertext + box.tag).base64EncodedString(), iv)
    }

    // MARK: 发送。返回错误文字，空串表示成功
    @discardableResult
    static func send(_ e: Event?, title: String, body: String, url: String = "", call: Bool = false, force: Bool = false) async -> String {
        if !force {
            guard enabled else { return "Bark 提醒没有开启。" }
            if let e, !on(e) { return "" }
        }
        let ks = keys
        guard !ks.isEmpty else { return "还没有填写 Bark 设备密钥。" }
        guard let base = normalizedServer(server) else { return "服务器地址需要以 https:// 开头。" }
        var errors: [String] = []
        for k in ks {
            var obj: [String: Any] = ["title": title, "body": body, "level": level, "group": group, "isArchive": "1",
                                      "icon": "https://raw.githubusercontent.com/TSTZ-M/OSVIA/main/assets/icon-192.png"]
            if !sound.isEmpty { obj["sound"] = sound }
            let link = url.isEmpty ? (e?.link ?? "") : url
            if !link.isEmpty { obj["url"] = link }
            if call { obj["call"] = "1" }
            var payload: [String: Any]
            let enc = encryptionKey
            if enc.isEmpty {
                obj["device_key"] = k
                payload = obj
            } else {
                guard let c = encrypt(obj, key: enc) else { return "加密密钥长度必须是 16、24 或 32 个字符。" }
                payload = ["device_key": k, "ciphertext": c.cipher, "iv": c.iv]
            }
            let err = await post(base.appendingPathComponent("push"), payload)
            if !err.isEmpty { errors.append(err) }
        }
        let err = errors.first ?? ""
        ud.set(err, forKey: "bark.lastErr")
        if err.isEmpty { ud.set(Date().timeIntervalSince1970, forKey: "bark.lastOK") }
        return err
    }

    private static func post(_ url: URL, _ payload: [String: Any]) async -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "内容无法编码。" }
        var last = ""
        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 12
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { return "" }
                let msg = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["message"] as? String ?? ""
                last = "Bark 服务器返回 \(code)" + (msg.isEmpty ? "" : "：" + msg)
                if code < 500 { return last }
            } catch {
                last = "连接 Bark 服务器失败：" + error.localizedDescription
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
        }
        return last
    }

    // MARK: 排队：本机通知登记的同时，登记一条到点推送
    static func event(forID id: String) -> Event {
        if id.hasPrefix("task-") { return .task }
        if id.hasPrefix("mail.") { return .mail }
        if id.hasPrefix("alarm-") { return .alarm }
        return .remind
    }

    static func schedule(id: String, title: String, body: String, at d: Date, rep: Int = 0, ev: Event) {
        guard enabled, on(ev) else { return }
        DB.shared.run("INSERT OR REPLACE INTO bark_queue(id,due,title,body,ev,rep) VALUES(?,?,?,?,?,?)",
                      [id, d.timeIntervalSince1970, title, body, ev.rawValue, rep])
        let wait = d.timeIntervalSinceNow
        if wait <= 20 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000) + 400_000_000)
                await flush()
            }
        } else {
            scheduleBG()
        }
    }

    static func cancel(_ id: String) { DB.shared.run("DELETE FROM bark_queue WHERE id=?", [id]) }

    static func pending() -> [Row] { DB.shared.rows("SELECT * FROM bark_queue ORDER BY due LIMIT 30") }

    private static let lock = NSLock()
    private static var busy = false

    // 把到期的都发出去。重复提醒推进到下一次；错过超过 12 小时的不补发
    static func flush() async {
        guard enabled, !keys.isEmpty else { return }
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        defer { lock.lock(); busy = false; lock.unlock() }

        let now = Date().timeIntervalSince1970
        for r in DB.shared.rows("SELECT * FROM bark_queue WHERE due<=? ORDER BY due LIMIT 20", [now + 1]) {
            let id = r.s("id")
            let rep = r.i("rep")
            let dueAt = r.d("due")
            if rep > 0 {
                var next = dueAt
                while next <= now { next += Double(rep) * 86400 }
                DB.shared.run("UPDATE bark_queue SET due=? WHERE id=?", [next, id])
            } else {
                DB.shared.run("DELETE FROM bark_queue WHERE id=?", [id])
            }
            if now - dueAt > 12 * 3600 { continue }
            let ev = Event(rawValue: r.s("ev")) ?? .remind
            guard on(ev) else { continue }
            await send(ev, title: r.s("title"), body: r.s("body"))
        }
    }

    // 立即推送（助理主动消息、测试之外的即时事件）
    static func now(_ e: Event, title: String, body: String, url: String = "") {
        guard ready, on(e) else { return }
        Task { await send(e, title: L10n.tr(title), body: L10n.tr(body), url: url) }
    }

    // MARK: 前台循环与后台刷新
    @MainActor private static var loop: Task<Void, Never>?

    @MainActor static func startLoop() {
        loop?.cancel()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                await flush()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    @MainActor static func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    nonisolated static func registerBG() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgID, using: nil) { task in
            Task { @MainActor in await handleBG(task) }
        }
    }

    nonisolated static func scheduleBG() {
        let next = DB.shared.rows("SELECT MIN(due) AS d FROM bark_queue").first?.d("d") ?? 0
        let r = BGAppRefreshTaskRequest(identifier: bgID)
        let at = next > 0 ? max(next - 30, Date().timeIntervalSince1970 + 60) : Date().timeIntervalSince1970 + 900
        r.earliestBeginDate = Date(timeIntervalSince1970: at)
        try? BGTaskScheduler.shared.submit(r)
    }

    @MainActor private static func handleBG(_ t: BGTask) async {
        scheduleBG()
        let work = Task { await flush() }
        t.expirationHandler = { work.cancel() }
        await work.value
        t.setTaskCompleted(success: true)
    }

    // MARK: 给助理用的工具：用户说「推送到我的 Bark」「用 Bark 通知我」
    static func doc() -> String {
        guard ready else { return "" }
        return "- bark_send {\"title\":\"标题\",\"body\":\"内容\"}：把一条消息推送到用户的 Bark（其他设备、手表上能收到）。用户要求「通知我」「推送到手机」时用\n"
    }

    @MainActor static func run(_ c: ToolCall, trace: Tracer) async -> ToolResult? {
        guard c.name == "bark_send" else { return nil }
        let a = c.args
        let title = ((a["title"] as? String) ?? "OSVIA").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ((a["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready else { return ToolResult(text: "用户还没有开启 Bark 提醒。请告诉用户到 设置 → Bark 提醒 里填好设备密钥并开启。", ok: false) }
        guard !body.isEmpty else { return ToolResult(text: "缺少推送内容。", ok: false) }
        let sid = trace.begin(.phone, "推送到 Bark", String(body.prefix(40)))
        let e = await send(.agent, title: title.isEmpty ? "OSVIA" : String(title.prefix(60)), body: String(body.prefix(400)), force: true)
        trace.end(sid, ok: e.isEmpty, detail: e.isEmpty ? nil : e)
        return e.isEmpty ? ToolResult(text: "已推送到 Bark。") : ToolResult(text: "推送失败：" + e, ok: false)
    }
}
