import SwiftUI
import SQLite3

enum Theme {
    static let accents: [(String, Color)] = [
        ("薄荷绿", Color(red: 0.05, green: 0.56, blue: 0.43)),
        ("海军蓝", Color(red: 0.12, green: 0.30, blue: 0.62)),
        ("琥珀金", Color(red: 0.70, green: 0.46, blue: 0.05)),
        ("紫罗兰", Color(red: 0.42, green: 0.30, blue: 0.85)),
        ("玫瑰红", Color(red: 0.84, green: 0.20, blue: 0.40))
    ]
    static func accent(_ i: Int) -> Color { accents[min(max(i, 0), accents.count - 1)].1 }
    static let gold = Color(red: 0.93, green: 0.74, blue: 0.36)
    static let navy = Color(red: 0.05, green: 0.12, blue: 0.28)
}

typealias Row = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String { (self[k] as? String) ?? "" }
    func d(_ k: String) -> Double { (self[k] as? Double) ?? Double((self[k] as? Int64) ?? 0) }
    func i(_ k: String) -> Int { Int((self[k] as? Int64) ?? 0) }
}

final class DB {
    static let shared = DB()
    private var h: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        sqlite3_open(dir.appendingPathComponent("agent.sqlite").path, &h)
        let schema = """
        CREATE TABLE IF NOT EXISTS msg(id INTEGER PRIMARY KEY, role TEXT, text TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS doc(id INTEGER PRIMARY KEY, name TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS chunk(id INTEGER PRIMARY KEY, doc INTEGER, text TEXT, vec BLOB);
        CREATE TABLE IF NOT EXISTS task(id INTEGER PRIMARY KEY, title TEXT, instr TEXT, due REAL, use_model INTEGER, rep INTEGER, result TEXT, state INTEGER DEFAULT 0, notified INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS skill(name TEXT PRIMARY KEY, desc TEXT, code TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS prompt(ver INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);
        CREATE TABLE IF NOT EXISTS conv(id INTEGER PRIMARY KEY, title TEXT, ts REAL);
        CREATE TABLE IF NOT EXISTS evo(id INTEGER PRIMARY KEY, ts REAL, summary TEXT, facts TEXT, ver INTEGER);
        CREATE TABLE IF NOT EXISTS connector(id INTEGER PRIMARY KEY, name TEXT, kind TEXT, url TEXT, method TEXT, headers TEXT, body TEXT);
        CREATE TABLE IF NOT EXISTS alarm(id TEXT PRIMARY KEY, label TEXT, due REAL, rep INTEGER);
        CREATE TABLE IF NOT EXISTS memory(id INTEGER PRIMARY KEY, text TEXT, cat TEXT, src TEXT, ts REAL, pin INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS mcp_server(id INTEGER PRIMARY KEY, name TEXT, url TEXT, auto INTEGER DEFAULT 0, enabled INTEGER DEFAULT 1, tools TEXT DEFAULT '', ts REAL);
        CREATE TABLE IF NOT EXISTS mail_account(id INTEGER PRIMARY KEY, email TEXT, name TEXT DEFAULT '', user TEXT, imap_host TEXT, imap_port INTEGER DEFAULT 993, smtp_host TEXT, smtp_port INTEGER DEFAULT 465, smtp_starttls INTEGER DEFAULT 0, provider TEXT DEFAULT '', auto INTEGER DEFAULT 0, ts REAL, last_run REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS mail_triage(id INTEGER PRIMARY KEY, mkey TEXT UNIQUE, acct INTEGER, uid INTEGER, validity INTEGER, from_name TEXT, from_addr TEXT, reply_to TEXT, subject TEXT, ts REAL, cat TEXT, summary TEXT, act TEXT, snippet TEXT, msgid TEXT, refs TEXT, unread INTEGER DEFAULT 1);
        CREATE TABLE IF NOT EXISTS mail_log(id INTEGER PRIMARY KEY, ts REAL, acct INTEGER, text TEXT);
        CREATE TABLE IF NOT EXISTS bark_queue(id TEXT PRIMARY KEY, due REAL, title TEXT, body TEXT, ev TEXT, rep INTEGER DEFAULT 0);
        """
        // 一条一条执行：某一条出错时不会连累后面的表没建出来
        for st in schema.components(separatedBy: ";\n") {
            let t = st.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { exec(t) }
        }
        exec("ALTER TABLE mail_triage ADD COLUMN flagged INTEGER DEFAULT 0")
        exec("ALTER TABLE mail_triage ADD COLUMN to_list TEXT DEFAULT ''")
        exec("ALTER TABLE mail_triage ADD COLUMN cc_list TEXT DEFAULT ''")
        exec("ALTER TABLE msg ADD COLUMN conv INTEGER DEFAULT 0")
        exec("ALTER TABLE msg ADD COLUMN files TEXT DEFAULT ''")
        exec("ALTER TABLE msg ADD COLUMN meta TEXT DEFAULT ''")
        exec("ALTER TABLE bark_queue ADD COLUMN cloud INTEGER DEFAULT 0")
        exec("ALTER TABLE conv ADD COLUMN pin INTEGER DEFAULT 0")
    }

    func exec(_ sql: String) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(h, sql, nil, nil, nil)
    }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        sqlite3_step(st)
        return sqlite3_last_insert_rowid(h)
    }

    func rows(_ sql: String, _ args: [Any?] = []) -> [Row] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        var out: [Row] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var r: Row = [:]
            for i in 0..<sqlite3_column_count(st) {
                let name = String(cString: sqlite3_column_name(st, i))
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: r[name] = sqlite3_column_int64(st, i)
                case SQLITE_FLOAT: r[name] = sqlite3_column_double(st, i)
                case SQLITE_TEXT: r[name] = String(cString: sqlite3_column_text(st, i))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(st, i))
                    r[name] = n > 0 ? Data(bytes: sqlite3_column_blob(st, i), count: n) : Data()
                default: break
                }
            }
            out.append(r)
        }
        return out
    }

    private func bind(_ st: OpaquePointer?, _ args: [Any?]) {
        for (i, a) in args.enumerated() {
            let n = Int32(i + 1)
            switch a {
            case let v as Int: sqlite3_bind_int64(st, n, Int64(v))
            case let v as Int64: sqlite3_bind_int64(st, n, v)
            case let v as Double: sqlite3_bind_double(st, n, v)
            case let v as String: sqlite3_bind_text(st, n, v, -1, transient)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(st, n, $0.baseAddress, Int32(v.count), transient) }
            default: sqlite3_bind_null(st, n)
            }
        }
    }

    func kv(_ k: String) -> String? { rows("SELECT v FROM kv WHERE k=?", [k]).first?.s("v") }
    func setKV(_ k: String, _ v: String) { run("INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)", [k, v]) }
}

enum Store {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func dir(_ n: String) -> URL {
        let u = docs.appendingPathComponent(n)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func rel(_ u: URL) -> String {
        let base = docs.path + "/"
        return u.path.hasPrefix(base) ? String(u.path.dropFirst(base.count)) : u.lastPathComponent
    }

    static func abs(_ r: String) -> URL { docs.appendingPathComponent(r) }

    static func copyIn(_ src: URL) -> URL? {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        let dst = dir("Inbox").appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        do { try FileManager.default.copyItem(at: src, to: dst); return dst } catch { return nil }
    }

    // 友好的文件名，如「照片 03.08.12.jpg」
    static func stamped(_ prefix: String, _ ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "MMdd HH.mm.ss"
        return dir("Inbox").appendingPathComponent("\(prefix) \(f.string(from: Date())).\(ext)")
    }
}

// 把技术性报错翻成人话
func friendly(_ s: String) -> String {
    if s.contains("setTimeout") || s.contains("ReferenceError") { return "脚本用了不支持的功能" }
    if s.contains("SyntaxError") { return "脚本写法有误" }
    if s.contains("TypeError") { return "脚本运行出错" }
    return String(s.prefix(80))
}
