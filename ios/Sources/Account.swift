import Foundation
import CommonCrypto
import CryptoKit

// MARK: OSVIA 账号：网页版同一个账号。提醒中转（App 被结束也准时推送 Bark）、加密云备份
// 密码不上传：先在本机用 PBKDF2 派生出校验值再发给服务器，参数与网页版完全一致
enum Account {
    static let defaultBase = "https://osvia.tstzrm.workers.dev"

    struct Err: LocalizedError {
        let code: String
        let message: String
        var errorDescription: String? { message }
    }

    enum Step { case signedIn, needVerify }

    struct Usage {
        var reminders = 0
        var notes = 0
        var backups = 0
        var bytes: Int64 = 0
    }

    struct CloudFile: Identifiable {
        let id: String
        let name: String
        let size: Int64
        let created: Date
        let device: String
    }

    // MARK: 设置
    private static var ud: UserDefaults { .standard }

    static var base: String {
        var s = (ud.string(forKey: "acct.base") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultBase }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    static var customBase: String { ud.string(forKey: "acct.base") ?? "" }
    static func setBase(_ s: String) { ud.set(s.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "acct.base") }

    static var token: String {
        get { SecretStore.get("acct.token") }
        set { SecretStore.set("acct.token", newValue) }
    }
    static var email: String { ud.string(forKey: "acct.email") ?? "" }
    static var signedIn: Bool { !token.isEmpty }
    static var relayOn: Bool { ud.bool(forKey: "acct.relay") }

    // MARK: 密钥派生（与网页版一致：PBKDF2-SHA256 · 210000 次 · 盐 "osvia-auth-v1:"+小写邮箱 · NFKC 密码）
    static func normEmail(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func authKey(_ password: String, email: String) -> String {
        let pw = password.precomposedStringWithCompatibilityMapping
        let salt = [UInt8](("osvia-auth-v1:" + normEmail(email)).utf8)
        var out = [UInt8](repeating: 0, count: 32)
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.utf8.count, salt, salt.count,
                             CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000, &out, out.count)
        return Data(out).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func deriveKey(_ password: String, email: String) async -> String {
        await Task.detached(priority: .userInitiated) { authKey(password, email: email) }.value
    }

    // MARK: 网络
    private static func obj(_ d: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
    }

    private static func call(_ method: String, _ path: String, json: Any? = nil, file: URL? = nil,
                             auth: Bool = true, timeout: TimeInterval = 30) async throws -> Data {
        guard let url = URL(string: base + path) else {
            throw Err(code: "bad_url", message: L10n.tr("服务器地址不正确"))
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        if auth, signedIn { req.setValue("Bearer " + token, forHTTPHeaderField: "authorization") }
        let data: Data
        let resp: URLResponse
        do {
            if let file {
                req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
                (data, resp) = try await URLSession.shared.upload(for: req, fromFile: file)
            } else {
                if let json {
                    req.httpBody = try JSONSerialization.data(withJSONObject: json)
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                }
                (data, resp) = try await URLSession.shared.data(for: req)
            }
        } catch {
            if error is CancellationError { throw error }
            throw Err(code: "network", message: L10n.tr("网络不通，请检查连接"))
        }
        guard let http = resp as? HTTPURLResponse else {
            throw Err(code: "network", message: L10n.tr("网络不通，请检查连接"))
        }
        if http.statusCode >= 400 {
            let o = obj(data)
            let code = (o["error"] as? String) ?? "http_\(http.statusCode)"
            if http.statusCode == 401, auth, signedIn, code == "unauthorized" {
                signOutLocal()
                throw Err(code: code, message: L10n.tr("登录已失效，请重新登录"))
            }
            let msg = (o["message"] as? String).map { L10n.tr($0) } ?? "HTTP \(http.statusCode)"
            throw Err(code: code, message: msg)
        }
        return data
    }

    // MARK: 登录 / 注册
    private static func finish(_ data: Data) throws -> Step {
        let o = obj(data)
        if (o["needVerify"] as? Bool) == true { return .needVerify }
        guard let t = o["token"] as? String, !t.isEmpty else {
            throw Err(code: "bad_response", message: L10n.tr("服务器返回的内容不对"))
        }
        token = t
        if let u = o["user"] as? [String: Any], let e = u["email"] as? String { ud.set(e, forKey: "acct.email") }
        return .signedIn
    }

    static func register(email: String, password: String) async throws -> Step {
        let em = normEmail(email)
        let key = await deriveKey(password, email: em)
        let step = try finish(try await call("POST", "/api/auth/register", json: ["email": em, "authKey": key], auth: false))
        if step == .needVerify { ud.set(em, forKey: "acct.email") }
        return step
    }

    static func login(email: String, password: String) async throws -> Step {
        let em = normEmail(email)
        let key = await deriveKey(password, email: em)
        do {
            return try finish(try await call("POST", "/api/auth/login", json: ["email": em, "authKey": key], auth: false))
        } catch let e as Err where e.code == "need_verify" {
            return .needVerify
        }
    }

    static func verify(email: String, code: String) async throws {
        let em = normEmail(email)
        _ = try finish(try await call("POST", "/api/auth/verify", json: ["email": em, "code": code.trimmingCharacters(in: .whitespaces)], auth: false))
    }

    static func logout() async {
        if signedIn { _ = try? await call("POST", "/api/auth/logout") }
        signOutLocal()
    }

    static func signOutLocal() {
        token = ""
        ud.removeObject(forKey: "acct.barksig")
        DB.shared.run("UPDATE bark_queue SET cloud=0")
    }

    static func deleteAccount(password: String) async throws {
        let key = await deriveKey(password, email: email)
        _ = try await call("DELETE", "/api/me", json: ["authKey": key])
        signOutLocal()
        ud.removeObject(forKey: "acct.email")
        ud.set(false, forKey: "acct.relay")
    }

    // MARK: 账号信息
    static func me() async throws -> (verified: Bool, usage: Usage) {
        let o = obj(try await call("GET", "/api/me"))
        let u = o["user"] as? [String: Any] ?? [:]
        let c = o["counts"] as? [String: Any] ?? [:]
        func n(_ k: String) -> Int { (c[k] as? NSNumber)?.intValue ?? 0 }
        let verified = (u["verified"] as? Bool) ?? false
        return (verified, Usage(reminders: n("reminders"), notes: n("notes"), backups: n("backups"), bytes: Int64(n("backupBytes"))))
    }

    // MARK: 云备份（只上传加密备份，服务器看不到内容）
    static func listBackups() async throws -> [CloudFile] {
        let items = obj(try await call("GET", "/api/backups"))["items"] as? [[String: Any]] ?? []
        return items.compactMap { i in
            guard let id = i["id"] as? String else { return nil }
            return CloudFile(id: id,
                             name: (i["name"] as? String) ?? "OSVIA.\(Backup.ext)",
                             size: (i["size"] as? NSNumber)?.int64Value ?? 0,
                             created: Date(timeIntervalSince1970: (i["created"] as? NSNumber)?.doubleValue ?? 0),
                             device: (i["device"] as? String) ?? "")
        }
    }

    static func uploadBackup() async throws {
        let pass = Backup.passphrase
        guard !pass.isEmpty else {
            throw Err(code: "no_pass", message: L10n.tr("请先在「数据备份与恢复」里设置备份口令。云备份只上传加密文件。"))
        }
        let url = try await Backup.create(kind: "云", secrets: Backup.includeSecrets, pass: pass)
        defer { try? FileManager.default.removeItem(at: url) }
        var c = URLComponents()
        c.queryItems = [URLQueryItem(name: "name", value: url.lastPathComponent), URLQueryItem(name: "device", value: "iOS")]
        _ = try await call("PUT", "/api/backups?" + (c.percentEncodedQuery ?? ""), file: url, timeout: 180)
    }

    // 下载到本机备份目录，返回文件地址，交给恢复页
    static func download(_ f: CloudFile) async throws -> URL {
        let data = try await call("GET", "/api/backups/" + f.id, timeout: 180)
        guard Backup.isEncrypted(data) else {
            throw Err(code: "bad_file", message: L10n.tr("这不是有效的加密备份"))
        }
        var name = (f.name as NSString).lastPathComponent
        if (name as NSString).pathExtension != Backup.ext { name += "." + Backup.ext }
        var dest = Backup.dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = Backup.dir.appendingPathComponent("云-" + String(f.id.prefix(6)) + "-" + name)
        }
        try data.write(to: dest, options: [.atomic, .completeFileProtectionUnlessOpen])
        return dest
    }

    static func deleteBackup(_ f: CloudFile) async throws {
        _ = try await call("DELETE", "/api/backups/" + f.id)
    }

    // MARK: 提醒中转：把排队中的 Bark 提醒交给云端，到点由服务器推送，App 没在运行也准时
    private static let syncLock = NSLock()
    private static var syncTask: Task<Void, Never>?
    private static var syncing = false

    static func scheduleSync(after seconds: Double = 3) {
        guard signedIn, relayOn else { return }
        syncLock.lock()
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { await sync() }
        }
        syncLock.unlock()
    }

    private static func pushBarkIfChanged() async throws {
        let keys = Bark.keys.joined(separator: ",")
        let raw = [Bark.server, keys, Bark.encryptionKey, base, email].joined(separator: "\n")
        let sig = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        if ud.string(forKey: "acct.barksig") == sig { return }
        _ = try await call("PUT", "/api/bark", json: ["server": Bark.server, "key": keys, "enc": Bark.encryptionKey])
        ud.set(sig, forKey: "acct.barksig")
    }

    static func sync() async {
        guard signedIn, relayOn, Bark.ready else { return }
        syncLock.lock()
        if syncing { syncLock.unlock(); return }
        syncing = true
        syncLock.unlock()
        defer { syncLock.lock(); syncing = false; syncLock.unlock() }

        do {
            try await pushBarkIfChanged()
            let now = Date().timeIntervalSince1970
            let rows = DB.shared.rows("SELECT id,due,title,body FROM bark_queue WHERE due>? ORDER BY due LIMIT 300", [now + 5])
            let items: [[String: Any]] = rows.map { r in
                ["ref": "\(r.s("id"))@\(Int(r.d("due")))", "title": r.s("title"), "body": r.s("body"), "due": Int(r.d("due"))]
            }
            _ = try await call("POST", "/api/relay", json: ["items": items])
            for r in rows {
                DB.shared.run("UPDATE bark_queue SET cloud=1 WHERE id=? AND due=?", [r.s("id"), r.d("due")])
            }
        } catch {
            // 同步失败就保持本机推送，下次再试
        }
    }

    static func setRelay(_ on: Bool) async throws {
        if on {
            guard Bark.ready else {
                throw Err(code: "no_bark", message: L10n.tr("请先开启 Bark 提醒并填写设备密钥"))
            }
            ud.removeObject(forKey: "acct.barksig")
            try await pushBarkIfChanged()   // 服务器拒绝时直接报错，不会处于「已开启但没生效」的状态
            ud.set(true, forKey: "acct.relay")
            await sync()
        } else {
            ud.set(false, forKey: "acct.relay")
            DB.shared.run("UPDATE bark_queue SET cloud=0")
            _ = try? await call("POST", "/api/relay", json: ["items": [Any]()])
        }
    }
}
