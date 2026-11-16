import Foundation

struct ToolCall {
    let name: String
    let args: [String: Any]

    // 去重用：同一轮或前几轮里完全相同的调用不重复执行
    var key: String {
        let d = (try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])) ?? Data()
        return name + String(decoding: d, as: UTF8.self)
    }
}

struct ToolResult {
    var text: String
    var final = false      // 做事类工具（闹钟、提醒……）的结果直接作为最终回复
    var ok = true
}

// MARK: 统一的工具注册表：云端大脑和本机大模型共用同一套执行代码，区别只在于给模型看多少说明
@MainActor
enum AgentTools {
    // MARK: 解析：一条回复里最多 3 个 <tool>{…}</tool>，容忍缺结束标签、换行、代码围栏
    nonisolated static func parse(_ t: String) -> [ToolCall] {
        var out: [ToolCall] = []
        var rest = Substring(t)
        while out.count < 3, let r = rest.range(of: "<tool>") {
            rest = rest[r.upperBound...]
            guard let obj = firstObject(in: rest) else { break }
            rest = rest[obj.end...]
            if let c = toCall(obj.json) { out.append(c) }
        }
        return out
    }

    nonisolated private static func toCall(_ j: [String: Any]) -> ToolCall? {
        guard let name = (j["name"] as? String) ?? (j["tool"] as? String), !name.isEmpty else { return nil }
        let args = (j["args"] as? [String: Any]) ?? (j["arguments"] as? [String: Any]) ?? (j["input"] as? [String: Any]) ?? [:]
        return ToolCall(name: name.trimmingCharacters(in: .whitespaces), args: args)
    }

    nonisolated private static func firstObject(in s: Substring) -> (json: [String: Any], end: Substring.Index)? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inStr = false
        var esc = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if inStr {
                if esc {
                    esc = false
                } else if c == "\\" {
                    esc = true
                } else if c == "\"" {
                    inStr = false
                }
            } else if c == "\"" {
                inStr = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let end = s.index(after: i)
                    let raw = String(s[start..<end])
                    if let j = object(raw) { return (j, end) }
                    // 模型常在字符串里直接换行：换成空格再试
                    let fixed = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                    if let j = object(fixed) { return (j, end) }
                    return nil
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    nonisolated private static func object(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    // 流式显示时去掉工具调用（含刚写了一半的「<to」）
    nonisolated static func shown(_ t: String) -> String {
        if let r = t.range(of: "<tool") { return String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let i = t.lastIndex(of: "<"), "<tool>".hasPrefix(String(t[i...])) {
            return String(t[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    // 回复里的工具标签清掉（最后一轮模型还在调用工具时的兜底）
    nonisolated static func stripped(_ t: String) -> String {
        var s = t.replacingOccurrences(of: "<tool>[\\s\\S]*?(</tool>|$)", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    // 需要用户确认、或会改变外部状态的工具：顺序执行，不并行
    nonisolated static func sequential(_ name: String) -> Bool {
        ["mcp_call", "http_request", "delete_file", "run_shortcut", "confirm_action", "mail_send", "mail_act", "mail_unsubscribe", "speak", "ocr", "calendar_free", "photos_find", "connector", "open_app", "maps", "compose", "share", "contacts", "location"].contains(name) || Hands2.sequentialNames.contains(name)
    }

    // MARK: 给模型看的工具说明
    static func doc(local: Bool, query: String) -> String {
        var s = "可用工具：\n"
        s += "- web_search {\"q\":\"搜索词\"}：联网搜索，返回带编号的结果。最新消息、新闻、价格、天气、比分、你没把握的事实，先搜再答\n"
        s += "- read_url {\"url\":\"网址\"}：读取网页正文。搜索后对最相关的 1-2 条用它拿细节\n"
        s += "- search_memory {\"q\":\"关键词\"}：查用户的记忆与知识库\n"
        s += "- calc {\"expr\":\"算式\"}：精确计算，支持 + - * / % ^ 括号和 sqrt sin cos log ln abs round pi 等。任何计算都用它，不要心算\n"
        s += "- now {}：当前日期、星期、时间、时区\n"
        if !local {
            s += "- remember {\"text\":\"一条关于用户的长期事实或偏好\",\"cat\":\"个人|偏好|工作|项目|人际|其他\"}：用户明确要求记住，或透露了稳定的个人信息时调用\n"
            s += "- set_alarm {\"time\":\"yyyy-MM-dd'T'HH:mm\",\"title\":\"标题\",\"repeat\":\"none|daily|weekly\"}：设置会响铃的闹钟\n"
            s += "- add_reminder {\"time\":\"yyyy-MM-dd'T'HH:mm\",\"title\":\"内容\",\"repeat\":\"none|daily|weekly\"}：添加提醒事项\n"
            s += "- add_event {\"time\":\"yyyy-MM-dd'T'HH:mm\",\"title\":\"标题\"}：添加日历日程\n"
        }
        s += Hands.doc(local: local)
        if !local { s += Mail.doc() }
        let skills = Skills.list().map { $0.s("name") }
        if !skills.isEmpty { s += "- run_skill {\"name\":\"技能名\",\"input\":\"输入\"}：运行用户的脚本技能，可用：" + skills.prefix(12).joined(separator: "、") + "\n" }
        let conns = Connectors.all().map { $0.s("name") }
        if !conns.isEmpty && !local { s += "- connector {\"name\":\"连接器名\",\"input\":\"输入\"}：调用用户连接的接口或应用，可用：" + conns.prefix(10).joined(separator: "、") + "\n" }

        let mention: [String]? = local ? MCP.servers().map { $0.s("name") }.filter { query.lowercased().contains($0.lowercased()) } : nil
        let mcp = (local && (mention ?? []).isEmpty) ? "" : MCP.catalog(only: mention)
        if !mcp.isEmpty {
            s += "- mcp_call {\"server\":\"服务名\",\"tool\":\"工具名\",\"args\":{…}}：调用下面 MCP 服务器里的工具（带 * 的参数必填）\n"
            s += "- mcp_tools {\"server\":\"服务名\",\"q\":\"关键词\"}：按关键词查某个 MCP 服务器的工具\n"
            s += "MCP 服务器：\n" + mcp
        }
        if local {
            s += "调用格式：整条回复只输出一行 <tool>{\"name\":\"工具名\",\"args\":{…}}</tool>，不要输出别的文字，一次只调用一个。\n"
        } else {
            s += "调用格式：整条回复只输出工具调用，不要输出别的文字，每个调用单独一行 <tool>{\"name\":\"工具名\",\"args\":{…}}</tool>。互不依赖的调用可以放在同一条回复里（最多 3 个，会并行执行）。时间必须换算成上面的绝对时间格式。\n"
        }
        return s
    }

    // MARK: 执行
    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func when(_ a: [String: Any]) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let s = str(a, "time")
        guard !s.isEmpty else { return nil }
        return f.date(from: String(s.prefix(16)))
    }

    private static func rep(_ a: [String: Any]) -> Int {
        let r = str(a, "repeat")
        return r == "daily" ? 1 : (r == "weekly" ? 7 : 0)
    }

    // 参数的简短说明，显示在步骤里
    private static func brief(_ a: [String: Any]) -> String {
        let parts = a.keys.sorted().prefix(3).map { k -> String in
            let v = (a[k] as? String) ?? "\(a[k] ?? "")"
            return "\(k): " + String(v.replacingOccurrences(of: "\n", with: " ").prefix(40))
        }
        return parts.joined(separator: "，")
    }

    static func run(_ c: ToolCall, trace: Tracer, cloud: Bool) async -> ToolResult {
        let a = c.args
        switch c.name {
        case "web_search":
            let q = str(a, "q")
            guard !q.isEmpty else { return ToolResult(text: "搜索词为空。", ok: false) }
            let sid = trace.begin(.search, "联网搜索", q)
            Live.set(.searching)
            let hits = await WebSearch.search(q)
            if hits.isEmpty {
                trace.end(sid, ok: false, detail: q + " · " + L10n.tr("没有结果"))
                return ToolResult(text: "没有搜到结果（可能网络不通，或搜索词太偏，可以换个关键词再试）。", ok: false)
            }
            let ns = trace.register(hits)
            trace.end(sid, detail: q + " · " + L10n.f("{} 条结果", "\(hits.count)"))
            return ToolResult(text: WebSearch.format(hits, numbers: ns))

        case "read_url":
            let s = str(a, "url")
            guard let u = URL(string: s), u.scheme == "http" || u.scheme == "https" else { return ToolResult(text: "网址不正确。", ok: false) }
            let host = (u.host ?? s).replacingOccurrences(of: "www.", with: "")
            let sid = trace.begin(.read, "读取网页", host)
            Live.set(.searching)
            let page = await Web.read(u, limit: cloud ? 6000 : 3000)
            if page.text.isEmpty {
                trace.end(sid, ok: false, detail: host + " · " + L10n.tr("没读到内容"))
                return ToolResult(text: "网页没有读到内容（可能需要登录或由脚本渲染），可以换一个来源。", ok: false)
            }
            let n = trace.register(url: s, title: page.title)
            trace.end(sid, detail: page.title.isEmpty ? host : page.title)
            return ToolResult(text: "[\(n)] \(page.title)\n\(page.text)")

        case "search_memory":
            let q = str(a, "q")
            let sid = trace.begin(.memory, "查询记忆", q)
            var mem = Memory.relevant(q, k: 8)
            let exact = !mem.isEmpty
            if mem.isEmpty { mem = Memory.overview(14) }
            let kb = KB.shared.search(q, k: 3)
            trace.end(sid, detail: q + " · " + L10n.f("{} 条", "\(mem.count + kb.count)"))
            if mem.isEmpty && kb.isEmpty { return ToolResult(text: "记忆和知识库里没有相关内容。") }
            var t = ""
            if !mem.isEmpty { t += (exact ? "用户记忆：\n" : "没有精确匹配，以下是关于用户的概览：\n") + mem.map { "- " + $0 }.joined(separator: "\n") + "\n" }
            if !kb.isEmpty { t += "知识库：\n" + kb.map { "- " + String($0.prefix(300)) }.joined(separator: "\n") }
            return ToolResult(text: t)

        case "remember":
            let t = str(a, "text")
            guard !t.isEmpty else { return ToolResult(text: "没有要记的内容。", ok: false) }
            let added = Memory.add(t, cat: str(a, "cat"), src: "对话")
            trace.note(.memory, "写入记忆", String(t.prefix(60)))
            return ToolResult(text: added ? "好的，已经记住了。" : "这个我已经记过了。", final: true)

        case "calc":
            let e = str(a, "expr")
            let sid = trace.begin(.calc, "计算", e)
            guard let v = Calc.eval(e) else {
                trace.end(sid, ok: false, detail: e)
                return ToolResult(text: "算式无法计算，请检查括号和运算符后重新调用。", ok: false)
            }
            let r = Calc.format(v)
            trace.end(sid, detail: e + " = " + r)
            return ToolResult(text: e + " = " + r)

        case "now":
            let t = Sys.fmtFull(Date()) + " · " + TimeZone.current.identifier
            trace.note(.time, "查看当前时间", t)
            return ToolResult(text: t)

        case "run_skill":
            let n = str(a, "name")
            let sid = trace.begin(.skill, "运行技能", n)
            let r = await Skills.runAsync(n, str(a, "input"))
            trace.end(sid, ok: r.0, detail: r.0 ? n : n + " · " + String(r.1.prefix(40)))
            return ToolResult(text: r.0 ? r.1 : "技能「\(n)」运行失败：\(r.1)", ok: r.0)

        case "connector":
            let n = str(a, "name")
            guard let row = Connectors.find(n) else { return ToolResult(text: "没有名为「\(n)」的连接器。", ok: false) }
            let name = row.s("name")
            let input = str(a, "input")
            let sid = trace.begin(.connector, "调用连接器", name + (input.isEmpty ? "" : " · " + String(input.prefix(40))))
            let out = await Connectors.run(name, input, limit: cloud ? 3000 : 1500)
            trace.end(sid)
            return ToolResult(text: out, final: row.s("kind") != "http" && !row.s("kind").isEmpty)

        case "mcp_tools":
            let server = str(a, "server")
            let sid = trace.begin(.mcp, "查看 MCP 工具", server)
            let t = MCP.searchTools(server: server, q: str(a, "q"))
            trace.end(sid)
            return ToolResult(text: t)

        case "mcp_call":
            return await callMCP(a, trace: trace, cloud: cloud)

        case "set_alarm", "add_reminder", "add_event":
            guard let d = when(a) else { return ToolResult(text: "时间格式不对，请用 yyyy-MM-dd'T'HH:mm 重新调用。", ok: false) }
            let title = str(a, "title")
            let sid = trace.begin(.action, c.name == "set_alarm" ? "设置闹钟" : (c.name == "add_reminder" ? "添加提醒" : "添加日程"), title)
            Live.set(.working)
            var r = ""
            switch c.name {
            case "set_alarm":
                let label = title.isEmpty ? "闹钟" : String(title.prefix(20))
                r = await Sys.alarmSmart(d, label, rep: rep(a))
            case "add_reminder":
                let label = title.isEmpty ? "提醒" : String(title.prefix(40))
                r = await Sys.reminder(label, d, rep: rep(a))
            default:
                r = await Sys.event(title.isEmpty ? "日程" : String(title.prefix(30)), d)
            }
            trace.end(sid, detail: Sys.friendly(d))
            return ToolResult(text: r, final: true)

        default:
            if let r = await Hands.run(c, trace: trace, cloud: cloud) { return r }
            if let r = await Mail.run(c, trace: trace, cloud: cloud) { return r }
            return ToolResult(text: "没有「\(c.name)」这个工具，请只使用工具列表里的。", ok: false)
        }
    }

    private static func callMCP(_ a: [String: Any], trace: Tracer, cloud: Bool) async -> ToolResult {
        let server = str(a, "server")
        let tool = str(a, "tool")
        let args = (a["args"] as? [String: Any]) ?? [:]
        guard let row = MCP.find(server) else {
            let names = MCP.servers().filter { $0.i("enabled") == 1 }.map { $0.s("name") }.joined(separator: "、")
            return ToolResult(text: "没有名为「\(server)」的 MCP 服务器。可用：" + (names.isEmpty ? "无" : names), ok: false)
        }
        let name = row.s("name")
        let tools = MCP.cachedTools(row)
        let info = tools.first(where: { $0.name == tool })
        if tool.isEmpty || (info == nil && !tools.isEmpty) {
            return ToolResult(text: "「\(name)」里没有「\(tool)」这个工具。它的工具有：" + tools.prefix(20).map { $0.name }.joined(separator: "、"), ok: false)
        }
        // 会改变外部状态的工具先问用户；只读工具、或用户已信任的服务器直接执行
        if row.i("auto") == 0 && !(info?.readOnly ?? false) {
            let ok = await Agent.shared.requestConfirm(title: L10n.tr("允许调用外部工具？"), detail: "\(name) · \(tool)\n" + brief(args))
            if !ok { return ToolResult(text: "用户拒绝了这次调用，没有执行。请告诉用户你没有执行，并问是否换个方式。", ok: false) }
        }
        let sid = trace.begin(.mcp, L10n.tr("调用 MCP") + " · " + name, tool + (args.isEmpty ? "" : " · " + brief(args)))
        let r = await MCP.call(row, tool: tool, args: args)
        trace.end(sid, ok: r.ok, detail: r.ok ? nil : tool + " · " + String(r.text.prefix(50)))
        let body = String(r.text.prefix(cloud ? 6000 : 2500))
        return ToolResult(text: r.ok ? body : "调用失败：" + body, ok: r.ok)
    }
}
