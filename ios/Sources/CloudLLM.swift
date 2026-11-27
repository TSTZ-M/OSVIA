import Foundation
import Security

// MARK: 云端大脑（可选）
// 用户自己填一个免费的 AI 服务密钥，回答会明显更聪明。
// 请求由手机直接发给用户选的服务商，不经过任何开发者服务器；密钥只存在本机钥匙串。
// 没填密钥时一切照旧，使用本机模型。

enum SecretStore {
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "OSVIA",
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func set(_ account: String, _ value: String) {
        SecItemDelete(base(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct CloudPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let base: String
    let model: String
    let note: String
    let keyURL: String
}

enum CloudError: LocalizedError {
    case config(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .config(let s):
            return s
        case .http(let c, let body):
            switch c {
            case 401, 403: return "密钥不对或没有权限（\(c)）"
            case 404: return "接口地址或模型名不对（404）"
            case 429: return "请求太频繁，或免费额度用完了（429）"
            default: return "服务商返回错误 \(c)：" + String(body.prefix(120))
            }
        }
    }
}

@MainActor
enum CloudLLM {
    static var lastError = ""

    static let presets: [CloudPreset] = [
        CloudPreset(id: "zhipu", name: "智谱 GLM（免费，国内直连）",
                    base: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4.7-flash",
                    note: "手机号注册即可，GLM-Flash 系列长期免费，中文很强。推荐大多数用户使用。",
                    keyURL: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"),
        CloudPreset(id: "silicon", name: "硅基流动（有免费模型，国内直连）",
                    base: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen3-8B",
                    note: "手机号注册，有多个免费开源模型，也可换成它家的其他模型。",
                    keyURL: "https://cloud.siliconflow.cn/account/ak"),
        CloudPreset(id: "gemini", name: "Google Gemini（免费，需海外网络）",
                    base: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-2.5-flash",
                    note: "用 Google 账号免费申请，国外用户首选；中国大陆需要能访问 Google。",
                    keyURL: "https://aistudio.google.com/apikey"),
        CloudPreset(id: "groq", name: "Groq（免费，需海外网络）",
                    base: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile",
                    note: "速度极快，有免费额度；中国大陆需要海外网络。",
                    keyURL: "https://console.groq.com/keys"),
        CloudPreset(id: "deepseek", name: "DeepSeek（很便宜，国内直连）",
                    base: "https://api.deepseek.com", model: "deepseek-chat",
                    note: "新用户有赠送额度，之后按量付费，价格很低，推理和代码强。",
                    keyURL: "https://platform.deepseek.com/api_keys"),
        CloudPreset(id: "custom", name: "自定义（OpenAI 兼容接口）",
                    base: "", model: "",
                    note: "填写任意兼容 OpenAI 的接口地址和模型名。", keyURL: "")
    ]

    static var enabled: Bool { UserDefaults.standard.object(forKey: "cloudOn") as? Bool ?? true }
    static var presetID: String { UserDefaults.standard.string(forKey: "cloudPreset") ?? "zhipu" }
    static var preset: CloudPreset { presets.first { $0.id == presetID } ?? presets[0] }

    static var base: String {
        let custom = (UserDefaults.standard.string(forKey: "cloudBase") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return presetID == "custom" ? custom : preset.base
    }

    static var model: String {
        let m = (UserDefaults.standard.string(forKey: "cloudModel") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? preset.model : m
    }

    static var key: String { SecretStore.get("cloudKey") }
    static var configured: Bool { enabled && !key.isEmpty && !base.isEmpty && !model.isEmpty }
    // 只有「设置好了 + 用户明确同意把内容发给这家服务商」才会真正走云端
    static var ready: Bool { configured && consented }
    static var summary: String { ready ? providerName : (configured ? "待授权" : "未设置") }

    // MARK: 第三方 AI 授权（App Store 审核指南 5.1.2(i)）。按服务商记录，换了服务商要重新同意
    static var consentID: String { presetID == "custom" ? base : presetID }
    static var providerName: String {
        presetID == "custom" ? (URL(string: base)?.host ?? base) : preset.name.components(separatedBy: "（")[0]
    }
    private static func idList(_ k: String) -> [String] {
        (UserDefaults.standard.string(forKey: k) ?? "").split(separator: "\n").map(String.init)
    }
    static var consented: Bool { idList("cloudConsent").contains(consentID) }
    // 设置好了但还没表过态：发消息前要问一次
    static var needsConsent: Bool { configured && !consented && !idList("cloudDeclined").contains(consentID) }
    static var mailAllowed: Bool { UserDefaults.standard.object(forKey: "cloudMail") as? Bool ?? true }

    static func setConsent(_ yes: Bool) {
        let id = consentID
        let granted = idList("cloudConsent").filter { $0 != id } + (yes ? [id] : [])
        let declined = idList("cloudDeclined").filter { $0 != id } + (yes ? [] : [id])
        UserDefaults.standard.set(granted.joined(separator: "\n"), forKey: "cloudConsent")
        UserDefaults.standard.set(declined.joined(separator: "\n"), forKey: "cloudDeclined")
    }

    // 用户在模型菜单里重新点了「云端」：下次发消息时再问一次
    static func askAgain() {
        let id = consentID
        UserDefaults.standard.set(idList("cloudDeclined").filter { $0 != id }.joined(separator: "\n"), forKey: "cloudDeclined")
    }

    // 向服务商查询当前账号能用的模型（OpenAI 兼容 GET /models）。服务商换了模型名也不用等应用更新。
    static func listModels() async -> (ids: [String], error: String) {
        let root = base.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n"))
        guard let url = URL(string: root + "/models") else { return ([], "接口地址不正确") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
                return ([], h.statusCode == 401 || h.statusCode == 403 ? "密钥不对或没有权限，请检查密钥" : "服务商没有提供模型列表（\(h.statusCode)），请手动填写模型名")
            }
            let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let arr = (j?["data"] as? [[String: Any]]) ?? (j?["models"] as? [[String: Any]]) ?? []
            let ids = arr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
                .filter { !$0.lowercased().contains("embed") && !$0.lowercased().contains("whisper") && !$0.lowercased().contains("tts") && !$0.lowercased().contains("image") }
            return (Array(Set(ids)).sorted(), ids.isEmpty ? "没有读到可用模型，请手动填写模型名" : "")
        } catch {
            return ([], "读取失败：" + error.localizedDescription)
        }
    }

    // 流式对话（OpenAI 兼容 /chat/completions）。返回完整回答；onText 每次给出到目前为止的全文。
    // 还没收到任何文字时遇到网络抖动、服务繁忙（429 / 5xx），自动静默重试一次，避免一次抖动就掉到本机模型
    static func stream(_ messages: [[String: String]], maxTokens: Int = 1000, temperature: Double = 0.4,
                       onText: @escaping (String) -> Void) async throws -> String {
        var attempt = 0
        while true {
            var got = false
            do {
                return try await streamOnce(messages, maxTokens: maxTokens, temperature: temperature) { t in
                    got = true
                    onText(t)
                }
            } catch {
                attempt += 1
                if attempt > 1 || got || Task.isCancelled || !transient(error) { throw error }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { throw error }
            }
        }
    }

    private static func transient(_ error: Error) -> Bool {
        if let u = error as? URLError {
            return [.networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed].contains(u.code)
        }
        if case CloudError.http(let c, _) = error { return [429, 500, 502, 503, 504].contains(c) }
        return false
    }

    private static func streamOnce(_ messages: [[String: String]], maxTokens: Int, temperature: Double,
                                   onText: @escaping (String) -> Void) async throws -> String {
        let root = base.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n"))
        guard let url = URL(string: root + "/chat/completions") else { throw CloudError.config("接口地址不正确") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true,
                                   "max_tokens": maxTokens, "temperature": temperature]
        // 混合思考模型：关闭长篇思考，回答更快
        if root.contains("bigmodel.cn") { body["thinking"] = ["type": "disabled"] }
        if root.contains("siliconflow") { body["enable_thinking"] = false }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            var err = ""
            for try await line in bytes.lines {
                err += line
                if err.count > 400 { break }
            }
            throw CloudError.http(h.statusCode, err)
        }
        var acc = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let d = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if d == "[DONE]" { break }
            guard let data = d.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ch = (j["choices"] as? [[String: Any]])?.first,
                  let delta = ch["delta"] as? [String: Any],
                  let c = delta["content"] as? String, !c.isEmpty else { continue }
            acc += c
            onText(LocalLLM.clean(acc))
        }
        return LocalLLM.clean(acc)
    }

    static func test() async -> String {
        do {
            let r = try await stream([["role": "user", "content": "用一句话说你好"]], maxTokens: 60, temperature: 0.2) { _ in }
            return r.isEmpty ? "连接成功，但模型没有返回内容，请检查模型名" : "连接成功：" + String(r.prefix(80))
        } catch {
            return "连接失败：" + error.localizedDescription
        }
    }
}
