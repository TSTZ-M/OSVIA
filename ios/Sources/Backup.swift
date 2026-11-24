import Foundation
import CryptoKit
import CommonCrypto
import Security
import UIKit

// MARK: 数据备份：对话、记忆、知识库、脚本、任务、连接器、邮箱账号、偏好设置，打成一个 .osvbackup 文件
// 格式：魔数 OSVB + 版本 + 标志；内容为 JSON（LZFSE 压缩）。设了口令就用 AES-256-GCM 加密（口令经 PBKDF2-SHA256 20 万次派生），
// 没设口令则附 SHA-256 校验，防止文件损坏后误恢复。钥匙串里的密钥和密码只在加密备份里、并且用户勾选时才会写入。
enum Backup {
    struct Category: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tables: [String]
    }

    // 闹钟表是系统闹钟的登记，换设备没有意义，不备份
    static let categories: [Category] = [
        Category(id: "chats", title: "对话记录", icon: "bubble.left.and.bubble.right", tables: ["conv", "msg"]),
        Category(id: "memory", title: "记忆与进化", icon: "brain.head.profile", tables: ["memory", "evo", "prompt"]),
        Category(id: "kb", title: "知识库", icon: "books.vertical", tables: ["doc", "chunk"]),
        Category(id: "skills", title: "脚本技能", icon: "curlybraces", tables: ["skill"]),
        Category(id: "tasks", title: "定时任务", icon: "clock", tables: ["task"]),
        Category(id: "connectors", title: "连接器与 MCP 服务", icon: "puzzlepiece.extension", tables: ["connector", "mcp_server"]),
        Category(id: "mail", title: "邮箱账号", icon: "envelope", tables: ["mail_account"]),
        Category(id: "settings", title: "偏好设置", icon: "gearshape", tables: ["kv"])
    ]

    static let ext = "osvbackup"
    static let magic = Data("OSVB".utf8)
    static var dir: URL { Store.dir("Backups") }

    // 偏好设置里值得带走的键（不含缓存、临时状态、本地模型文件相关）
    private static let defaultKeys: Set<String> = ["appearance", "saveHistory", "style", "autoSend", "liveOn", "cloudOn", "cloudBase", "cloudModel", "cloudPreset",
                                                    "modelMode", "transTarget", "appLang", "folders", "shareBase", "alarmMode", "mail.logos", "localOn",
                                                    "backup.auto", "backup.keep", "backup.secrets"]
    private static func wantsDefault(_ k: String) -> Bool {
        defaultKeys.contains(k) || (k.hasPrefix("bark.") && k != "bark.lastErr" && k != "bark.lastOK")
    }
    private static let skipKV = ["mail.err.", "mail.dbg.", "mail.failAt.", "mail.stat.", "mail.warn.", "evolve.try", "skill.last."]

    struct FileInfo: Identifiable {
        let url: URL
        let date: Date
        let size: Int64
        var id: String { url.path }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    struct Info {
        var created: Date
        var version: String
        var counts: [String: Int]
        var secretCount: Int
        var encrypted: Bool
    }

    static func fail(_ s: String, code: Int = 1) -> NSError {
        NSError(domain: "OSVIA.Backup", code: code, userInfo: [NSLocalizedDescriptionKey: s])
    }
    static func needsPassphrase(_ e: Error) -> Bool { (e as NSError).domain == "OSVIA.Backup" && (e as NSError).code == 401 }

    // MARK: 口令与自动备份设置
    static var passphrase: String {
        get { SecretStore.get("backup.pass") }
        set { SecretStore.set("backup.pass", newValue) }
    }
    static var autoOn: Bool { UserDefaults.standard.bool(forKey: "backup.auto") }
    static var keep: Int { max(UserDefaults.standard.integer(forKey: "backup.keep") == 0 ? 7 : UserDefaults.standard.integer(forKey: "backup.keep"), 1) }
    static var includeSecrets: Bool { UserDefaults.standard.bool(forKey: "backup.secrets") }
    static var lastTime: Date? {
        let t = UserDefaults.standard.double(forKey: "backup.last")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: 收集
    private static func encodeRow(_ r: Row) -> [String: Any] {
        var o: [String: Any] = [:]
        for (k, v) in r {
            switch v {
            case let d as Double: o[k] = d.isFinite ? d : 0
            case let d as Data: o[k] = ["$b64": d.base64EncodedString()]
            default: o[k] = v
            }
        }
        return o
    }

    static func allSecrets() -> [String: String] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "OSVIA",
                                kSecReturnAttributes as String: true, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let arr = out as? [[String: Any]] else { return [:] }
        var m: [String: String] = [:]
        for a in arr {
            guard let k = a[kSecAttrAccount as String] as? String, k != "backup.pass", let d = a[kSecValueData as String] as? Data else { continue }
            m[k] = String(decoding: d, as: UTF8.self)
        }
        return m
    }

    static func snapshot(secrets: Bool) -> [String: Any] {
        var tables: [String: Any] = [:]
        for c in categories {
            for t in c.tables {
                var rows = DB.shared.rows("SELECT * FROM \(t)")
                if t == "kv" { rows = rows.filter { r in !skipKV.contains { r.s("k").hasPrefix($0) } } }
                tables[t] = rows.map(encodeRow)
            }
        }
        var defaults: [String: Any] = [:]
        for (k, v) in UserDefaults.standard.dictionaryRepresentation() where wantsDefault(k) {
            if v is String || v is NSNumber || v is [String] { defaults[k] = v }
        }
        var snap: [String: Any] = [
            "format": 1, "app": "OSVIA", "created": Date().timeIntervalSince1970,
            "version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") + ")",
            "tables": tables, "defaults": defaults
        ]
        if secrets { snap["secrets"] = allSecrets() }
        return snap
    }

    // MARK: 打包 / 解包
    private static let headerEnc = 26   // 魔数 4 + 版本 1 + 标志 1 + 盐 16 + 迭代次数 4

    private static func derive(_ pass: String, salt: Data, iter: Int) -> SymmetricKey? {
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let st = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass, pass.utf8.count, saltBytes, saltBytes.count,
                                      CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iter), &out, out.count)
        return st == Int32(kCCSuccess) ? SymmetricKey(data: Data(out)) : nil
    }

    static func pack(_ snap: [String: Any], pass: String) throws -> Data {
        guard JSONSerialization.isValidJSONObject(snap) else { throw fail("数据无法编码") }
        let json = try JSONSerialization.data(withJSONObject: snap)
        let comp = try (json as NSData).compressed(using: .lzfse) as Data
        var out = magic
        out.append(1)
        if pass.isEmpty {
            out.append(0)
            out.append(Data(SHA256.hash(data: comp)))
            out.append(comp)
            return out
        }
        out.append(1)
        var salt = Data(count: 16)
        let rc = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard rc == errSecSuccess else { throw fail("无法生成随机数") }
        let iter = 200_000
        var be = UInt32(iter).bigEndian
        out.append(salt)
        out.append(Data(bytes: &be, count: 4))
        guard let key = derive(pass, salt: salt, iter: iter) else { throw fail("口令处理失败") }
        let box = try AES.GCM.seal(comp, using: key, authenticating: out)
        guard let combined = box.combined else { throw fail("加密失败") }
        out.append(combined)
        return out
    }

    static func unpack(_ data: Data, pass: String) throws -> [String: Any] {
        guard data.count > 40, Data(data.prefix(4)) == magic else { throw fail("这不是 OSVIA 备份文件。") }
        guard data[data.startIndex + 4] == 1 else { throw fail("这份备份来自更新版本的 OSVIA，请先升级再恢复。") }
        let comp: Data
        if data[data.startIndex + 5] == 1 {
            guard !pass.isEmpty else { throw fail("这份备份已加密，请输入口令。", code: 401) }
            guard data.count > headerEnc + 28 else { throw fail("备份文件已损坏。") }
            let header = Data(data.prefix(headerEnc))
            let salt = Data(header[6..<22])
            let iter = Int(header[22..<26].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard iter >= 10_000, iter <= 5_000_000, let key = derive(pass, salt: salt, iter: iter) else { throw fail("备份文件已损坏。") }
            do {
                let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst(headerEnc)))
                comp = try AES.GCM.open(box, using: key, authenticating: header)
            } catch {
                throw fail("口令不对，或备份文件已损坏。", code: 401)
            }
        } else {
            let hash = Data(data[(data.startIndex + 6)..<(data.startIndex + 38)])
            comp = Data(data.dropFirst(38))
            guard Data(SHA256.hash(data: comp)) == hash else { throw fail("备份文件已损坏，校验没有通过。") }
        }
        let json = try (comp as NSData).decompressed(using: .lzfse) as Data
        guard let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any], obj["app"] as? String == "OSVIA" else {
            throw fail("备份内容无法识别。")
        }
        return obj
    }

    static func isEncrypted(_ data: Data) -> Bool { data.count > 6 && Data(data.prefix(4)) == magic && data[data.startIndex + 5] == 1 }

    static func info(_ snap: [String: Any], encrypted: Bool) -> Info {
        let tables = (snap["tables"] as? [String: Any]) ?? [:]
        var counts: [String: Int] = [:]
        for c in categories {
            counts[c.id] = c.tables.reduce(0) { $0 + (((tables[$1] as? [Any])?.count) ?? 0) }
        }
        counts["settings"] = (counts["settings"] ?? 0) + (((snap["defaults"] as? [String: Any])?.count) ?? 0)
        return Info(created: Date(timeIntervalSince1970: (snap["created"] as? Double) ?? 0), version: (snap["version"] as? String) ?? "",
                    counts: counts, secretCount: ((snap["secrets"] as? [String: Any])?.count) ?? 0, encrypted: encrypted)
    }

    // MARK: 创建
    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    // kind：备份 / 自动 / 恢复前
    static func create(kind: String, secrets: Bool, pass: String) async throws -> URL {
        let wantSecrets = secrets && !pass.isEmpty
        let url = dir.appendingPathComponent("OSVIA-\(kind)-\(stamp()).\(ext)")
        try await Task.detached(priority: .utility) {
            let data = try pack(snapshot(secrets: wantSecrets), pass: pass)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        }.value
        if kind != "恢复前" { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "backup.last") }
        prune()
        return url
    }

    // 自动备份：回到前台时，距离上一次超过 20 小时就备份一次
    static func autoIfDue() async {
        guard autoOn else { return }
        if let t = lastTime, Date().timeIntervalSince(t) < 20 * 3600 { return }
        _ = try? await create(kind: "自动", secrets: includeSecrets, pass: passphrase)
    }

    static func list() -> [FileInfo] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return items.filter { $0.pathExtension == ext }.map { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return FileInfo(url: u, date: v?.contentModificationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    // 自动备份和恢复前备份各保留最近 N 份；手动备份不删
    static func prune() {
        let all = list()
        for prefix in ["OSVIA-自动-", "OSVIA-恢复前-"] {
            let mine = all.filter { $0.url.lastPathComponent.hasPrefix(prefix) }
            let n = prefix == "OSVIA-自动-" ? keep : 3
            for f in mine.dropFirst(n) { try? FileManager.default.removeItem(at: f.url) }
        }
    }

    // MARK: 恢复
    private static func decode(_ v: Any) -> Any? {
        switch v {
        case is NSNull: return nil
        case let d as [String: Any]:
            if let b = d["$b64"] as? String { return Data(base64Encoded: b) ?? Data() }
            return nil
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return Int64(n.boolValue ? 1 : 0) }
            return CFNumberIsFloatType(n) ? n.doubleValue : n.int64Value
        case let s as String: return s
        default: return nil
        }
    }

    private static func validName(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    // 覆盖所选类别对应的数据。返回恢复条数的摘要
    @MainActor
    static func restore(_ snap: [String: Any], categories ids: Set<String>, secrets: Bool) async -> String {
        let tables = (snap["tables"] as? [String: Any]) ?? [:]
        var total = 0
        let db = DB.shared
        db.exec("BEGIN")
        for c in categories where ids.contains(c.id) {
            for t in c.tables {
                guard let rows = tables[t] as? [[String: Any]] else { continue }
                let cols = Set(db.rows("PRAGMA table_info(\(t))").map { $0.s("name") })
                guard !cols.isEmpty else { continue }
                db.run("DELETE FROM \(t)")
                for r in rows {
                    let names = r.keys.filter { cols.contains($0) && validName($0) }.sorted()
                    guard !names.isEmpty else { continue }
                    let sql = "INSERT OR REPLACE INTO \(t)(" + names.joined(separator: ",") + ") VALUES(" + names.map { _ in "?" }.joined(separator: ",") + ")"
                    db.run(sql, names.map { n in r[n].flatMap { decode($0) } })
                    total += 1
                }
            }
        }
        db.exec("COMMIT")

        if ids.contains("settings"), let d = snap["defaults"] as? [String: Any] {
            for (k, v) in d where wantsDefault(k) { UserDefaults.standard.set(v, forKey: k) }
        }
        if secrets, let s = snap["secrets"] as? [String: String] {
            for (k, v) in s { SecretStore.set(k, v) }
        }
        if ids.contains("mail") {
            db.run("DELETE FROM mail_triage")
            db.run("DELETE FROM mail_log")
        }
        if ids.contains("skills") && !ids.contains("kb") {
            for s in Skills.list() { KB.shared.upsert("技能:" + s.s("name"), s.s("desc") + "（用 run_skill 调用：" + s.s("name") + "）") }
        }
        if ids.contains("chats") { Agent.shared.newChat() }
        if ids.contains("tasks") { _ = await Tasks.refresh() }
        if ids.contains("settings"), UserDefaults.standard.bool(forKey: "bark.on") { Bark.scheduleBG() }
        return L10n.f("已恢复 {} 条数据", "\(total)")
    }
}
