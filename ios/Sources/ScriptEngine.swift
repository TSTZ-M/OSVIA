import Foundation
import JavaScriptCore
import CryptoKit

// MARK: 脚本引擎：系统自带的 JavaScriptCore 沙盒 + 一组受限的原生函数
// 脚本看不到屏幕、文件和别的 App；联网只允许 https 公开地址；存储、通知、调用大模型都有次数上限。
final class ScriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var http = 0
    var asks = 0
    var notes = 0
    var slept = 0

    func log(_ s: String) {
        lock.lock()
        if lines.count < 200 { lines.append(String(s.prefix(2000))) }
        lock.unlock()
    }

    var logs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

// 跨线程交接结果用，避免闭包直接修改外面的变量
private final class Slot: @unchecked Sendable {
    var text = ""
    var data: Data?
    var resp: URLResponse?
    var error: Error?
}

enum ScriptEngine {
    struct Outcome {
        var ok: Bool
        var output: String
        var logs: [String]
        var ms: Int
    }

    static let maxHTTP = 20
    static let maxAsk = 3
    static let maxNotify = 3

    // MARK: 一段 JS 里把原生函数包装成顺手的写法
    private static let prelude = """
    var console={log:__log,info:__log,warn:__log,error:__log,debug:__log};
    var window={};
    var __n=0;function __tick(){if((++__n&1023)===0)__chk(__n)}
    var setTimeout=function(f){try{f()}catch(e){};return 0};
    var setInterval=function(){return 0};
    var clearTimeout=function(){};
    function httpGet(u,h){return __http('GET',String(u),'',h||{})}
    function httpPost(u,b,h){return __http('POST',String(u),(typeof b==='string')?b:JSON.stringify(b==null?{}:b),h||{})}
    function httpPut(u,b,h){return __http('PUT',String(u),(typeof b==='string')?b:JSON.stringify(b==null?{}:b),h||{})}
    function httpDelete(u,h){return __http('DELETE',String(u),'',h||{})}
    function fetchJSON(u,h){var r=httpGet(u,h);try{return JSON.parse(r.body)}catch(e){return null}}
    function ask(p,s){return __ask(String(p),s?String(s):'')}
    var store={
      get:function(k,d){var v=__storeGet(String(k));if(v===null||v===undefined)return d===undefined?null:d;try{return JSON.parse(v)}catch(e){return v}},
      set:function(k,v){return __storeSet(String(k),JSON.stringify(v))},
      remove:function(k){return __storeDel(String(k))},
      keys:function(){return __storeKeys()}
    };
    var params={};
    try{var __p=JSON.parse(__input);if(__p&&typeof __p==='object')params=__p}catch(e){}
    """

    static func blockedHost(_ h: String) -> Bool {
        let host = h.lowercased()
        if host == "localhost" || !host.contains(".") || host.contains(":") { return true }
        for s in [".local", ".internal", ".lan", ".home.arpa", ".localdomain"] where host.hasSuffix(s) { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        if p.count == 4 {
            if p[0] == 10 || p[0] == 127 || p[0] == 0 || p[0] >= 224 { return true }
            if p[0] == 169 && p[1] == 254 { return true }
            if p[0] == 192 && p[1] == 168 { return true }
            if p[0] == 172 && (16...31).contains(p[1]) { return true }
            if p[0] == 100 && (64...127).contains(p[1]) { return true }
        }
        return false
    }

    private static func failDict(_ msg: String) -> [String: Any] {
        ["ok": false, "status": 0, "body": "", "error": msg, "headers": [String: String]()]
    }

    // 同步请求：脚本是同步写法，所以这里阻塞当前（后台）线程，最多 12 秒
    static func request(_ method: String, _ urlStr: String, body: String, headers: [String: Any], box: ScriptBox) -> [String: Any] {
        box.http += 1
        guard box.http <= maxHTTP else { return failDict("联网次数太多：每次运行最多 \(maxHTTP) 次") }
        guard let url = URL(string: urlStr), url.scheme == "https", let host = url.host, !blockedHost(host) else {
            return failDict("只能访问公开的 https 地址")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("OSVIA-Script/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            let key = k.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !["host", "content-length"].contains(key.lowercased()), let s = v as? String else { continue }
            req.setValue(s, forHTTPHeaderField: key)
        }
        if method != "GET" && !body.isEmpty {
            req.httpBody = Data(body.utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                let t = body.trimmingCharacters(in: .whitespaces)
                req.setValue(t.hasPrefix("{") || t.hasPrefix("[") ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        let slot = Slot()
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: req) { d, r, e in
            slot.data = d
            slot.resp = r
            slot.error = e
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 12) == .timedOut {
            task.cancel()
            return failDict("请求超时")
        }
        if let e = slot.error { return failDict(e.localizedDescription) }
        let code = (slot.resp as? HTTPURLResponse)?.statusCode ?? 0
        var hs: [String: String] = [:]
        for (k, v) in (slot.resp as? HTTPURLResponse)?.allHeaderFields ?? [:] {
            if let k = k as? String, let v = v as? String { hs[k.lowercased()] = v }
        }
        let text = String(decoding: (slot.data ?? Data()).prefix(400_000), as: UTF8.self)
        return ["ok": (200..<300).contains(code), "status": code, "body": text, "headers": hs]
    }

    // MARK: 脚本私有存储（数据库 kv 表）：每个脚本最多 200 项，每项最多 64KB
    private static func kvPrefix(_ name: String) -> String { "skill.kv.\(name)." }

    static func storeKeys(_ name: String) -> [String] {
        let p = kvPrefix(name)
        return DB.shared.rows("SELECT k FROM kv WHERE substr(k,1,?)=?", [p.unicodeScalars.count, p]).map { String($0.s("k").dropFirst(p.count)) }
    }

    static func clearStore(_ name: String) {
        let p = kvPrefix(name)
        DB.shared.run("DELETE FROM kv WHERE substr(k,1,?)=?", [p.unicodeScalars.count, p])
        DB.shared.run("DELETE FROM kv WHERE k=?", ["skill.last." + name])
    }

    // MARK: 文本化：对象转 JSON
    private static func jsText(_ v: JSValue) -> String {
        if v.isString { return v.toString() ?? "" }
        if v.isUndefined { return "undefined" }
        if v.isNull { return "null" }
        if v.isObject, let j = v.context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [v]), j.isString {
            return j.toString() ?? ""
        }
        return v.toString() ?? ""
    }

    private static func hex<D: Sequence>(_ d: D) -> String where D.Element == UInt8 {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private static func looksLikeFunction(_ code: String) -> Bool {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("function") || t.hasPrefix("(") || t.hasPrefix("async") || t.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*\\s*=>", options: .regularExpression) != nil
    }

    // MARK: 运行（阻塞，调用方放到后台线程）
    static func run(code: String, input: String, name: String) -> Outcome {
        let t0 = Date()
        let box = ScriptBox()
        func done(_ ok: Bool, _ out: String) -> Outcome {
            Outcome(ok: ok, output: out, logs: box.logs, ms: Int(Date().timeIntervalSince(t0) * 1000))
        }
        guard let ctx = JSContext() else { return done(false, "脚本环境创建失败") }
        var err = ""
        ctx.exceptionHandler = { _, e in err = e?.toString() ?? "" }

        // 日志与联网
        let logB: @convention(block) () -> Void = {
            let args = (JSContext.currentArguments() as? [JSValue]) ?? []
            box.log(args.map { jsText($0) }.joined(separator: " "))
        }
        let httpB: @convention(block) (String, String, String, JSValue) -> [String: Any] = { m, u, b, h in
            request(m, u, body: b, headers: (h.toDictionary() as? [String: Any]) ?? [:], box: box)
        }
        let fetchB: @convention(block) (String) -> String = { u in
            let r = request("GET", u, body: "", headers: [:], box: box)
            return (r["body"] as? String) ?? ""
        }
        let pageB: @convention(block) (String) -> String = { u in
            box.http += 1
            guard box.http <= maxHTTP, let url = URL(string: u), url.scheme == "https", let host = url.host, !blockedHost(host) else { return "" }
            let slot = Slot()
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                let r = await WebText.extract(url, limit: 60_000)
                slot.text = (r.title.isEmpty ? "" : r.title + "\n\n") + r.text
                sem.signal()
            }
            return sem.wait(timeout: .now() + 20) == .timedOut ? "" : slot.text
        }
        let kbB: @convention(block) (String) -> [String] = { KB.shared.search($0, k: 3) }

        // 存储
        let sGet: @convention(block) (String) -> String? = { k in
            DB.shared.kv("skill.kv.\(name).\(k)")
        }
        let sSet: @convention(block) (String, String) -> Bool = { k, v in
            guard !k.isEmpty, k.count <= 100, v.utf8.count <= 65_536 else { return false }
            let full = "skill.kv.\(name).\(k)"
            if DB.shared.kv(full) == nil, storeKeys(name).count >= 200 { return false }
            DB.shared.setKV(full, v)
            return true
        }
        let sDel: @convention(block) (String) -> Bool = { k in
            DB.shared.run("DELETE FROM kv WHERE k=?", ["skill.kv.\(name).\(k)"])
            return true
        }
        let sKeys: @convention(block) () -> [String] = { storeKeys(name) }

        // 通知、Bark、大模型、计算
        let notifyB: @convention(block) (String, String) -> Bool = { t, b in
            guard box.notes < maxNotify else { return false }
            box.notes += 1
            let title = String(t.prefix(60)), body = String(b.prefix(300))
            Task {
                await Sys.ensureNotif()
                Sys.notify(id: "script-\(UUID().uuidString)", title: title, body: body, at: Date().addingTimeInterval(2))
            }
            return true
        }
        let barkB: @convention(block) (String, String) -> Bool = { t, b in
            guard Bark.ready, box.notes < maxNotify else { return false }
            box.notes += 1
            let title = String(t.prefix(60)), body = String(b.prefix(300))
            Task { _ = await Bark.send(.agent, title: title, body: body) }
            return true
        }
        let askB: @convention(block) (String, String) -> String = { p, s in
            guard box.asks < maxAsk else { return "（一次运行最多调用 \(maxAsk) 次 ask）" }
            box.asks += 1
            let slot = Slot()
            let sem = DispatchSemaphore(value: 0)
            let ins = s.isEmpty ? "你是简洁的助手，用用户使用的语言直接回答，不要寒暄。" : s
            Task.detached {
                slot.text = await AI.oneShot(ins, String(p.prefix(12_000)), maxTokens: 700, local: false) ?? ""
                sem.signal()
            }
            return sem.wait(timeout: .now() + 45) == .timedOut ? "" : slot.text
        }
        let calcB: @convention(block) (String) -> String = { e in
            guard let v = Calc.eval(e) else { return "" }
            return Calc.format(v)
        }

        // 工具函数
        let md5B: @convention(block) (String) -> String = { hex(Insecure.MD5.hash(data: Data($0.utf8))) }
        let sha1B: @convention(block) (String) -> String = { hex(Insecure.SHA1.hash(data: Data($0.utf8))) }
        let sha256B: @convention(block) (String) -> String = { hex(SHA256.hash(data: Data($0.utf8))) }
        let hmacB: @convention(block) (String, String) -> String = { k, m in
            hex(HMAC<SHA256>.authenticationCode(for: Data(m.utf8), using: SymmetricKey(data: Data(k.utf8))))
        }
        let b64B: @convention(block) (String) -> String = { Data($0.utf8).base64EncodedString() }
        let unb64B: @convention(block) (String) -> String = { s in
            guard let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        let uuidB: @convention(block) () -> String = { UUID().uuidString.lowercased() }
        let randB: @convention(block) (Int) -> Int = { n in n > 0 ? Int.random(in: 0..<n) : 0 }
        let dateB: @convention(block) (Double, String) -> String = { ms, f in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f.isEmpty ? "yyyy-MM-dd HH:mm:ss" : f
            return df.string(from: Date(timeIntervalSince1970: ms / 1000))
        }
        let csvInB: @convention(block) (String) -> [[String]] = { Convert.csvParse($0, ",") }
        let csvOutB: @convention(block) (JSValue) -> String = { v in
            let rows = ((v.toArray() as? [[Any]]) ?? []).map { $0.map { "\($0)" } }
            return Convert.csvOut(rows, ",")
        }
        let sleepB: @convention(block) (Int) -> Void = { ms in
            let n = min(max(ms, 0), 2000)
            guard box.slept + n <= 5000 else { return }
            box.slept += n
            Thread.sleep(forTimeInterval: Double(n) / 1000)
        }

        // 循环计数：次数或时间超限就在脚本里抛错，让死循环自己停下
        let chkB: @convention(block) (Int) -> Void = { n in
            guard n > LoopGuard.maxTicks || Date().timeIntervalSince(t0) > LoopGuard.maxSeconds, let c = JSContext.current() else { return }
            c.exception = JSValue(newErrorFromMessage: "脚本运行时间过长，已中止（可能有死循环）", in: c)
        }

        func set(_ n: String, _ v: Any) { ctx.setObject(v, forKeyedSubscript: n as NSString) }
        set("__log", logB); set("__http", httpB); set("fetchText", fetchB); set("readPage", pageB); set("kbSearch", kbB)
        set("__storeGet", sGet); set("__storeSet", sSet); set("__storeDel", sDel); set("__storeKeys", sKeys)
        set("notify", notifyB); set("bark", barkB); set("__ask", askB); set("calc", calcB)
        set("md5", md5B); set("sha1", sha1B); set("sha256", sha256B); set("hmac", hmacB)
        set("base64", b64B); set("unbase64", unb64B); set("uuid", uuidB); set("secureRandom", randB)
        set("formatDate", dateB); set("csvParse", csvInB); set("csvStringify", csvOutB); set("sleep", sleepB)
        set("__input", input); set("__chk", chkB)
        ctx.evaluateScript(prelude)
        err = ""

        // 代码可以是函数表达式，也可以是直接写函数体（用 input 和 return）
        // 先用带循环保护的版本编译，失败再退回原代码
        func compile(_ c: String) -> String? {
            err = ""
            ctx.evaluateScript("var skill = (\(c));")
            if err.isEmpty { return nil }
            let first = err
            err = ""
            ctx.evaluateScript("var skill = (function(input){\n\(c)\n});")
            return err.isEmpty ? nil : (looksLikeFunction(c) ? first : err)
        }
        let guarded = LoopGuard.instrument(code)
        var failure = compile(guarded)
        if failure != nil, guarded != code { failure = compile(code) }
        if let failure { return done(false, friendly(failure)) }
        err = ""
        guard let fn = ctx.objectForKeyedSubscript("skill"), !fn.isUndefined, !fn.isNull else { return done(false, "脚本里没有找到函数") }
        var r = fn.call(withArguments: [input])
        if !err.isEmpty { return done(false, friendly(err)) }

        // async / Promise：这里的原生函数都是同步的，微任务在每次执行后会自动跑完
        if let v = r, v.isObject, v.hasProperty("then") {
            ctx.evaluateScript("var __pd=false,__pv,__pe;")
            let okFn = ctx.evaluateScript("(function(v){__pv=v;__pd=true})")
            let badFn = ctx.evaluateScript("(function(e){__pe=e;__pd=true})")
            v.invokeMethod("then", withArguments: [okFn as Any, badFn as Any])
            for _ in 0..<60 where ctx.objectForKeyedSubscript("__pd")?.toBool() != true { ctx.evaluateScript("0") }
            guard ctx.objectForKeyedSubscript("__pd")?.toBool() == true else {
                return done(false, "脚本里的异步操作没有完成。这里没有定时器，请改成同步写法。")
            }
            if let e = ctx.objectForKeyedSubscript("__pe"), !e.isUndefined { return done(false, friendly(e.toString() ?? "脚本出错")) }
            r = ctx.objectForKeyedSubscript("__pv")
        }
        if !err.isEmpty { return done(false, friendly(err)) }

        let out: String
        if let r, !r.isUndefined, !r.isNull {
            out = r.isString ? (r.toString() ?? "") : (r.isObject ? jsText(r) : (r.toString() ?? ""))
        } else {
            out = ""
        }
        return out.isEmpty ? done(false, "脚本没有返回结果") : done(true, out)
    }
}
