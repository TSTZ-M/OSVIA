import Foundation
import JavaScriptCore
import FoundationModels

@Generable
struct SkillDraft {
    @Guide(description: "技能名，4到8个汉字") var name: String
    @Guide(description: "一句话用途") var desc: String
    @Guide(description: "测试用的示例输入，一个简短字符串") var sample: String
    @Guide(description: "JavaScript 函数源码，形式 function(input){ ... return 字符串; }") var code: String
}

// 只放行一次：超时和正常结束谁先到谁生效
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// 脚本技能：自然语言描述 → 自动生成 → 自动测试运行 → 失败自动修复 → 保存。运行用系统自带的 JavaScriptCore。
// 生成代码优先用云端大脑（已填密钥时）和本地大模型（已下载时），否则用系统自带模型。
enum Skills {
    static let rules = """
    你是 JavaScript 工程师。写在 iPhone 内置 JavaScriptCore 里运行的脚本，优先写简单直接的同步代码。
    代码必须是单个函数表达式：function(input){ ... return 结果; }，input 是用户传入的字符串；返回字符串，或返回对象（会自动转成 JSON 文本）。
    可以用 ES2015 语法（const、let、箭头函数、模板字符串）、Math、Date、JSON、正则。不能用 setTimeout、require、import、fetch、XMLHttpRequest、document。
    可用的同步函数：
    httpGet(url, 请求头?)、httpPost(url, 请求体, 请求头?)：返回 {ok, status, body, headers}，只能访问公开 https 地址；fetchJSON(url) 返回解析后的对象；fetchText(url) 返回文本；readPage(url) 返回网页正文。
    store.get(键, 默认值)、store.set(键, 值)、store.remove(键)、store.keys()：这个脚本私有的持久存储，可存对象。
    notify(标题, 内容)：本机通知；bark(标题, 内容)：推送到 Bark。
    ask(提示, 系统指令?)：调用大模型，返回文本。kbSearch(关键词)：搜索知识库，返回字符串数组。calc("1+2*3")：精确计算。
    md5、sha1、sha256、hmac(密钥, 文本)、base64、unbase64、uuid()、formatDate(毫秒时间戳, "yyyy-MM-dd HH:mm")、csvParse(文本)、csvStringify(二维数组)。
    console.log 用于调试。必须有返回值。不要输出解释。
    """

    struct Template: Identifiable {
        let id: String
        let icon: String
        let title: String
        let desc: String
        let sample: String
        let code: String
    }

    static let templates: [Template] = [
        Template(id: "summary", icon: "doc.text.magnifyingglass", title: "网页摘要", desc: "读取网址正文，让大模型总结成三句话", sample: "https://example.com",
                 code: """
                 function(input) {
                   var url = input.trim();
                   if (!url) return "请输入网址";
                   var text = readPage(url);
                   if (!text) return "读取失败";
                   return ask("用三句话总结下面的网页内容：\n" + text.slice(0, 6000));
                 }
                 """),
        Template(id: "watch", icon: "eye", title: "网页变化监控", desc: "内容变了就通知（配合定时运行）", sample: "https://example.com",
                 code: """
                 function(input) {
                   var url = input.trim();
                   if (!url) return "请输入要监控的网址";
                   var text = readPage(url);
                   if (!text) return "读取失败";
                   var h = sha256(text);
                   var old = store.get("h:" + url, null);
                   store.set("h:" + url, h);
                   if (old === null) return "已开始监控，下次运行时对比";
                   if (old !== h) {
                     notify("网页有变化", url);
                     bark("网页有变化", url);
                     return "页面内容变了";
                   }
                   return "没有变化";
                 }
                 """),
        Template(id: "rate", icon: "dollarsign.arrow.circlepath", title: "汇率换算", desc: "输入「100 USD to CNY」得到实时汇率", sample: "100 USD to CNY",
                 code: """
                 function(input) {
                   var m = input.trim().toUpperCase().match(/([0-9.]+)\s*([A-Z]{3})\s*(?:TO|IN|->|=>)?\s*([A-Z]{3})/);
                   if (!m) return "格式：100 USD to CNY";
                   var d = fetchJSON("https://open.er-api.com/v6/latest/" + m[2]);
                   if (!d || !d.rates || !d.rates[m[3]]) return "查不到这组货币的汇率";
                   var v = parseFloat(m[1]) * d.rates[m[3]];
                   return m[1] + " " + m[2] + " ≈ " + v.toFixed(2) + " " + m[3];
                 }
                 """),
        Template(id: "api", icon: "network", title: "查询 JSON 接口", desc: "请求任意公开接口，返回前 2000 字", sample: "https://api.github.com/zen",
                 code: """
                 function(input) {
                   var r = httpGet(input.trim());
                   if (!r.ok) return "请求失败：" + (r.error || r.status);
                   return r.body.slice(0, 2000);
                 }
                 """),
        Template(id: "rewrite", icon: "text.badge.checkmark", title: "AI 改写", desc: "把输入的文字改成更正式、简洁的表达", sample: "这个事情我觉得吧可能得再看看",
                 code: """
                 function(input) {
                   if (!input.trim()) return "请输入要改写的文字";
                   return ask("把下面的文字改写得正式、简洁，保持原意，只输出结果：\n" + input);
                 }
                 """),
        Template(id: "csv", icon: "tablecells", title: "CSV 转 JSON", desc: "第一行当表头，转成对象数组", sample: "name,age\nTom,18\nAnn,20",
                 code: """
                 function(input) {
                   var rows = csvParse(input);
                   if (rows.length < 2) return "至少需要表头和一行数据";
                   var head = rows[0];
                   return rows.slice(1).map(function(r) {
                     var o = {};
                     head.forEach(function(h, i) { o[h] = r[i] === undefined ? "" : r[i]; });
                     return o;
                   });
                 }
                 """),
        Template(id: "count", icon: "number", title: "文本统计", desc: "字数、行数、词数一次看清", sample: "Hello world\n你好，世界",
                 code: """
                 function(input) {
                   var chars = input.replace(/\s/g, "").length;
                   var lines = input.split("\n").length;
                   var words = (input.match(/[A-Za-z0-9_']+/g) || []).length;
                   var han = (input.match(/[\u4e00-\u9fff]/g) || []).length;
                   return "字符 " + chars + "，行 " + lines + "，英文词 " + words + "，汉字 " + han;
                 }
                 """),
        Template(id: "hash", icon: "lock.rectangle", title: "哈希与编码", desc: "MD5、SHA-256、Base64 一起算", sample: "hello",
                 code: """
                 function(input) {
                   return ["MD5     " + md5(input), "SHA-256 " + sha256(input), "Base64  " + base64(input)].join("\n");
                 }
                 """),
        Template(id: "counter", icon: "plus.circle", title: "运行计数器", desc: "演示脚本私有存储：每次运行加一", sample: "",
                 code: """
                 function(input) {
                   var n = store.get("n", 0) + 1;
                   store.set("n", n);
                   return "这是第 " + n + " 次运行";
                 }
                 """),
        Template(id: "remind", icon: "bell", title: "发送提醒", desc: "运行时弹出本机通知（和 Bark）", sample: "站起来活动一下",
                 code: """
                 function(input) {
                   var text = input.trim() || "该休息一下了";
                   notify("提醒", text);
                   bark("提醒", text);
                   return "已发送：" + text;
                 }
                 """)
    ]

    static func list() -> [Row] { DB.shared.rows("SELECT name, desc, ts FROM skill ORDER BY ts DESC") }

    static func get(_ name: String) -> Row? { DB.shared.rows("SELECT name, desc, code, ts FROM skill WHERE name=?", [name]).first }

    static func exists(_ name: String) -> Bool { get(name) != nil }

    static func remove(_ name: String) {
        DB.shared.run("DELETE FROM skill WHERE name=?", [name])
        DB.shared.run("DELETE FROM chunk WHERE doc IN (SELECT id FROM doc WHERE name=?)", ["技能:" + name])
        DB.shared.run("DELETE FROM doc WHERE name=?", ["技能:" + name])
        for t in schedules(name) { Tasks.remove(t.i("id")) }
        ScriptEngine.clearStore(name)
    }

    static func save(_ name: String, _ desc: String, _ code: String) {
        DB.shared.run("INSERT OR REPLACE INTO skill(name,desc,code,ts) VALUES(?,?,?,?)", [name, desc, code, Date().timeIntervalSince1970])
        KB.shared.upsert("技能:" + name, desc + "（用 run_skill 调用：" + name + "）")
    }

    static func clean(_ code: String) -> String {
        var c = code
        for f in ["```javascript", "```js", "```JavaScript", "```"] { c = c.replacingOccurrences(of: f, with: "") }
        c = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasSuffix(";") { c.removeLast() }
        return c
    }

    // MARK: 运行
    static let testName = "~test"

    // 同步执行（调用方放后台线程）。测试用的临时存储运行完就清掉
    static func exec(_ code: String, _ input: String, name: String = testName) -> ScriptEngine.Outcome {
        let r = ScriptEngine.run(code: code, input: input, name: name)
        if name == testName { ScriptEngine.clearStore(testName) }
        return r
    }

    // 返回（是否成功，输出或人话报错）
    static func runCode(_ code: String, _ input: String) -> (Bool, String) {
        let r = exec(code, input)
        return (r.ok, r.output)
    }

    static func run(_ name: String, _ input: String) -> (Bool, String) {
        let r = runFull(name, input)
        return (r.ok, r.output)
    }

    static func runFull(_ name: String, _ input: String) -> ScriptEngine.Outcome {
        guard let code = get(name)?.s("code"), !code.isEmpty else {
            return ScriptEngine.Outcome(ok: false, output: "没有找到这个技能", logs: [], ms: 0)
        }
        let r = exec(code, input, name: name)
        record(name, input, r)
        return r
    }

    // 超时放弃等待的线程仍在运行；累计卡住 3 个就拒绝再运行，避免把后台线程占满
    private final class Stuck: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add(_ d: Int) {
            lock.lock()
            n += d
            lock.unlock()
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return n
        }
    }
    private static let stuck = Stuck()

    // 在后台线程运行并限时：脚本死循环或网络很慢时不会卡住界面，超时就放弃等待
    static func runAsyncFull(_ name: String, _ input: String, timeout: Double = 30) async -> ScriptEngine.Outcome {
        if stuck.count >= 3 {
            return ScriptEngine.Outcome(ok: false, output: "有脚本卡住没有结束。请完全退出并重新打开 OSVIA 后再试。", logs: [], ms: 0)
        }
        return await withCheckedContinuation { (c: CheckedContinuation<ScriptEngine.Outcome, Never>) in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Skills.runFull(name, input)
                if once.claim() { c.resume(returning: r) } else { stuck.add(-1) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() {
                    stuck.add(1)
                    c.resume(returning: ScriptEngine.Outcome(ok: false, output: "脚本运行超时（超过 \(Int(timeout)) 秒），已放弃等待。", logs: [], ms: Int(timeout * 1000)))
                }
            }
        }
    }

    static func runAsync(_ name: String, _ input: String, timeout: Double = 30) async -> (Bool, String) {
        let r = await runAsyncFull(name, input, timeout: timeout)
        return (r.ok, r.output)
    }

    // 测试运行一段还没保存的代码（编辑器、创建流程用）
    static func testAsync(_ code: String, _ input: String, timeout: Double = 30) async -> ScriptEngine.Outcome {
        if stuck.count >= 3 {
            return ScriptEngine.Outcome(ok: false, output: "有脚本卡住没有结束。请完全退出并重新打开 OSVIA 后再试。", logs: [], ms: 0)
        }
        return await withCheckedContinuation { (c: CheckedContinuation<ScriptEngine.Outcome, Never>) in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Skills.exec(code, input)
                if once.claim() { c.resume(returning: r) } else { stuck.add(-1) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() {
                    stuck.add(1)
                    c.resume(returning: ScriptEngine.Outcome(ok: false, output: "脚本运行超时（超过 \(Int(timeout)) 秒），已放弃等待。", logs: [], ms: Int(timeout * 1000)))
                }
            }
        }
    }

    // MARK: 最近一次运行记录
    struct LastRun {
        var date: Date
        var ok: Bool
        var output: String
        var logs: [String]
        var ms: Int
    }

    private static func record(_ name: String, _ input: String, _ r: ScriptEngine.Outcome) {
        let o: [String: Any] = ["ts": Date().timeIntervalSince1970, "ok": r.ok, "out": String(r.output.prefix(2000)), "logs": Array(r.logs.prefix(60)), "ms": r.ms]
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        DB.shared.setKV("skill.last." + name, s)
    }

    static func lastRun(_ name: String) -> LastRun? {
        guard let s = DB.shared.kv("skill.last." + name), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ts = o["ts"] as? Double else { return nil }
        return LastRun(date: Date(timeIntervalSince1970: ts), ok: o["ok"] as? Bool ?? false, output: o["out"] as? String ?? "",
                       logs: o["logs"] as? [String] ?? [], ms: o["ms"] as? Int ?? 0)
    }

    // MARK: 定时运行：复用「定时任务」，到点前在 OSVIA 里算好结果，由系统通知准时送达
    static func schedules(_ name: String) -> [Row] {
        Tasks.list().filter { $0.s("instr").hasPrefix("skill:" + name + "|") && $0.i("state") == 0 }
    }

    @discardableResult
    static func schedule(_ name: String, input: String, at: Date, rep: Int) -> Int64 {
        Tasks.add("脚本：" + name, "skill:" + name + "|" + input, at, useModel: true, rep: rep)
    }

    // 任务里的「skill:名字|输入」：返回运行结果
    static func runTask(_ instr: String) async -> String {
        let rest = String(instr.dropFirst(6))
        let parts = rest.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts.first.map(String.init) ?? ""
        let input = parts.count > 1 ? String(parts[1]) : ""
        let r = await runAsyncFull(name, input, timeout: 40)
        let out = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok ? out : L10n.f("脚本「{}」运行失败：{}", name, out)
    }

    // MARK: 导出
    static func exportPack(_ names: [String]) -> URL? {
        let items = names.compactMap { n -> [String: String]? in
            guard let r = get(n) else { return nil }
            return ["name": n, "desc": r.s("desc"), "code": r.s("code")]
        }
        guard !items.isEmpty, let d = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(names.count == 1 ? "\(names[0]).osvskill.json" : "OSVIA-skills.json")
        do {
            try d.write(to: u, options: .atomic)
            return u
        } catch {
            return nil
        }
    }

    typealias Draft = (name: String, desc: String, sample: String, code: String)

    // 大模型（云端或本地）：用分段格式而不是 JSON，多行代码不会因为转义出错
    static func parseDraft(_ t: String) -> Draft? {
        guard let cr = t.range(of: "CODE:") else { return nil }
        let head = String(t[..<cr.lowerBound])
        let code = String(t[cr.upperBound...])
        func field(_ k: String) -> String {
            guard let r = head.range(of: k + ":") else { return "" }
            let rest = head[r.upperBound...]
            let line = rest.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return line.trimmingCharacters(in: .whitespaces)
        }
        let name = field("NAME")
        let desc = field("DESC")
        let sample = field("SAMPLE")
        guard !name.isEmpty, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (name, desc.isEmpty ? name : desc, sample, code)
    }

    private static func localDraft(_ spec: String, _ last: String, _ err: String, _ attempt: Int) async -> Draft? {
        var prompt = "需求：" + spec + "\n\n严格按下面的格式输出，不要输出别的：\nNAME: 技能名（4到8个汉字）\nDESC: 一句话用途\nSAMPLE: 测试用的示例输入\nCODE:\nfunction(input){ ... return 字符串; }"
        if attempt > 1 { prompt += "\n\n上次的代码：\n" + last + "\n运行结果：" + err + "\n请修复后重新按格式输出。" }
        guard let text = await LLM.complete(instructions: rules, prompt: prompt, maxTokens: 900, temperature: 0.2) else { return nil }
        return parseDraft(text)
    }

    // 创建并运行：最多尝试 3 次，失败时把错误交还模型修复
    static func create(_ spec: String, progress: @escaping (String) -> Void) async -> (name: String, ok: Bool, out: String) {
        var last = ""
        var err = ""
        let local = await LLM.localAvailable()
        for attempt in 1...3 {
            progress(attempt == 1 ? "正在编写脚本…" : "正在修复脚本（第 \(attempt) 次尝试）…")
            var draft: Draft?
            if local {
                draft = await localDraft(spec, last, err, attempt)
            } else {
                var prompt = "需求：" + spec
                if attempt > 1 { prompt += "\n上次的代码：\n" + last + "\n运行结果：" + err + "\n请修复后重新输出。" }
                let s = LanguageModelSession(instructions: rules)
                if let g = try? await s.respond(to: prompt, generating: SkillDraft.self).content {
                    draft = (g.name, g.desc, g.sample, g.code)
                }
            }
            guard let d = draft else {
                err = "模型没有返回内容"
                continue
            }
            last = clean(d.code)
            progress("正在测试运行…")
            let r = await testAsync(last, d.sample, timeout: 45)
            if r.ok {
                save(d.name, d.desc, last)
                return (d.name, true, r.output)
            }
            err = r.output
        }
        return ("", false, err)
    }

    // 导入技能包：[{"name","desc","code"}]，也接受单个对象；返回导入数量
    @discardableResult
    static func importPack(_ url: URL) -> Int {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        struct S: Decodable { let name: String; let desc: String?; let code: String }
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let dec = JSONDecoder()
        let list = (try? dec.decode([S].self, from: data)) ?? (try? dec.decode(S.self, from: data)).map { [$0] } ?? []
        var n = 0
        for s in list where !s.name.trimmingCharacters(in: .whitespaces).isEmpty && !s.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            save(s.name.trimmingCharacters(in: .whitespaces), s.desc ?? s.name, s.code)
            n += 1
        }
        return n
    }
}
