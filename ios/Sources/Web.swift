import Foundation
import PDFKit

// 读网页正文：优先 <article>/<main>，去掉导航、页脚、脚本，还原实体，按段落保留换行。
// 读不了的（登录墙、纯脚本渲染）返回空，调用方会告诉模型「没读到」。
enum Web {
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func read(_ u: URL, limit: Int) async -> (title: String, text: String) {
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue("text/html,application/xhtml+xml,application/json,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (d, resp) = try? await URLSession.shared.data(for: req) else { return ("", "") }
        let ctype = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if ctype.contains("pdf") {
            let t = PDFDocument(data: d)?.string ?? ""
            return ("", String(t.prefix(limit)))
        }
        let head = String(decoding: d.prefix(2048), as: UTF8.self).lowercased()
        let gb = ctype.contains("charset=gb") || head.contains("charset=gb") || head.contains("charset=\"gb")
        let body = d.prefix(450_000)
        let raw: String
        if gb {
            let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            raw = String(data: Data(body), encoding: enc) ?? String(decoding: body, as: UTF8.self)
        } else {
            raw = String(decoding: body, as: UTF8.self)
        }
        let plain = (ctype.contains("json") || ctype.contains("text/plain") || ctype.contains("markdown") || (ctype.contains("xml") && !ctype.contains("html")))
        if plain { return ("", String(raw.prefix(limit))) }
        return clean(raw, limit: limit)
    }

    static func clean(_ html: String, limit: Int) -> (title: String, text: String) {
        var title = ""
        if let r = html.range(of: "<title[^>]*>[\\s\\S]*?</title>", options: [.regularExpression, .caseInsensitive]) {
            title = decodeEntities(String(html[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var s = html
        for tag in ["article", "main"] {
            if let r = s.range(of: "<\(tag)[\\s\\S]*?</\(tag)>", options: [.regularExpression, .caseInsensitive]), s[r].count > 800 {
                s = String(s[r])
                break
            }
        }
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<noscript[\\s\\S]*?</noscript>", "<svg[\\s\\S]*?</svg>",
                  "<nav[\\s\\S]*?</nav>", "<header[\\s\\S]*?</header>", "<footer[\\s\\S]*?</footer>", "<aside[\\s\\S]*?</aside>",
                  "<form[\\s\\S]*?</form>", "<!--[\\s\\S]*?-->"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "</(p|div|li|h[1-6]|tr|section|article)>|<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, String(s.prefix(limit)))
    }

    static func decodeEntities(_ s: String) -> String {
        var t = s
        for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
                       ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&ldquo;", "“"), ("&rdquo;", "”"),
                       ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        guard t.contains("&#"), let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return t }
        let ns = t as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = ns.substring(with: m.range(at: 1)) == "x"
            let num = ns.substring(with: m.range(at: 2))
            if let v = UInt32(num, radix: isHex ? 16 : 10), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
