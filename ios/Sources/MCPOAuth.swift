import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: MCP 的网页登录（OAuth 2.1 + PKCE + 动态客户端注册）
// 流程：从 MCP 服务器找到授权服务器 → 自动注册客户端 → 系统网页登录（ASWebAuthenticationSession）→ 换取令牌 → 过期自动刷新。
// 令牌放钥匙串，和手填访问令牌走同一条路径，其余代码不用改。

@MainActor
enum MCPOAuth {
    private static let redirect = "osvia://oauth/callback"

    struct Discovery {
        var authz: String
        var token: String
        var registration: String?
        var scopes: [String]
    }

    private struct Fail: LocalizedError {
        let msg: String
        var errorDescription: String? { msg }
    }

    @MainActor
    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let w = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) { return w }
            if let s = scenes.first { return UIWindow(windowScene: s) }
            return UIWindow(frame: .zero)
        }
    }

    private static var anchor: Anchor?
    private static var session: ASWebAuthenticationSession?

    static func isAuthorized(_ id: Int) -> Bool { !SecretStore.get("mcp.oauth.\(id)").isEmpty }

    static func forget(_ id: Int) { SecretStore.set("mcp.oauth.\(id)", "") }

    // MARK: 登录。返回错误文字；空串表示成功
    static func login(_ id: Int, url: URL) async -> String {
        do {
            let d = try await discover(url)
            let cid = try await clientID(d)
            let verifier = random(64)
            let challenge = b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
            let state = random(24)
            guard var comps = URLComponents(string: d.authz) else { throw Fail(msg: "授权地址不正确。") }
            var q = comps.queryItems ?? []
            q += [URLQueryItem(name: "response_type", value: "code"),
                  URLQueryItem(name: "client_id", value: cid),
                  URLQueryItem(name: "redirect_uri", value: redirect),
                  URLQueryItem(name: "code_challenge", value: challenge),
                  URLQueryItem(name: "code_challenge_method", value: "S256"),
                  URLQueryItem(name: "state", value: state),
                  URLQueryItem(name: "resource", value: url.absoluteString)]
            if !d.scopes.isEmpty { q.append(URLQueryItem(name: "scope", value: d.scopes.joined(separator: " "))) }
            comps.queryItems = q
            guard let authURL = comps.url else { throw Fail(msg: "授权地址不正确。") }
            let cb = try await web(authURL)
            let items = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func val(_ k: String) -> String? { items.first(where: { $0.name == k })?.value }
            if let e = val("error") { throw Fail(msg: "登录没有完成：" + (val("error_description") ?? e)) }
            guard val("state") == state, let code = val("code") else { throw Fail(msg: "登录结果校验失败，请重试。") }
            let tok = try await post(d.token, form: [
                "grant_type": "authorization_code", "code": code, "redirect_uri": redirect,
                "client_id": cid, "code_verifier": verifier, "resource": url.absoluteString])
            try save(id, tok, tokenURL: d.token, clientID: cid, resource: url.absoluteString, oldRefresh: "")
            return ""
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            return "已取消登录。"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: 令牌快过期就用 refresh_token 换新的；没有登录过的服务器什么也不做
    static func ensureFresh(_ id: Int) async {
        guard let meta = load(id), let exp = meta["exp"] as? Double, exp - Date().timeIntervalSince1970 < 120,
              let refresh = meta["refresh"] as? String, !refresh.isEmpty,
              let tokenURL = meta["token_endpoint"] as? String, let cid = meta["client_id"] as? String else { return }
        var form = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": cid]
        if let r = meta["resource"] as? String { form["resource"] = r }
        if let tok = try? await post(tokenURL, form: form) {
            try? save(id, tok, tokenURL: tokenURL, clientID: cid, resource: (meta["resource"] as? String) ?? "", oldRefresh: refresh)
        }
    }

    // MARK: 内部
    private static func load(_ id: Int) -> [String: Any]? {
        guard let d = SecretStore.get("mcp.oauth.\(id)").data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func save(_ id: Int, _ tok: [String: Any], tokenURL: String, clientID: String, resource: String, oldRefresh: String) throws {
        guard let access = tok["access_token"] as? String, !access.isEmpty else { throw Fail(msg: "服务器没有返回访问令牌。") }
        let expires = (tok["expires_in"] as? Double) ?? Double((tok["expires_in"] as? Int) ?? 3000)
        let meta: [String: Any] = [
            "refresh": (tok["refresh_token"] as? String) ?? oldRefresh,
            "exp": Date().timeIntervalSince1970 + max(expires, 60),
            "token_endpoint": tokenURL, "client_id": clientID, "resource": resource
        ]
        if let d = try? JSONSerialization.data(withJSONObject: meta) { SecretStore.set("mcp.oauth.\(id)", String(decoding: d, as: UTF8.self)) }
        MCP.updateAuth(id, token: access, headers: MCP.extraHeaders(id))
    }

    private static func discover(_ mcp: URL) async throws -> Discovery {
        guard let scheme = mcp.scheme, let host = mcp.host else { throw Fail(msg: "服务器地址不正确。") }
        let origin = scheme + "://" + host + (mcp.port.map { ":\($0)" } ?? "")
        let path = mcp.path == "/" ? "" : mcp.path

        var prm: [String] = []
        if let h = await challengeMetadata(mcp) { prm.append(h) }
        prm += [origin + "/.well-known/oauth-protected-resource" + path, origin + "/.well-known/oauth-protected-resource"]
        var issuer = origin
        for c in prm {
            if let j = await json(c), let a = (j["authorization_servers"] as? [String])?.first { issuer = a; break }
        }
        guard let iu = URL(string: issuer), let ihost = iu.host else { throw Fail(msg: "没有找到授权服务器。") }
        let iorigin = (iu.scheme ?? "https") + "://" + ihost + (iu.port.map { ":\($0)" } ?? "")
        let ipath = iu.path == "/" ? "" : iu.path
        let cands = [iorigin + "/.well-known/oauth-authorization-server" + ipath,
                     iorigin + "/.well-known/openid-configuration" + ipath,
                     issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/.well-known/openid-configuration"]
        for c in cands {
            if let j = await json(c), let a = j["authorization_endpoint"] as? String, let t = j["token_endpoint"] as? String {
                let scopes = (j["scopes_supported"] as? [String]) ?? []
                _ = scopes
                return Discovery(authz: a, token: t, registration: j["registration_endpoint"] as? String, scopes: [])
            }
        }
        throw Fail(msg: "这个服务没有公开标准的网页登录入口。请在「访问授权」里手动填写访问令牌。")
    }

    // 未授权的请求会在 WWW-Authenticate 里告诉我们受保护资源元数据的地址
    private static func challengeMetadata(_ u: URL) async -> String? {
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "OSVIA", "version": "1"]]] as [String: Any])
        guard let (_, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse,
              let ch = h.value(forHTTPHeaderField: "WWW-Authenticate"),
              let range = ch.range(of: "resource_metadata=\"[^\"]+\"", options: .regularExpression) else { return nil }
        return String(ch[range]).replacingOccurrences(of: "resource_metadata=\"", with: "").replacingOccurrences(of: "\"", with: "")
    }

    private static func clientID(_ d: Discovery) async throws -> String {
        let key = "mcp.oauth.client." + d.authz
        if let c = DB.shared.kv(key), !c.isEmpty { return c }
        guard let reg = d.registration, let u = URL(string: reg) else {
            throw Fail(msg: "这个服务不支持自动注册登录。请在「访问授权」里手动填写访问令牌。")
        }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_name": "OSVIA", "redirect_uris": [redirect],
            "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
            "token_endpoint_auth_method": "none", "application_type": "native"] as [String: Any])
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let cid = j["client_id"] as? String else {
            throw Fail(msg: "服务器拒绝了自动注册。请在「访问授权」里手动填写访问令牌。")
        }
        DB.shared.setKV(key, cid)
        return cid
    }

    private static func web(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "osvia") { cb, err in
                if let cb { cont.resume(returning: cb) } else { cont.resume(throwing: err ?? Fail(msg: "登录没有完成。")) }
            }
            let a = Anchor()
            anchor = a
            s.presentationContextProvider = a
            session = s
            if !s.start() { cont.resume(throwing: Fail(msg: "无法打开登录页面。")) }
        }
    }

    private static func post(_ url: String, form: [String: String]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw Fail(msg: "令牌地址不正确。") }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 20
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        r.httpBody = form.map { k, v in k + "=" + (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v) }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else {
            throw Fail(msg: "换取令牌失败：" + ((j["error_description"] as? String) ?? (j["error"] as? String) ?? "服务器拒绝"))
        }
        return j
    }

    private static func json(_ s: String) async -> [String: Any]? {
        guard let u = URL(string: s) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 12
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func random(_ n: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var g = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count, using: &g)] })
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
