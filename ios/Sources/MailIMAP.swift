import Foundation

// MARK: 邮件网络层：IMAP（收、整理）+ SMTP（发）。基于 URLSessionStreamTask，隐式 TLS（993 / 465）或 STARTTLS（587）。
struct MailError: Error { let msg: String; init(_ m: String) { msg = m } }

final class MailStream {
    private let session: URLSession
    private let task: URLSessionStreamTask
    private var buf = Data()

    init(host: String, port: Int, tls: Bool) {
        session = URLSession(configuration: .ephemeral)
        task = session.streamTask(withHostName: host, port: port)
        if tls { task.startSecureConnection() }
        task.resume()
    }

    func startTLS() { task.startSecureConnection() }

    func close() {
        task.closeRead()
        task.closeWrite()
        session.invalidateAndCancel()
    }

    func write(_ s: String) async throws { try await write(Data(s.utf8)) }

    func write(_ d: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            task.write(d, timeout: 30) { e in
                if let e { c.resume(throwing: MailError(e.localizedDescription)) } else { c.resume() }
            }
        }
    }

    private func fill() async throws {
        let d: Data = try await withCheckedThrowingContinuation { c in
            task.readData(ofMinLength: 1, maxLength: 65536, timeout: 30) { data, eof, e in
                if let e { c.resume(throwing: MailError(e.localizedDescription)) } else if let data, !data.isEmpty { c.resume(returning: data) } else if eof { c.resume(throwing: MailError("服务器断开了连接")) } else { c.resume(returning: Data()) }
            }
        }
        buf.append(d)
    }

    // 读一行（不含结尾的 \r\n）
    func line() async throws -> String {
        while true {
            if let i = buf.firstIndex(of: 10) {
                var l = buf.subdata(in: buf.startIndex..<i)
                buf.removeSubrange(buf.startIndex...i)
                if l.last == 13 { l.removeLast() }
                return String(decoding: l, as: UTF8.self)
            }
            try await fill()
        }
    }

    func bytes(_ n: Int) async throws -> Data {
        while buf.count < n { try await fill() }
        let d = buf.subdata(in: buf.startIndex..<(buf.startIndex + n))
        buf.removeSubrange(buf.startIndex..<(buf.startIndex + n))
        return d
    }
}

// MARK: IMAP
struct IMAPResp {
    var head: String          // 一行；其中的 {n} 字面量已被替换成 <LIT0>、<LIT1>…
    var lits: [Data]
}

struct IMAPMsg {
    var uid = 0
    var flags: [String] = []
    var date = Date()
    var raw = Data()
    var seen: Bool { flags.contains { $0.lowercased() == "\\seen" } }
    var flagged: Bool { flags.contains { $0.lowercased() == "\\flagged" } }
}

struct IMAPFolder {
    var raw: String           // 服务器上的原始名字（修改版 UTF-7），命令里用它
    var flags: [String]
    var name: String { MailMIME.utf7Decode(raw) }
    func has(_ f: String) -> Bool { flags.contains { $0.lowercased() == f.lowercased() } }
}

final class IMAPClient {
    private let s: MailStream
    private var n = 0
    var caps = ""
    var validity = 0
    var exists = 0
    var uidnext = 0
    var debug = ""        // 最近一次取信时服务器回应的开头，排查用

    init(host: String, port: Int) {
        s = MailStream(host: host, port: port, tls: true)
    }

    func close() { s.close() }

    static func quote(_ x: String) -> String {
        "\"" + x.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func connect(user: String, pass: String) async throws {
        let g = try await s.line()
        guard g.hasPrefix("* OK") || g.hasPrefix("* PREAUTH") else { throw MailError("服务器没有正常响应：" + String(g.prefix(80))) }
        guard user.allSatisfy({ $0.isASCII }), pass.allSatisfy({ $0.isASCII }) else { throw MailError("账号或密码里有非英文字符，请检查是否复制了多余内容。") }
        let r = try await cmd("LOGIN \(Self.quote(user)) \(Self.quote(pass))", allowFail: true)
        if !r.ok { throw MailError(Self.explain(r.status)) }
        let c = try await cmd("CAPABILITY")
        caps = c.untagged.map { $0.head }.joined(separator: " ").uppercased()
        // 网易系邮箱（163 / 126 / yeah）不发这条 ID 命令，会以「Unsafe Login」拒绝 SELECT；其他服务器无害
        _ = try? await cmd("ID (\"name\" \"OSVIA\" \"version\" \"1.0\" \"vendor\" \"OSVIA\" \"os\" \"iOS\")", allowFail: true)
    }

    static func explain(_ status: String) -> String {
        let t = status.lowercased()
        if t.contains("authenticationfailed") || t.contains("invalid credentials") || t.contains("login fail") || t.contains("auth") || t.contains("password") || t.contains("密码") || t.contains("授权码") {
            return "登录被拒绝：请确认填的是「应用专用密码 / 授权码」而不是登录密码，并且已在邮箱设置里开启 IMAP。"
        }
        if t.contains("unsafe") { return "服务器认为这是不安全的登录。请在邮箱网页设置里开启 IMAP 并使用授权码。" }
        return "登录失败：" + String(status.prefix(100))
    }

    struct Result {
        var ok: Bool
        var status: String
        var untagged: [IMAPResp]
    }

    // 发一条命令，读到带标签的结果行为止；沿途收集「*」开头的数据，字面量 {n} 按字节读完
    @discardableResult
    func cmd(_ c: String, allowFail: Bool = false) async throws -> Result {
        n += 1
        let tag = "O\(n)"
        try await s.write("\(tag) \(c)\r\n")
        var out: [IMAPResp] = []
        while true {
            var l = try await s.line()
            if l.hasPrefix(tag + " ") {
                let rest = String(l.dropFirst(tag.count + 1))
                let ok = rest.hasPrefix("OK")
                if !ok && !allowFail { throw MailError(String(rest.prefix(120))) }
                return Result(ok: ok, status: rest, untagged: out)
            }
            guard l.hasPrefix("*") else { continue }
            var resp = IMAPResp(head: "", lits: [])
            while true {
                if let m = l.range(of: "\\{(\\d+)\\+?\\}$", options: .regularExpression) {
                    let num = Int(l[m].dropFirst().dropLast().replacingOccurrences(of: "+", with: "")) ?? 0
                    resp.head += String(l[l.startIndex..<m.lowerBound]) + "<LIT\(resp.lits.count)>"
                    resp.lits.append(try await s.bytes(num))
                    l = try await s.line()
                } else {
                    resp.head += l
                    break
                }
            }
            out.append(resp)
        }
    }

    // MARK: 文件夹
    func list() async throws -> [IMAPFolder] {
        let r = try await cmd("LIST \"\" \"*\"")
        var out: [IMAPFolder] = []
        for u in r.untagged {
            guard u.head.uppercased().hasPrefix("* LIST") || u.head.uppercased().hasPrefix("* XLIST"),
                  let fl = u.head.range(of: "\\(([^)]*)\\)", options: .regularExpression) else { continue }
            let flags = u.head[fl].dropFirst().dropLast().split(separator: " ").map(String.init)
            var rest = String(u.head[fl.upperBound...]).trimmingCharacters(in: .whitespaces)
            // 分隔符："/" 或 NIL
            if rest.hasPrefix("\"") {
                if let e = rest.dropFirst().firstIndex(of: "\"") { rest = String(rest[rest.index(after: e)...]) }
            } else if rest.uppercased().hasPrefix("NIL") { rest = String(rest.dropFirst(3)) }
            rest = rest.trimmingCharacters(in: .whitespaces)
            var name = rest
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            } else if name.hasPrefix("<LIT0>"), let d = u.lits.first {
                name = String(decoding: d, as: UTF8.self)
            }
            if flags.contains(where: { $0.lowercased() == "\\noselect" }) { continue }
            if !name.isEmpty { out.append(IMAPFolder(raw: name, flags: flags)) }
        }
        return out
    }

    func select(_ folder: String) async throws {
        let r = try await cmd("SELECT \(Self.quote(folder))")
        for u in r.untagged {
            let h = u.head
            if let m = h.range(of: "\\[UIDVALIDITY (\\d+)\\]", options: .regularExpression) {
                validity = Int(h[m].filter { $0.isNumber }) ?? 0
            }
            if let m = h.range(of: "\\[UIDNEXT (\\d+)\\]", options: .regularExpression) {
                uidnext = Int(h[m].filter { $0.isNumber }) ?? 0
            }
            if h.hasSuffix(" EXISTS"), let v = Int(h.dropFirst(2).dropLast(7)) { exists = v }
        }
    }

    func create(_ folder: String) async throws {
        _ = try await cmd("CREATE \(Self.quote(folder))", allowFail: true)
    }

    // MARK: 取信
    // 取最近 count 封（按序号，从最新往回）；每封只取前 maxBytes 字节，够解析头部和正文开头
    func fetchRecent(count: Int, maxBytes: Int = 9000) async throws -> [IMAPMsg] {
        guard exists > 0 else { return [] }
        let from = max(1, exists - count + 1)
        let r = try await cmd("FETCH \(from):\(exists) (UID FLAGS INTERNALDATE BODY.PEEK[]<0.\(maxBytes)>)")
        debug = r.untagged.prefix(2).map { String($0.head.prefix(200)) }.joined(separator: " | ")
        return r.untagged.compactMap(parseFetch).sorted { $0.uid > $1.uid }
    }

    func fetchBody(uid: Int, maxBytes: Int = 300_000) async throws -> IMAPMsg? {
        let r = try await cmd("UID FETCH \(uid) (UID FLAGS INTERNALDATE BODY.PEEK[]<0.\(maxBytes)>)")
        return r.untagged.compactMap(parseFetch).first
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return f
    }()

    private func parseFetch(_ u: IMAPResp) -> IMAPMsg? {
        let h = u.head
        guard h.contains(" FETCH "), let uidR = h.range(of: "UID (\\d+)", options: .regularExpression) else { return nil }
        var m = IMAPMsg()
        m.uid = Int(h[uidR].dropFirst(4)) ?? 0
        if let f = h.range(of: "FLAGS \\(([^)]*)\\)", options: .regularExpression) {
            m.flags = h[f].dropFirst(7).dropLast().split(separator: " ").map(String.init)
        }
        if let d = h.range(of: "INTERNALDATE \"([^\"]+)\"", options: .regularExpression) {
            let t = String(h[d]).dropFirst(14).dropLast()
            m.date = Self.dateFmt.date(from: String(t).trimmingCharacters(in: .whitespaces)) ?? Date()
        }
        m.raw = u.lits.first ?? Data()
        return m.uid > 0 ? m : nil
    }

    // MARK: 整理
    func addFlag(uid: Int, _ flag: String) async throws {
        _ = try await cmd("UID STORE \(uid) +FLAGS.SILENT (\(flag))")
    }

    func removeFlag(uid: Int, _ flag: String) async throws {
        _ = try await cmd("UID STORE \(uid) -FLAGS.SILENT (\(flag))")
    }

    // 移动：有 MOVE 就直接移；否则「复制 + 标记删除 + 只清掉这一封」
    func move(uid: Int, to folder: String) async throws {
        if caps.contains("MOVE") {
            _ = try await cmd("UID MOVE \(uid) \(Self.quote(folder))")
            return
        }
        _ = try await cmd("UID COPY \(uid) \(Self.quote(folder))")
        try await addFlag(uid: uid, "\\Deleted")
        if caps.contains("UIDPLUS") {
            _ = try await cmd("UID EXPUNGE \(uid)", allowFail: true)
        } else {
            // 没有 UIDPLUS 时 EXPUNGE 会清掉所有带删除标记的邮件；只有确认只有这一封才执行，避免误删
            let r = try await cmd("UID SEARCH DELETED", allowFail: true)
            let ids = r.untagged.first { $0.head.uppercased().hasPrefix("* SEARCH") }?.head.split(separator: " ").dropFirst(2).compactMap { Int($0) } ?? []
            if ids == [uid] { _ = try await cmd("EXPUNGE", allowFail: true) }
        }
    }

    func logout() async {
        _ = try? await cmd("LOGOUT", allowFail: true)
        s.close()
    }
}

// MARK: SMTP
final class SMTPClient {
    private let s: MailStream
    private let startTLS: Bool

    init(host: String, port: Int, startTLS: Bool) {
        self.startTLS = startTLS
        s = MailStream(host: host, port: port, tls: !startTLS)
    }

    // 读一条（可能多行）回复，返回（状态码，全文）
    private func reply() async throws -> (Int, String) {
        var text = ""
        while true {
            let l = try await s.line()
            text += l + "\n"
            if l.count >= 4, l[l.index(l.startIndex, offsetBy: 3)] == " ", let c = Int(l.prefix(3)) { return (c, text) }
            if l.count == 3, let c = Int(l) { return (c, text) }
        }
    }

    private func send(_ c: String, expect: [Int]) async throws -> String {
        try await s.write(c + "\r\n")
        let (code, text) = try await reply()
        guard expect.contains(code) else { throw MailError("发信服务器拒绝：" + String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return text
    }

    func deliver(user: String, pass: String, from: String, to: [String], message: Data) async throws {
        defer { s.close() }
        let (gc, gt) = try await reply()
        guard gc == 220 else { throw MailError("发信服务器没有正常响应：" + String(gt.prefix(80))) }
        var ehlo = try await send("EHLO osvia.local", expect: [250])
        if startTLS {
            _ = try await send("STARTTLS", expect: [220])
            s.startTLS()
            ehlo = try await send("EHLO osvia.local", expect: [250])
        }
        let up = ehlo.uppercased()
        if up.contains("AUTH") && up.contains("PLAIN") {
            let tok = Data(("\0" + user + "\0" + pass).utf8).base64EncodedString()
            try await s.write("AUTH PLAIN \(tok)\r\n")
            let (c, t) = try await reply()
            guard c == 235 else { throw MailError("发信登录被拒绝：" + IMAPClient.explain(t)) }
        } else {
            _ = try await send("AUTH LOGIN", expect: [334])
            _ = try await send(Data(user.utf8).base64EncodedString(), expect: [334])
            _ = try await send(Data(pass.utf8).base64EncodedString(), expect: [235])
        }
        _ = try await send("MAIL FROM:<\(from)>", expect: [250])
        for r in to { _ = try await send("RCPT TO:<\(r)>", expect: [250, 251]) }
        _ = try await send("DATA", expect: [354])
        try await s.write(Self.stuff(message))
        let (c, t) = try await reply()
        guard c == 250 else { throw MailError("发送失败：" + String(t.prefix(120))) }
        _ = try? await send("QUIT", expect: [221])
    }

    // 行首的「.」要双写；结尾补 \r\n.\r\n
    private static func stuff(_ d: Data) -> Data {
        let t = String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        var lines = t.components(separatedBy: "\r\n")
        for i in lines.indices where lines[i].hasPrefix(".") { lines[i] = "." + lines[i] }
        var s = lines.joined(separator: "\r\n")
        if !s.hasSuffix("\r\n") { s += "\r\n" }
        s += ".\r\n"
        return Data(s.utf8)
    }
}

// MARK: 生成邮件正文
enum MailBuilder {
    private static func encWord(_ s: String) -> String {
        if s.allSatisfy({ $0.isASCII }) { return s }
        // 每个编码词不超过 75 字符：UTF-8 取 42 字节以内再 base64
        var words: [String] = []
        var cur = Data()
        for ch in s {
            let b = Data(String(ch).utf8)
            if cur.count + b.count > 42 { words.append(cur.base64EncodedString()); cur = Data() }
            cur.append(b)
        }
        if !cur.isEmpty { words.append(cur.base64EncodedString()) }
        return words.map { "=?UTF-8?B?\($0)?=" }.joined(separator: "\r\n ")
    }

    private static func rfc5322Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }

    static func build(from: String, fromName: String, to: [String], subject: String, body: String, inReplyTo: String = "", references: String = "") -> Data {
        let domain = from.split(separator: "@").last.map(String.init) ?? "osvia.local"
        var h: [String] = []
        let name = fromName.isEmpty ? "" : (fromName.allSatisfy { $0.isASCII } ? "\"\(fromName.replacingOccurrences(of: "\"", with: ""))\" " : encWord(fromName) + " ")
        h.append("From: \(name)<\(from)>")
        h.append("To: " + to.joined(separator: ", "))
        h.append("Subject: " + encWord(subject.replacingOccurrences(of: "\n", with: " ")))
        h.append("Date: " + rfc5322Date())
        h.append("Message-ID: <\(UUID().uuidString.lowercased())@\(domain)>")
        if !inReplyTo.isEmpty { h.append("In-Reply-To: " + inReplyTo) }
        let refs = [references, inReplyTo].filter { !$0.isEmpty }.joined(separator: " ")
        if !refs.isEmpty { h.append("References: " + refs) }
        h.append("MIME-Version: 1.0")
        h.append("Content-Type: text/plain; charset=UTF-8")
        h.append("Content-Transfer-Encoding: base64")
        let b64 = Data(body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return Data((h.joined(separator: "\r\n") + "\r\n\r\n" + b64 + "\r\n").utf8)
    }
}
