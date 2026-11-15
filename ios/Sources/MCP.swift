import Foundation

// MARK: MCP 客户端（Streamable HTTP）
// 新版（2026-07-28）无状态：每个请求自带协议版本与客户端信息，不需要握手；
// 旧版（2025 系列）：initialize → Mcp-Session-Id → notifications/initialized。先试新版，被拒绝再退回旧版，并记住结果。
// 暂不支持已废弃的 HTTP+SSE（地址以 /sse 结尾的老服务）和 OAuth 登录；需要授权的服务请填访问令牌。

struct MCPTool {
    var name: String
    var desc: String
    var schema: [String: Any]
    var readOnly: Bool

    init(name: String, desc: String, schema: [String: Any], readOnly: Bool) {
        self.name = name
        self.desc = desc
        self.schema = schema
        self.readOnly = readOnly
    }

    init?(json j: [String: Any]) {
        guard let n = j["name"] as? String, !n.isEmpty else { return nil }
        name = n
        desc = (j["description"] as? String) ?? ""
        schema = (j["inputSchema"] as? [String: Any]) ?? [:]
        if let a = j["annotations"] as? [String: Any], let r = a["readOnlyHint"] as? Bool {
            readOnly = r
        } else {
            readOnly = (j["readOnly"] as? Bool) ?? false
        }
    }

    var json: [String: Any] {
        ["name": name, "description": desc, "inputSchema": schema, "readOnly": readOnly]
    }

    // 参数的简写：{"repoName*":"string","question*":"string"}（带 * 是必填）
    var signature: String {
        let props = (schema["properties"] as? [String: Any]) ?? [:]
        let req = Set((schema["required"] as? [String]) ?? [])
        let parts = props.keys.sorted().prefix(8).map { k -> String in
            let t = ((props[k] as? [String: Any])?["type"] as? String) ?? "any"
            return "\"\(k)\(req.contains(k) ? "*" : "")\":\"\(t)\""
        }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

enum MCPError: LocalizedError {
    case msg(String)
    case fallback
    var errorDescription: String? {
        switch self {
        case .msg(let s): return s
        case .fallback: return "服务器不支持新版协议"
        }
    }
}

actor MCPClient {
    enum Mode: String { case unknown, modern, legacy }

    static let modernVersion = "2026-07-28"
    static let legacyVersion = "2025-06-18"

    private struct Out {
        var status: Int
        var headers: [String: String]
        var body: Data
        var ctype: String
    }

    let serverId: Int
    let url: URL
    private let headers: [String: String]
    private var mode: Mode
    private var session: String?
    private var legacyReady = false
    private var proto = MCPClient.legacyVersion
    private var seq = 0

    init(serverId: Int, url: URL, headers: [String: String], mode: Mode) {
        self.serverId = serverId
        self.url = url
        self.headers = headers
        self.mode = mode
    }

    // MARK: 对外
    func tools() async throws -> [MCPTool] {
        var all: [MCPTool] = []
        var cursor: String?
        for _ in 0..<6 {
            var p: [String: Any] = [:]
            if let c = cursor { p["cursor"] = c }
            let r = try await request("tools/list", p, name: nil)
            let arr = (r["tools"] as? [[String: Any]]) ?? []
            all += arr.compactMap { MCPTool(json: $0) }
            cursor = r["nextCursor"] as? String
            if cursor == nil || cursor == "" { break }
        }
        return all
    }

    // 返回（文字结果，是否报错）
    func call(_ tool: String, _ args: [String: Any]) async throws -> (String, Bool) {
        let r = try await request("tools/call", ["name": tool, "arguments": args], name: tool)
        return MCPClient.text(r)
    }

    static func text(_ r: [String: Any]) -> (String, Bool) {
        var parts: [String] = []
        if let c = r["content"] as? [[String: Any]] {
            for p in c {
                switch (p["type"] as? String) ?? "" {
                case "text":
                    if let t = p["text"] as? String { parts.append(t) }
                case "image": parts.append("[图片]")
                case "audio": parts.append("[音频]")
                case "resource":
                    if let res = p["resource"] as? [String: Any] {
                        if let t = res["text"] as? String {
                            parts.append(t)
                        } else if let u = res["uri"] as? String {
                            parts.append("[资源] " + u)
                        }
                    }
                case "resource_link": parts.append("[链接] " + ((p["uri"] as? String) ?? ""))
                default: break
                }
            }
        }
        if parts.isEmpty, let sc = r["structuredContent"], JSONSerialization.isValidJSONObject(sc),
           let d = try? JSONSerialization.data(withJSONObject: sc, options: [.prettyPrinted, .sortedKeys]) {
            parts.append(String(decoding: d, as: UTF8.self))
        }
        if parts.isEmpty, (r["resultType"] as? String) == "input_required" { parts.append("服务器要求额外的交互输入，本应用暂不支持。") }
        return (parts.joined(separator: "\n"), (r["isError"] as? Bool) ?? false)
    }

    // MARK: 请求（先新版，再旧版）
    private func request(_ method: String, _ params: [String: Any], name: String?) async throws -> [String: Any] {
        if mode != .legacy {
            do {
                let r = try await modern(method, params, name: name)
                if mode != .modern {
                    mode = .modern
                    DB.shared.setKV("mcp.mode.\(serverId)", mode.rawValue)
                }
                return r
            } catch MCPError.fallback {
                if mode == .modern { throw MCPError.msg("服务器拒绝了请求（HTTP 400/404/405）。") }
                mode = .legacy
                DB.shared.setKV("mcp.mode.\(serverId)", mode.rawValue)
            }
        }
        do {
            return try await legacy(method, params)
        } catch MCPError.fallback {
            // 会话过期：重新握手重试一次
            session = nil
            legacyReady = false
            do {
                return try await legacy(method, params)
            } catch MCPError.fallback {
                throw MCPError.msg("会话已失效，重新连接失败。")
            }
        }
    }

    private func nextId() -> Int {
        seq += 1
        return seq
    }

    private func post(_ body: [String: Any], extra: [String: String]) async throws -> Out {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in extra { req.setValue(v, forHTTPHeaderField: k) }
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard let h = resp as? HTTPURLResponse else { throw MCPError.msg("没有收到响应") }
        var hs: [String: String] = [:]
        for (k, v) in h.allHeaderFields { hs[String(describing: k).lowercased()] = String(describing: v) }
        return Out(status: h.statusCode, headers: hs, body: d, ctype: hs["content-type"] ?? "")
    }

    // 响应可能是 JSON，也可能是 SSE 流；取出 JSON-RPC 消息
    private static func messages(_ out: Out) -> [[String: Any]] {
        if out.ctype.contains("text/event-stream") {
            var res: [[String: Any]] = []
            var data: [String] = []
            func flush() {
                if !data.isEmpty, let d = data.joined(separator: "\n").data(using: .utf8),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    res.append(j)
                }
                data = []
            }
            for raw in String(decoding: out.body, as: UTF8.self).components(separatedBy: "\n") {
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
                if line.isEmpty {
                    flush()
                } else if line.hasPrefix("data:") {
                    var v = String(line.dropFirst(5))
                    if v.hasPrefix(" ") { v.removeFirst() }
                    data.append(v)
                }
            }
            flush()
            return res
        }
        guard let j = try? JSONSerialization.jsonObject(with: out.body) else { return [] }
        if let o = j as? [String: Any] { return [o] }
        if let a = j as? [[String: Any]] { return a }
        return []
    }

    private static func headerValue(_ s: String) -> String {
        if s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) { return s }
        return "=?base64?" + Data(s.utf8).base64EncodedString() + "?="
    }

    private static func snippet(_ d: Data) -> String {
        String(String(decoding: d.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func finish(_ out: Out, id: Int, allowFallback: Bool) throws -> [String: Any] {
        if out.status == 401 || out.status == 403 {
            throw MCPError.msg("服务器要求授权（HTTP \(out.status)）。请在服务器设置里点「网页登录授权」，或填写访问令牌。")
        }
        let msgs = MCPClient.messages(out)
        let rpc = msgs.first(where: { ($0["id"] as? Int) == id }) ?? msgs.first(where: { $0["result"] != nil || $0["error"] != nil })
        if let rpc {
            if let e = rpc["error"] as? [String: Any] {
                let m = (e["message"] as? String) ?? "未知错误"
                let low = m.lowercased()
                if allowFallback, low.contains("session") || low.contains("initialize") || low.contains("not initialized") {
                    throw MCPError.fallback
                }
                throw MCPError.msg("MCP 错误：" + m)
            }
            if let r = rpc["result"] as? [String: Any] { return r }
        }
        if allowFallback, [400, 404, 405, 406, 415].contains(out.status) { throw MCPError.fallback }
        if !(200..<300).contains(out.status) {
            let hint = url.path.hasSuffix("/sse") ? "（这是旧式 SSE 地址，请改用以 /mcp 结尾的地址）" : ""
            throw MCPError.msg("服务器返回 HTTP \(out.status)\(hint) \(MCPClient.snippet(out.body))")
        }
        throw MCPError.msg("服务器没有返回有效的 MCP 响应。")
    }

    private func modern(_ method: String, _ params: [String: Any], name: String?) async throws -> [String: Any] {
        let id = nextId()
        var p = params
        let meta: [String: Any] = [
            "io.modelcontextprotocol/protocolVersion": MCPClient.modernVersion,
            "io.modelcontextprotocol/clientInfo": ["name": "OSVIA", "version": "0.9"],
            "io.modelcontextprotocol/clientCapabilities": [String: Any]()
        ]
        p["_meta"] = meta
        var extra = ["MCP-Protocol-Version": MCPClient.modernVersion, "Mcp-Method": method]
        if let n = name { extra["Mcp-Name"] = MCPClient.headerValue(n) }
        let out = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": p], extra: extra)
        return try finish(out, id: id, allowFallback: mode != .modern)
    }

    private func ensureSession() async throws {
        if legacyReady { return }
        let id = nextId()
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": "initialize",
            "params": ["protocolVersion": MCPClient.legacyVersion, "capabilities": [String: Any](),
                       "clientInfo": ["name": "OSVIA", "version": "0.9"]] as [String: Any]
        ]
        let out = try await post(body, extra: [:])
        let r = try finish(out, id: id, allowFallback: false)
        session = out.headers["mcp-session-id"]
        if let v = r["protocolVersion"] as? String { proto = v }
        var extra = ["MCP-Protocol-Version": proto]
        if let s = session { extra["Mcp-Session-Id"] = s }
        _ = try? await post(["jsonrpc": "2.0", "method": "notifications/initialized"], extra: extra)
        legacyReady = true
    }

    private func legacy(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try await ensureSession()
        let id = nextId()
        var extra = ["MCP-Protocol-Version": proto]
        if let s = session { extra["Mcp-Session-Id"] = s }
        let out = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": params], extra: extra)
        // 会话过期时服务器返回 404（或提示 session）：交给上层重新握手
        if out.status == 404, session != nil { throw MCPError.fallback }
        return try finish(out, id: id, allowFallback: false)
    }
}

// MARK: 服务器管理（保存在数据库，令牌放钥匙串）
struct MCPPreset: Identifiable {
    let name: String
    let url: String
    let about: String
    var oauth = false
    var id: String { name }
}

@MainActor
enum MCP {
    private static var clients: [Int: MCPClient] = [:]

    static let presets: [MCPPreset] = [
        MCPPreset(name: "DeepWiki", url: "https://mcp.deepwiki.com/mcp", about: "读懂任意 GitHub 仓库：结构、文档、问答"),
        MCPPreset(name: "Microsoft Learn", url: "https://learn.microsoft.com/api/mcp", about: "检索微软官方技术文档与示例代码"),
        MCPPreset(name: "Cloudflare Docs", url: "https://docs.mcp.cloudflare.com/mcp", about: "检索 Cloudflare 官方文档"),
        MCPPreset(name: "Context7", url: "https://mcp.context7.com/mcp", about: "查询各种开发库的最新文档")
    ]

    // 需要网页登录（OAuth）的官方服务：添加后会跳出系统登录页，授权一次即可
    static let oauthPresets: [MCPPreset] = [
        MCPPreset(name: "Notion", url: "https://mcp.notion.com/mcp", about: "搜索、读取、创建你的 Notion 页面和数据库", oauth: true),
        MCPPreset(name: "Linear", url: "https://mcp.linear.app/mcp", about: "查看和创建 Linear 的任务、项目", oauth: true),
        MCPPreset(name: "GitHub", url: "https://api.githubcopilot.com/mcp/", about: "仓库、Issue、PR、代码搜索", oauth: true),
        MCPPreset(name: "Atlassian（Jira / Confluence）", url: "https://mcp.atlassian.com/v2/mcp", about: "Jira 工单与 Confluence 文档", oauth: true),
        MCPPreset(name: "Asana", url: "https://mcp.asana.com/v2/mcp", about: "任务与项目管理", oauth: true),
        MCPPreset(name: "Stripe", url: "https://mcp.stripe.com", about: "查询收款、客户和订阅", oauth: true),
        MCPPreset(name: "HubSpot", url: "https://mcp.hubspot.com", about: "客户与销售数据", oauth: true),
        MCPPreset(name: "Cloudflare", url: "https://mcp.cloudflare.com/mcp", about: "管理 Workers、D1、KV、R2 等 Cloudflare 资源", oauth: true),
        MCPPreset(name: "Box", url: "https://mcp.box.com", about: "搜索和读取 Box 里的文件", oauth: true)
    ]

    static func servers() -> [Row] { DB.shared.rows("SELECT id, name, url, auto, enabled, tools, ts FROM mcp_server ORDER BY id") }

    static func row(_ id: Int) -> Row? { DB.shared.rows("SELECT id, name, url, auto, enabled, tools, ts FROM mcp_server WHERE id=?", [id]).first }

    // 返回错误文字；空串表示成功
    @discardableResult
    static func add(name: String, url: String, token: String, headers: String, auto: Bool) -> (id: Int, error: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.contains("://") { u = "https://" + u }
        guard let parsed = URL(string: u), parsed.scheme == "https", parsed.host != nil else { return (0, "请填写 https 开头的服务器地址。") }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = n.isEmpty ? (parsed.host ?? "MCP") : n
        if servers().contains(where: { $0.s("name").lowercased() == title.lowercased() }) { return (0, "已经有同名的服务器了。") }
        let id = Int(DB.shared.run("INSERT INTO mcp_server(name,url,auto,enabled,tools,ts) VALUES(?,?,?,?,?,?)",
                                   [title, u, auto ? 1 : 0, 1, "", Date().timeIntervalSince1970]))
        SecretStore.set("mcp.token.\(id)", token.trimmingCharacters(in: .whitespacesAndNewlines))
        SecretStore.set("mcp.headers.\(id)", headers)
        return (id, "")
    }

    static func remove(_ id: Int) {
        DB.shared.run("DELETE FROM mcp_server WHERE id=?", [id])
        SecretStore.set("mcp.token.\(id)", "")
        SecretStore.set("mcp.headers.\(id)", "")
        MCPOAuth.forget(id)
        DB.shared.run("DELETE FROM kv WHERE k=?", ["mcp.mode.\(id)"])
        clients[id] = nil
    }

    static func setEnabled(_ id: Int, _ on: Bool) { DB.shared.run("UPDATE mcp_server SET enabled=? WHERE id=?", [on ? 1 : 0, id]) }
    static func setAuto(_ id: Int, _ on: Bool) { DB.shared.run("UPDATE mcp_server SET auto=? WHERE id=?", [on ? 1 : 0, id]) }

    static func updateAuth(_ id: Int, token: String, headers: String) {
        SecretStore.set("mcp.token.\(id)", token.trimmingCharacters(in: .whitespacesAndNewlines))
        SecretStore.set("mcp.headers.\(id)", headers)
        clients[id] = nil
    }

    static func token(_ id: Int) -> String { SecretStore.get("mcp.token.\(id)") }
    static func extraHeaders(_ id: Int) -> String { SecretStore.get("mcp.headers.\(id)") }

    private static func client(_ r: Row) -> MCPClient? {
        let id = r.i("id")
        if let c = clients[id] { return c }
        guard let u = URL(string: r.s("url")) else { return nil }
        var h: [String: String] = [:]
        for line in extraHeaders(id).components(separatedBy: .newlines) {
            guard let i = line.firstIndex(of: ":") else { continue }
            let k = line[..<i].trimmingCharacters(in: .whitespaces)
            let v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { h[k] = v }
        }
        let t = token(id)
        if !t.isEmpty { h["Authorization"] = t.lowercased().hasPrefix("bearer ") ? t : "Bearer " + t }
        let mode = MCPClient.Mode(rawValue: DB.shared.kv("mcp.mode.\(id)") ?? "") ?? .unknown
        let c = MCPClient(serverId: id, url: u, headers: h, mode: mode)
        clients[id] = c
        return c
    }

    static func cachedTools(_ r: Row) -> [MCPTool] {
        guard let d = r.s("tools").data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.compactMap { MCPTool(json: $0) }
    }

    // 连接并刷新工具列表。返回错误文字；空串表示成功
    static func refresh(_ id: Int) async -> String {
        await MCPOAuth.ensureFresh(id)
        guard let r = row(id), let c = client(r) else { return "服务器地址不正确。" }
        do {
            let list = try await c.tools()
            let data = try JSONSerialization.data(withJSONObject: list.map { $0.json })
            DB.shared.run("UPDATE mcp_server SET tools=?, ts=? WHERE id=?", [String(decoding: data, as: UTF8.self), Date().timeIntervalSince1970, id])
            return list.isEmpty ? "已连接，但服务器没有提供任何工具。" : ""
        } catch {
            return error.localizedDescription
        }
    }

    // 按名字找服务器（不区分大小写，支持包含）
    static func find(_ name: String) -> Row? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let list = servers().filter { $0.i("enabled") == 1 }
        if let exact = list.first(where: { $0.s("name").lowercased() == key }) { return exact }
        return list.first(where: { $0.s("name").lowercased().contains(key) || key.contains($0.s("name").lowercased()) })
    }

    static func hasEnabled() -> Bool { servers().contains { $0.i("enabled") == 1 && !$0.s("tools").isEmpty } }

    // 写进系统提示词的工具目录。only：只列出这些名字的服务器（小模型用）；每个服务器最多列 12 个工具
    static func catalog(only: [String]? = nil) -> String {
        var out = ""
        for r in servers() where r.i("enabled") == 1 {
            let name = r.s("name")
            if let only, !only.contains(where: { name.lowercased().contains($0.lowercased()) || $0.lowercased().contains(name.lowercased()) }) { continue }
            let tools = cachedTools(r)
            if tools.isEmpty { continue }
            out += "【\(name)】\n"
            for t in tools.prefix(12) {
                out += "  - \(t.name) \(t.signature)：\(String(t.desc.replacingOccurrences(of: "\n", with: " ").prefix(90)))\n"
            }
            if tools.count > 12 { out += "  （共 \(tools.count) 个工具，其余用 mcp_tools 按关键词查）\n" }
        }
        return out
    }

    static func searchTools(server: String, q: String) -> String {
        guard let r = find(server) else { return "没有名为「\(server)」的 MCP 服务器。" }
        let key = q.lowercased()
        let tools = cachedTools(r).filter { key.isEmpty || $0.name.lowercased().contains(key) || $0.desc.lowercased().contains(key) }
        if tools.isEmpty { return "没有匹配的工具。" }
        return tools.prefix(15).map { "- \($0.name) \($0.signature)：\(String($0.desc.replacingOccurrences(of: "\n", with: " ").prefix(160)))" }.joined(separator: "\n")
    }

    // 调用工具。返回（是否成功，文字）
    static func call(_ r: Row, tool: String, args: [String: Any]) async -> (ok: Bool, text: String) {
        await MCPOAuth.ensureFresh(r.i("id"))
        guard let c = client(r) else { return (false, "服务器地址不正确。") }
        do {
            let (text, isErr) = try await c.call(tool, args)
            let t = text.isEmpty ? "（服务器没有返回内容）" : text
            return (!isErr, t)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
