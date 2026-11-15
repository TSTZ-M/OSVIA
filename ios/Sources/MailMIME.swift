import Foundation

// MARK: 邮件解析：RFC 2047 头部编码、MIME 多段、base64 / quoted-printable、各种字符集（含 GBK / GB18030 / Big5）、HTML 转文字
struct ParsedMail {
    var headers: [String: String] = [:]      // 键小写，值已解码
    var text = ""
    var attachments: [String] = []
    func h(_ k: String) -> String { headers[k] ?? "" }
}

enum MailMIME {
    // MARK: 字符集
    static func encoding(_ name: String) -> String.Encoding {
        let n = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if n.isEmpty || n == "utf-8" || n == "utf8" || n == "us-ascii" || n == "ascii" { return .utf8 }
        if n == "gb2312" || n == "gbk" || n == "gb18030" || n == "x-gbk" || n == "cp936" {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        if n == "big5" || n == "big5-hkscs" {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        }
        if n == "iso-8859-1" || n == "latin1" { return .isoLatin1 }
        if n == "windows-1252" || n == "cp1252" { return .windowsCP1252 }
        if n == "shift_jis" || n == "shift-jis" || n == "sjis" { return .shiftJIS }
        if n == "euc-jp" { return .japaneseEUC }
        let cf = CFStringConvertIANACharSetNameToEncoding(n as CFString)
        if cf != kCFStringEncodingInvalidId {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        return .utf8
    }

    static func decode(_ d: Data, charset: String) -> String {
        if let s = String(data: d, encoding: encoding(charset)) { return s }
        if let s = String(data: d, encoding: .utf8) { return s }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: 头部
    // 把「=?utf-8?B?....?=」解成文字；相邻的编码词之间的空白要去掉
    static func decodeHeader(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "(\\?=)\\s+(=\\?)", with: "$1$2", options: .regularExpression)
        guard s.contains("=?"), let re = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let cs = ns.substring(with: m.range(at: 1)).components(separatedBy: "*")[0]
            let kind = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))
            var data: Data?
            if kind == "B" {
                data = Data(base64Encoded: pad(payload))
            } else {
                data = qpDecode(payload.replacingOccurrences(of: "_", with: " "), header: true)
            }
            out += data.map { decode($0, charset: cs) } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func pad(_ s: String) -> String {
        let t = s.filter { !$0.isWhitespace }
        let r = t.count % 4
        return r == 0 ? t : t + String(repeating: "=", count: 4 - r)
    }

    static func qpDecode(_ s: String, header: Bool = false) -> Data {
        var out = Data()
        let b = Array(s.utf8)
        var i = 0
        func hex(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 65...70: return c - 55
            case 97...102: return c - 87
            default: return nil
            }
        }
        while i < b.count {
            let c = b[i]
            if c == 61 { // =
                if i + 1 < b.count, b[i + 1] == 10 { i += 2; continue }
                if i + 2 < b.count, b[i + 1] == 13, b[i + 2] == 10 { i += 3; continue }
                if i + 2 < b.count, let h = hex(b[i + 1]), let l = hex(b[i + 2]) {
                    out.append(h << 4 | l)
                    i += 3
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }

    // 拆头部和正文，返回（头部字典，原始头部字段，正文字节）
    static func split(_ data: Data) -> (headers: [String: String], body: Data) {
        let bytes = [UInt8](data)
        var sep = -1
        var sepLen = 0
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 13, i + 3 < bytes.count, bytes[i + 1] == 10, bytes[i + 2] == 13, bytes[i + 3] == 10 { sep = i; sepLen = 4; break }
            if bytes[i] == 10, bytes[i + 1] == 10 { sep = i; sepLen = 2; break }
            i += 1
        }
        let headData = sep >= 0 ? Data(bytes[0..<sep]) : data
        let body = sep >= 0 ? Data(bytes[(sep + sepLen)...]) : Data()
        let raw = String(decoding: headData, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        var fields: [String] = []
        for line in raw.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !fields.isEmpty {
                fields[fields.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if !line.isEmpty {
                fields.append(line)
            }
        }
        var h: [String: String] = [:]
        for f in fields {
            guard let c = f.firstIndex(of: ":") else { continue }
            let k = f[..<c].lowercased()
            let v = f[f.index(after: c)...].trimmingCharacters(in: .whitespaces)
            if h[k] == nil { h[k] = v }
        }
        return (h, body)
    }

    // 「text/plain; charset="gbk"; name=x」→ 主值和参数
    static func params(_ v: String) -> (main: String, params: [String: String]) {
        var parts: [String] = []
        var cur = ""
        var q = false
        for c in v {
            if c == "\"" { q.toggle(); cur.append(c) } else if c == ";" && !q { parts.append(cur); cur = "" } else { cur.append(c) }
        }
        parts.append(cur)
        let main = (parts.first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        var p: [String: String] = [:]
        for s in parts.dropFirst() {
            guard let e = s.firstIndex(of: "=") else { continue }
            let k = s[..<e].trimmingCharacters(in: .whitespaces).lowercased()
            let val = s[s.index(after: e)...].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            p[k] = val
        }
        return (main, p)
    }

    // MARK: 解析整封邮件（允许被截断：多段只处理已经收到的部分）
    static func parse(_ data: Data) -> ParsedMail {
        let (h, body) = split(data)
        var m = ParsedMail()
        for (k, v) in h { m.headers[k] = decodeHeader(v) }
        var texts: [String] = []
        var htmls: [String] = []
        walk(headers: h, body: body, texts: &texts, htmls: &htmls, attachments: &m.attachments, depth: 0)
        var t = texts.joined(separator: "\n\n")
        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { t = htmls.map { htmlToText($0) }.joined(separator: "\n\n") }
        m.text = tidy(t)
        return m
    }

    private static func walk(headers h: [String: String], body: Data, texts: inout [String], htmls: inout [String], attachments: inout [String], depth: Int) {
        guard depth < 6 else { return }
        let ct = params(h["content-type"] ?? "text/plain")
        let disp = params(h["content-disposition"] ?? "")
        if ct.main.hasPrefix("multipart/"), let boundary = ct.params["boundary"] {
            let alt = ct.main == "multipart/alternative"
            var altText: [String] = []
            var altHtml: [String] = []
            for part in splitParts(body, boundary: boundary) {
                let (ph, pb) = split(part)
                var t: [String] = []
                var hh: [String] = []
                walk(headers: ph, body: pb, texts: &t, htmls: &hh, attachments: &attachments, depth: depth + 1)
                if alt { altText += t; altHtml += hh } else { texts += t; htmls += hh }
            }
            if alt {
                if !altText.isEmpty { texts += altText } else { htmls += altHtml }
            }
            return
        }
        let name = disp.params["filename"] ?? ct.params["name"] ?? ""
        if disp.main == "attachment" || (!name.isEmpty && !ct.main.hasPrefix("text/")) || (!ct.main.hasPrefix("text/") && ct.main != "message/rfc822") {
            attachments.append(name.isEmpty ? ct.main : decodeHeader(name))
            return
        }
        guard ct.main == "text/plain" || ct.main == "text/html" || ct.main.isEmpty else { return }
        var raw = body
        let cte = (h["content-transfer-encoding"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if cte == "base64" {
            let s = String(decoding: body, as: UTF8.self)
            // 被截断的 base64：只解码完整的 4 字符组
            var t = s.filter { !$0.isWhitespace }
            t = String(t.prefix(t.count / 4 * 4))
            raw = Data(base64Encoded: t) ?? Data()
        } else if cte == "quoted-printable" {
            raw = qpDecode(String(decoding: body, as: UTF8.self))
        }
        let s = decode(raw, charset: ct.params["charset"] ?? "utf-8")
        if ct.main == "text/html" { htmls.append(s) } else { texts.append(s) }
    }

    private static func splitParts(_ body: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8)
        var parts: [Data] = []
        var idx = body.startIndex
        var starts: [Int] = []
        while let r = body.range(of: marker, in: idx..<body.endIndex) {
            starts.append(r.lowerBound)
            idx = r.upperBound
        }
        for (i, s) in starts.enumerated() {
            var from = s + marker.count
            // 结束标记 --boundary--
            if from + 1 < body.endIndex, body[from] == 45, body[from + 1] == 45 { break }
            // 跳过这一行剩下的内容
            while from < body.endIndex, body[from] != 10 { from += 1 }
            from += 1
            let end = i + 1 < starts.count ? starts[i + 1] : body.endIndex
            if from < end { parts.append(body.subdata(in: from..<end)) }
        }
        return parts
    }

    // MARK: HTML → 文字
    static func htmlToText(_ html: String) -> String {
        var s = html
        for pat in ["<style[\\s\\S]*?</style>", "<script[\\s\\S]*?</script>", "<head[\\s\\S]*?</head>", "<!--[\\s\\S]*?-->"] {
            s = s.replacingOccurrences(of: pat, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br[^>]*>|</p>|</div>|</tr>|</h[1-6]>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return Web.decodeEntities(s)
    }

    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{00A0}", with: " ")
        t = t.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 地址 「名字 <a@b.com>」
    static func address(_ raw: String) -> (name: String, addr: String) {
        let s = decodeHeader(raw).trimmingCharacters(in: .whitespaces)
        if let lt = s.lastIndex(of: "<"), let gt = s.lastIndex(of: ">"), lt < gt {
            let addr = String(s[s.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces)
            let name = String(s[..<lt]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (name, addr)
        }
        return ("", s)
    }

    // MARK: IMAP 文件夹名（修改版 UTF-7）解码
    static func utf7Decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "&" else { out.append(c); continue }
            var b64 = ""
            while let n = it.next(), n != "-" { b64.append(n) }
            if b64.isEmpty { out.append("&"); continue }
            let std = b64.replacingOccurrences(of: ",", with: "/")
            if let d = Data(base64Encoded: pad(std)), let u = String(data: d, encoding: .utf16BigEndian) { out += u }
        }
        return out
    }
}
