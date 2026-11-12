import Foundation
import UIKit

// 一键添加的常用连接器：全部免费、无需密钥
struct ConnectorPreset: Identifiable {
    var id: String { name }
    let name: String
    let about: String
    let kind: String
    let url: String
    let hint: String
    let sample: String
}

// 连接器：连接本机已有的 App（快捷指令、Scriptable、任意网址方案）或调用网络接口。
// 网络接口当场返回结果；快捷指令、Scriptable 运行完会自动回到本 App，并把结果显示在对话里。
enum Connectors {
    static let presets: [ConnectorPreset] = [
        ConnectorPreset(name: "币安价格", about: "现货最新价，输入交易对", kind: "http",
                        url: "https://data-api.binance.vision/api/v3/ticker/price?symbol={{input}}",
                        hint: "交易对，如 BTCUSDT", sample: "BTCUSDT"),
        ConnectorPreset(name: "CoinGecko币价", about: "多个币种美元价与 24 小时涨跌", kind: "http",
                        url: "https://api.coingecko.com/api/v3/simple/price?ids={{input}}&vs_currencies=usd&include_24hr_change=true",
                        hint: "币种全名小写，用逗号分隔，如 bitcoin,solana", sample: "bitcoin,solana"),
        ConnectorPreset(name: "DexScreener搜币", about: "搜链上代币：价格、24h 涨跌、流动性、FDV（取流动性最大的 5 个池子）", kind: "http",
                        url: "https://api.dexscreener.com/latest/dex/search?q={{input}}",
                        hint: "代币名称或合约地址", sample: "PEPE"),
        ConnectorPreset(name: "天气", about: "城市当前天气", kind: "http",
                        url: "https://wttr.in/{{input}}?format=3&lang=zh",
                        hint: "城市名，如 上海", sample: "上海")
    ]

    // 给 Scriptable 脚本用的回调模板：读取传入内容，处理后把结果送回 TSTZ Bot
    static let scriptableTemplate = """
    // TSTZ Bot 连接器模板
    const input = args.queryParameters.input || args.shortcutParameter || "";
    const callback = args.queryParameters.callback;
    let result = "收到：" + input; // 在这里写你的处理逻辑，把结果放进 result
    if (callback) {
      Safari.open(callback + "&result=" + encodeURIComponent(String(result)));
    }
    Script.complete();
    """

    static func all() -> [Row] { DB.shared.rows("SELECT * FROM connector ORDER BY id") }

    static func add(name: String, kind: String, url: String, method: String = "GET", headers: String = "", body: String = "") {
        DB.shared.run("INSERT INTO connector(name,kind,url,method,headers,body) VALUES(?,?,?,?,?,?)", [name, kind, url, method, headers, body])
    }

    static func addPreset(_ p: ConnectorPreset) {
        guard !all().contains(where: { $0.s("name") == p.name }) else { return }
        add(name: p.name, kind: p.kind, url: p.url)
        DB.shared.setKV("connhint." + p.name, p.hint)
        DB.shared.setKV("connsample." + p.name, p.sample)
    }

    static func remove(_ id: Int) { DB.shared.run("DELETE FROM connector WHERE id=?", [id]) }

    static func hint(_ name: String) -> String { DB.shared.kv("connhint." + name) ?? "" }

    static func kindName(_ k: String) -> String {
        switch k {
        case "shortcut": return "快捷指令"
        case "scriptable": return "Scriptable 脚本"
        case "url": return "其他 App"
        default: return "网络接口"
        }
    }

    static func icon(_ k: String) -> String {
        switch k {
        case "shortcut": return "square.stack.3d.up"
        case "scriptable": return "curlybraces"
        case "url": return "arrow.up.forward.app"
        default: return "network"
        }
    }

    // 名称精确匹配优先，其次忽略大小写、再其次包含（小模型常把名字写得不完全一致）
    static func find(_ name: String) -> Row? {
        let list = all()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = list.first(where: { $0.s("name") == n }) { return c }
        if let c = list.first(where: { $0.s("name").lowercased() == n.lowercased() }) { return c }
        return list.first(where: { !n.isEmpty && ($0.s("name").contains(n) || n.contains($0.s("name"))) })
    }

    // 对话里直接说「用 币安价格 查 BTCUSDT」：确定性解析，不靠小模型猜
    static func match(_ text: String) -> (Row, String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = ["使用", "调用", "运行", "执行", "通过", "用", "让"]
        guard let trig = lead.first(where: { t.hasPrefix($0) }) else { return nil }
        let list = all().sorted { $0.s("name").count > $1.s("name").count }
        for c in list {
            let n = c.s("name")
            guard !n.isEmpty, let r = t.range(of: n, options: .caseInsensitive) else { continue }
            var rest = t
            rest.removeSubrange(r)
            rest = String(rest.dropFirst(trig.count))
            var s = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。"))
            var changed = true
            while changed {
                changed = false
                for w in ["查询一下", "查一下", "查询", "处理一下", "处理", "查", "来", "的"] where s.hasPrefix(w) {
                    s = String(s.dropFirst(w.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。"))
                    changed = true
                }
            }
            return (c, s)
        }
        return nil
    }

    private static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    // 放进 JSON 字符串里的转义（换行、引号、反斜杠都处理）
    private static func jsonEscape(_ s: String) -> String {
        guard let d = try? JSONEncoder().encode(s), var t = String(data: d, encoding: .utf8), t.count >= 2 else { return s }
        t.removeFirst()
        t.removeLast()
        return t
    }

    private static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private static func usd(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "$%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // DexScreener 搜索结果：压缩成 5 个流动性最大的池子
    private static func dexSummary(_ obj: Any) -> String? {
        guard let o = obj as? [String: Any], let pairs = o["pairs"] as? [[String: Any]], !pairs.isEmpty else { return nil }
        func liq(_ p: [String: Any]) -> Double { num((p["liquidity"] as? [String: Any])?["usd"]) ?? 0 }
        let top = pairs.sorted { liq($0) > liq($1) }.prefix(5)
        var lines: [String] = []
        for p in top {
            let base = (p["baseToken"] as? [String: Any])?["symbol"] as? String ?? "?"
            let quote = (p["quoteToken"] as? [String: Any])?["symbol"] as? String ?? "?"
            let chain = p["chainId"] as? String ?? ""
            let dex = p["dexId"] as? String ?? ""
            let price = p["priceUsd"] as? String ?? "-"
            let change = num((p["priceChange"] as? [String: Any])?["h24"]).map { String(format: "%+.1f%%", $0) } ?? "-"
            let fdv = num(p["fdv"]).map { usd($0) } ?? "-"
            lines.append("\(base)/\(quote) · \(chain)/\(dex)\n价格 $\(price) · 24h \(change) · 流动性 \(usd(liq(p))) · FDV \(fdv)")
        }
        return lines.joined(separator: "\n\n")
    }

    // 接口返回：JSON 美化（DexScreener 另做摘要），网页去标签，统一截断
    private static func format(_ d: Data, limit: Int) -> String {
        if d.count <= 400_000, let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
            if let s = dexSummary(obj) { return String(s.prefix(limit)) }
            if JSONSerialization.isValidJSONObject(obj),
               let p = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                return String(String(decoding: p, as: UTF8.self).prefix(limit))
            }
        }
        var s = String(decoding: d.prefix(300_000), as: UTF8.self)
        if s.contains("<") {
            s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    // limit：返回给模型用时要短（默认 1200 字），直接显示在对话里时用 3000 字
    static func run(_ name: String, _ input: String, limit: Int = 1200) async -> String {
        guard let c = find(name) else { return "没有找到名为「\(name)」的连接器" }
        let cname = c.s("name")
        let kind = c.s("kind")
        let target = c.s("url")
        let cb = "osvia://connector?name=\(enc(cname))"
        var link = ""
        switch kind {
        case "shortcut":
            link = "shortcuts://x-callback-url/run-shortcut?name=\(enc(target))"
                + (input.isEmpty ? "" : "&input=text&text=\(enc(input))")
                + "&x-success=\(enc(cb + "&ok=1"))&x-cancel=\(enc(cb + "&cancel=1"))&x-error=\(enc(cb + "&ok=0"))"
        case "scriptable":
            link = "scriptable:///run?scriptName=\(enc(target))&input=\(enc(input))&callback=\(enc(cb + "&ok=1"))"
        case "url":
            link = target.replacingOccurrences(of: "{{input}}", with: enc(input))
                .replacingOccurrences(of: "{{callback}}", with: enc(cb + "&ok=1"))
        default:
            let urlStr = target.replacingOccurrences(of: "{{input}}", with: enc(input))
            guard let url = URL(string: urlStr) else { return "接口地址无效，请检查连接器里的地址" }
            var req = URLRequest(url: url)
            req.httpMethod = c.s("method").isEmpty ? "GET" : c.s("method")
            req.timeoutInterval = 25
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_6 like Mac OS X) OSVIA", forHTTPHeaderField: "User-Agent")
            for line in c.s("headers").split(separator: "\n") {
                let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { req.setValue(kv[1], forHTTPHeaderField: kv[0]) }
            }
            let body = c.s("body")
            if !body.isEmpty && req.httpMethod != "GET" {
                req.httpBody = body.replacingOccurrences(of: "{{input}}", with: jsonEscape(input)).data(using: .utf8)
                if req.value(forHTTPHeaderField: "Content-Type") == nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            }
            do {
                let (d, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = format(d, limit: limit)
                if code >= 400 { return "接口返回错误（\(code)）：" + String(text.prefix(300)) }
                return text.isEmpty ? "接口返回了空内容（\(code)）" : text
            } catch let e as URLError {
                switch e.code {
                case .notConnectedToInternet: return "没有网络，请检查网络后再试"
                case .timedOut: return "请求超时。这个接口在当前网络下可能需要代理才能访问"
                default: return "接口调用失败：\(e.localizedDescription)"
                }
            } catch {
                return "接口调用失败：\(error.localizedDescription)"
            }
        }
        guard let url = URL(string: link) else { return "目标地址无效，请检查连接器设置" }
        let ok = await MainActor.run { () -> Bool in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return true
        }
        guard ok else { return "无法打开，请确认对应 App 已安装" }
        return kind == "url"
            ? "已打开「\(cname)」对应的 App。"
            : "已交给「\(cname)」处理，完成后会自动回到这里并显示结果。"
    }

    // 快捷指令、Scriptable 运行完回到本 App
    @MainActor
    static func callback(_ q: [String: String]) {
        let name = q["name"] ?? "连接器"
        if q["cancel"] == "1" {
            Agent.shared.post("assistant", "「\(name)」已取消。")
            return
        }
        if q["ok"] == "0" {
            let why = q["errorMessage"] ?? ""
            Agent.shared.post("assistant", "「\(name)」运行失败" + (why.isEmpty ? "。请确认快捷指令或脚本的名称与连接器里填的一致。" : "：\(why)"))
            return
        }
        let r = (q["result"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Agent.shared.post("assistant", r.isEmpty ? "「\(name)」已运行完成（没有返回内容）。" : "「\(name)」返回：\n" + String(r.prefix(3000)))
    }
}
