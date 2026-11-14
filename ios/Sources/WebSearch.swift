import Foundation

// MARK: 联网搜索：手机直接请求必应并提取标题、摘要、链接。不需要任何密钥或服务器，所有用户通用。
// 先试网页版，网页格式变了或被拦截时改试 RSS 版（格式稳定得多），国内站点与国际站点依次尝试。
enum WebSearch {
    struct Hit {
        let title: String
        let url: String
        let snippet: String
    }

    private static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func search(_ q: String) async -> [Hit] {
        let key = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let enc = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        for host in ["https://cn.bing.com", "https://www.bing.com"] {
            if let html = await get("\(host)/search?q=\(enc)&setlang=zh-Hans") {
                let hits = parse(html)
                if !hits.isEmpty { return hits }
            }
            if let xml = await get("\(host)/search?format=rss&q=\(enc)&setlang=zh-Hans") {
                let hits = parseRSS(xml)
                if !hits.isEmpty { return hits }
            }
        }
        return []
    }

    private static func get(_ s: String) async -> String? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    static func parse(_ html: String) -> [Hit] {
        var out: [Hit] = []
        for block in html.components(separatedBy: "<li class=\"b_algo\"").dropFirst() {
            guard let a = match(block, "<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>") else { continue }
            let p = match(block, "<p[^>]*>([\\s\\S]*?)</p>")
            let title = strip(a[1])
            if title.isEmpty { continue }
            out.append(Hit(title: title, url: real(a[0]), snippet: p.map { strip($0[0]) } ?? ""))
            if out.count >= 5 { break }
        }
        return out
    }

    // RSS 版：<item><title/><link/><description/></item>，链接就是真实地址
    static func parseRSS(_ xml: String) -> [Hit] {
        var out: [Hit] = []
        for block in xml.components(separatedBy: "<item>").dropFirst() {
            guard let t = match(block, "<title>([\\s\\S]*?)</title>"),
                  let l = match(block, "<link>([\\s\\S]*?)</link>") else { continue }
            let d = match(block, "<description>([\\s\\S]*?)</description>")
            let title = rss(t[0])
            if title.isEmpty { continue }
            out.append(Hit(title: title, url: rss(l[0]), snippet: d.map { rss($0[0]) } ?? ""))
            if out.count >= 5 { break }
        }
        return out
    }

    // 给模型看的搜索结果文本
    static func format(_ hits: [Hit], numbers: [Int]? = nil) -> String {
        hits.enumerated().map { i, h in
            let n = (numbers != nil && i < numbers!.count) ? numbers![i] : i + 1
            return "[\(n)] \(h.title)\n\(String(h.snippet.prefix(220)))\n\(h.url)"
        }.joined(separator: "\n\n")
    }

    // 哪些问题值得先联网查一查（本机小模型不会自己决定搜索，所以先用关键词判断）
    static func needs(_ t: String) -> Bool {
        guard t.count <= 120 else { return false }
        let low = t.lowercased()
        let ks = ["最新", "新闻", "价格", "多少钱", "股价", "汇率", "天气", "比分", "票房", "热搜", "行情", "发布会", "搜索", "搜一下", "查一下", "查查", "上网", "联网",
                  "实时", "金价", "油价", "股票", "基金", "赛程", "榜单",
                  "latest", "news", "price", "weather", "score", "search"]
        return ks.contains { low.contains($0) }
    }

    private static func match(_ s: String, _ p: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: p),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }

    private static func strip(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&#0183;", "·")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // RSS 的文字可能包在 CDATA 里，也可能是被转义的 HTML：先去 CDATA，再还原实体、去标签
    private static func rss(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        t = t.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        return strip(t)
    }

    // 必应的结果链接常是跳转链接，真实地址在参数 u 里（a1 + base64）
    private static func real(_ raw: String) -> String {
        let u = raw.replacingOccurrences(of: "&amp;", with: "&")
        guard u.contains("bing.com/ck/a"), let c = URLComponents(string: u),
              var v = c.queryItems?.first(where: { $0.name == "u" })?.value, v.hasPrefix("a1") else { return u }
        v.removeFirst(2)
        var b = v.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let s = String(data: d, encoding: .utf8) else { return u }
        return s
    }
}
