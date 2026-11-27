import Foundation
import FoundationModels

// MARK: 一次性生成：云端大脑 → 本地大模型 → 系统模型（整理记忆、提炼事实用）
enum AI {
    @MainActor
    // local：是否允许用本地大模型（MLX）。后台自动做的事（邮件分拣、更新画像）传 false：
    // 加载几个 GB 的模型会和界面抢内存，容易被系统杀掉；这类任务走云端或系统自带模型，都没有就不做。
    static func oneShot(_ ins: String, _ prompt: String, maxTokens: Int = 900, local: Bool = true, cloud: Bool = true) async -> String? {
        if cloud && CloudLLM.ready {
            let msgs: [[String: String]] = [["role": "system", "content": ins], ["role": "user", "content": prompt]]
            if let r = try? await CloudLLM.stream(msgs, maxTokens: maxTokens, temperature: 0.2, onText: { _ in }), !r.isEmpty { return r }
        }
        if local, let r = await LLM.complete(instructions: ins, prompt: prompt, maxTokens: maxTokens, temperature: 0.2) { return r }
        if case .available = SystemLanguageModel.default.availability {
            return try? await LanguageModelSession(instructions: ins).respond(to: prompt).content
        }
        return nil
    }

    // 有没有任何可用的模型
    @MainActor
    static func available() async -> Bool {
        if CloudLLM.ready { return true }
        if await LLM.localAvailable() { return true }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}

struct MemItem: Identifiable, Equatable {
    let id = UUID()
    var cat: String
    var text: String
}

// MARK: 记忆库：跨 AI 汇集的「关于用户」的长期信息，每次对话都会自然地用上
enum Memory {
    static let cats = ["个人", "偏好", "工作", "项目", "人际", "其他"]

    static func icon(_ c: String) -> String {
        switch c {
        case "个人": return "person.crop.circle"
        case "偏好": return "heart"
        case "工作": return "briefcase"
        case "项目": return "hammer"
        case "人际": return "person.2"
        default: return "tray"
        }
    }

    static func all() -> [Row] {
        DB.shared.rows("SELECT id, text, cat, src, ts, pin FROM memory ORDER BY pin DESC, ts DESC, id DESC")
    }

    static func count() -> Int { DB.shared.rows("SELECT COUNT(*) AS n FROM memory").first?.i("n") ?? 0 }

    // MARK: 去重用的相似度（字二元组的 Jaccard）
    private static func norm(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }

    private static func grams(_ s: String) -> Set<String> {
        let c = Array(norm(s))
        guard c.count > 1 else { return Set(c.map { String($0) }) }
        return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    // MARK: 分类
    static func mapCat(_ s: String) -> String? {
        let t = s.lowercased()
        if cats.contains(s) { return s }
        let table: [(String, [String])] = [
            ("个人", ["个人", "身份", "背景", "自我", "基本", "关于我", "personal", "identity", "about", "background", "profile", "demographic", "location"]),
            ("偏好", ["偏好", "喜好", "习惯", "风格", "兴趣", "爱好", "prefer", "like", "habit", "style", "interest", "hobby", "communication"]),
            ("工作", ["工作", "职业", "职场", "技能", "学习", "专业", "教育", "work", "career", "professional", "job", "skill", "education", "study"]),
            ("项目", ["项目", "正在做", "目标", "计划", "project", "goal", "plan", "ongoing"]),
            ("人际", ["人际", "关系", "家人", "朋友", "同事", "relationship", "people", "family", "friend", "social", "contact"]),
            ("其他", ["其他", "其它", "杂项", "other", "misc", "general"])
        ]
        for (c, ks) in table where ks.contains(where: { t.contains($0) }) { return c }
        return nil
    }

    static func guess(_ text: String) -> String {
        let t = text.lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { t.contains($0) } }
        if has(["朋友", "家人", "妻子", "老婆", "老公", "丈夫", "女朋友", "男朋友", "孩子", "儿子", "女儿", "同事", "老板", "父母", "girlfriend", "boyfriend", "wife", "husband", "friend", "colleague", "my son", "my daughter"]) { return "人际" }
        if has(["项目", "正在做", "正在开发", "仓库", "上架", "app store", "project", "building", "working on", "repo"]) { return "项目" }
        if has(["喜欢", "偏好", "习惯", "不喜欢", "讨厌", "爱吃", "希望", "回答", "风格", "prefer", "likes", "dislike", "enjoy", "favorite", "style"]) { return "偏好" }
        if has(["工程师", "公司", "职业", "工作", "岗位", "技术栈", "开发", "设计师", "学生", "专业", "engineer", "developer", "designer", "works at", "student", "career", "skills"]) { return "工作" }
        if has(["住在", "来自", "生日", "名字", "叫", "岁", "性别", "语言", "位于", "lives in", "born", "name is", "years old", "from "]) { return "个人" }
        return "其他"
    }

    // MARK: 增删改
    @discardableResult
    static func add(_ text: String, cat: String? = nil, src: String = "手动", pin: Bool = false) -> Bool {
        addMany([MemItem(cat: cat ?? "", text: text)], src: src, pin: pin) > 0
    }

    // 批量写入：跳过和已有记忆高度相似的；返回新增条数
    @discardableResult
    static func addMany(_ items: [MemItem], src: String, pin: Bool = false) -> Int {
        addManyIDs(items, src: src, pin: pin).count
    }

    // 同上，返回新增的记忆编号（用于「撤销导入」）
    static func addManyIDs(_ items: [MemItem], src: String, pin: Bool = false) -> [Int] {
        var existing = DB.shared.rows("SELECT text FROM memory").map { grams($0.s("text")) }
        var ids: [Int] = []
        let now = Date().timeIntervalSince1970
        for it in items {
            let t = String(it.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
            guard t.count >= 3 else { continue }
            let g = grams(t)
            if existing.contains(where: { jaccard($0, g) >= 0.7 }) { continue }
            existing.append(g)
            let c = cats.contains(it.cat) ? it.cat : guess(t)
            let id = DB.shared.run("INSERT INTO memory(text,cat,src,ts,pin) VALUES(?,?,?,?,?)", [t, c, src, now - Double(ids.count) * 0.001, pin ? 1 : 0])
            if id > 0 { ids.append(Int(id)) }
        }
        return ids
    }

    static func removeMany(_ ids: [Int]) {
        for id in ids { DB.shared.run("DELETE FROM memory WHERE id=?", [id]) }
    }

    static func remove(_ id: Int) { DB.shared.run("DELETE FROM memory WHERE id=?", [id]) }

    static func update(_ id: Int, text: String, cat: String) {
        DB.shared.run("UPDATE memory SET text=?, cat=? WHERE id=?", [String(text.prefix(400)), cat, id])
    }

    static func setPin(_ id: Int, _ on: Bool) { DB.shared.run("UPDATE memory SET pin=? WHERE id=?", [on ? 1 : 0, id]) }

    static func clear() { DB.shared.run("DELETE FROM memory") }

    // MARK: 检索与注入
    private static let stop: Set<Character> = ["的", "了", "是", "在", "我", "你", "他", "她", "它", "吗", "呢", "吧", "啊", "和", "与", "有", "就", "也", "都", "要", "会", "能", "可", "以", "不", "这", "那", "个", "么", "什", "一", "下", "请", "帮"]

    // 检索词：中文的相邻两字（遇到停用字断开）+ 英文数字单词
    private static func terms(_ s: String) -> Set<String> {
        var out = Set<String>()
        var word = ""
        var prev: Character?
        func flush() {
            if word.count >= 2 { out.insert(word) }
            word = ""
        }
        for ch in s.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                word.append(ch)
                prev = nil
                continue
            }
            flush()
            if ch.isLetter && !ch.isASCII && !stop.contains(ch) {
                if let p = prev { out.insert(String([p, ch])) }
                prev = ch
            } else {
                prev = nil
            }
        }
        flush()
        return out
    }

    // 按词的稀有程度加权打分（越少见的词命中越有价值），取最相关的几条
    static func relevant(_ q: String, k: Int = 6) -> [String] {
        let qt = terms(q)
        guard !qt.isEmpty else { return [] }
        let rows = all()
        guard !rows.isEmpty else { return [] }
        let docs = rows.map { terms($0.s("text")) }
        var df: [String: Int] = [:]
        for d in docs { for t in d { df[t, default: 0] += 1 } }
        let n = Double(rows.count)
        var scored: [(Double, String)] = []
        for (i, r) in rows.enumerated() {
            var sc = 0.0
            for t in qt where docs[i].contains(t) { sc += log(1 + n / Double(df[t] ?? 1)) }
            if sc >= 2.0 { scored.append((sc + (r.i("pin") == 1 ? 0.5 : 0), r.s("text"))) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(k).map { $0.1 }
    }

    // 没有精确命中时的概览：置顶的 + 每个类别最近的几条
    static func overview(_ n: Int = 12) -> [String] {
        var out: [String] = []
        let rows = all()
        for r in rows where r.i("pin") == 1 { out.append(r.s("text")) }
        for c in cats {
            for r in rows.filter({ $0.s("cat") == c && $0.i("pin") == 0 }).prefix(3) { out.append(r.s("text")) }
        }
        return Array(out.prefix(n))
    }

    private static func asksAboutUser(_ q: String) -> Bool {
        let t = q.lowercased()
        return ["我是谁", "了解我", "关于我", "我的", "记得", "记忆", "记住", "我喜欢", "我平时", "我做", "我在", "之前", "我们", "who am i", "about me", "remember", "my "].contains { t.contains($0) }
    }

    // 注入系统提示词的「关于用户」：置顶 → 与问题相关的 → 每个类别轮流取几条做骨架，直到用满字数预算。
    // 这样即使问题和记忆没有共同词（比如「帮我写个自我介绍」），助理也始终知道你是谁。
    static func block(for q: String, budget: Int, recent: Bool, hint: Bool = false) -> (text: String, relevant: Int, lines: Int) {
        let rows = all()
        if rows.isEmpty { return ("", 0, 0) }
        var lines: [String] = []
        var used = 0
        func push(_ t: String) {
            let l = "- " + t
            if used + l.count > budget || lines.contains(l) { return }
            lines.append(l)
            used += l.count
        }
        for r in rows where r.i("pin") == 1 { push(r.s("text")) }
        let rel = relevant(q, k: asksAboutUser(q) ? 12 : 6)
        for t in rel { push(t) }
        var byCat: [String: [Row]] = [:]
        for r in rows where r.i("pin") == 0 { byCat[r.s("cat"), default: []].append(r) }
        let order = ["个人", "工作", "偏好", "项目", "人际", "其他"]
        var round = 0
        while used < budget && round < 10 {
            var any = false
            for c in order {
                if let list = byCat[c], round < list.count {
                    push(list[round].s("text"))
                    any = true
                }
            }
            if !any { break }
            round += 1
        }
        if lines.isEmpty { return ("", 0, 0) }
        var t = "【用户本人的资料】下面是用户自己导入或告诉过你的信息。用户问到自己（我是谁、我的…、你了解我什么）或需要个性化建议时，必须依据这些资料回答；无关时不要提及，也不要说「根据你的记忆」：\n" + lines.joined(separator: "\n")
        if hint && rows.count > lines.count { t += "\n（共 \(rows.count) 条记忆，以上是节选；要查更多细节调用 search_memory。）" }
        return (t, rel.count, lines.count)
    }

    // 不用任何模型，直接把记忆按类别整理成一段话（用户画像的保底版本）
    static func digest(maxChars: Int) -> String {
        let rows = all()
        var parts: [String] = []
        var used = 0
        for c in ["个人", "工作", "偏好", "项目", "人际", "其他"] {
            var items: [String] = []
            for r in rows where r.s("cat") == c || (c == "其他" && !cats.contains(r.s("cat"))) {
                let t = r.s("text").trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if used + t.count + 2 > maxChars { break }
                items.append(t)
                used += t.count + 2
            }
            if !items.isEmpty { parts.append(c + "：" + items.joined(separator: "；")) }
        }
        return parts.joined(separator: "。")
    }

    // MARK: 导出
    static func exportText() -> String {
        let rows = all()
        var out = "# \(Brand.name) 记忆\n"
        for c in cats {
            let items = rows.filter { $0.s("cat") == c }
            if items.isEmpty { continue }
            out += "\n## \(c)\n" + items.map { "- " + $0.s("text") }.joined(separator: "\n") + "\n"
        }
        return out
    }

    // 带着去其他 AI 的背景介绍
    static func pack(limit: Int = 3000) -> String {
        var out = "以下是我的背景与偏好（来自我的个人 AI 助理 \(Brand.name) 的记忆）。请在接下来的对话里自然地参考，不必逐条复述。\n"
        for r in all() {
            let l = "- [\(r.s("cat"))] " + r.s("text") + "\n"
            if out.count + l.count > limit { break }
            out += l
        }
        return out
    }

    // 让任何一个 AI 导出它记住的关于你的信息
    static let exportPrompt = """
    请把你记住的、关于我的所有信息完整导出，不要总结、不要省略、不要改写原意。
    Please export everything you remember about me, completely — do not summarize, omit, or reword.

    格式 / Format：只输出一个代码块，每条一行：
    - [类别] 内容
    类别只能是：个人、偏好、工作、项目、人际、其他
    (个人 identity & background, 偏好 preferences & habits, 工作 career & skills, 项目 ongoing projects & goals, 人际 relationships, 其他 other)

    要包含 / Include：身份与背景、所在地、使用的语言、职业与技能、正在做的项目、技术栈与常用工具、兴趣与偏好、沟通与写作风格、目标、重要的人与事，以及你「记忆」功能里保存的每一条原文。
    不要包含密码、证件号、银行卡号、API 密钥等机密。Do not include secrets (passwords, IDs, card numbers, API keys).
    代码块之外不要输出任何文字。Output nothing outside the code block.
    """

    // MARK: AI 整理（合并重复、修正分类）；整理前自动备份，可一键撤销
    static func consolidate() async -> String {
        let rows = all().filter { $0.i("pin") == 0 }
        guard rows.count >= 6 else { return "记忆还不多，不需要整理。" }
        guard await AI.available() else { return "需要先配置云端大脑或本地模型。" }
        let list = rows.prefix(150).map { "- [\($0.s("cat"))] " + $0.s("text") }.joined(separator: "\n")
        let ins = "你是记忆整理器。合并重复或高度相似的条目，修正分类，删除明显过期或没有信息量的条目，保留所有独立的事实，不要编造，不要改变原意，保持原语言。每条一行，格式「- [类别] 内容」，类别只能是 个人/偏好/工作/项目/人际/其他。只输出列表。"
        guard let out = await AI.oneShot(ins, list, maxTokens: 1800) else { return "模型没有返回结果，稍后再试。" }
        let items = MemoryImport.parse(out)
        guard items.count >= max(1, rows.count / 3) else { return "整理结果异常，已放弃，原有记忆没有改动。" }
        backup(rows)
        for r in rows { remove(r.i("id")) }
        let n = addMany(items, src: "AI 整理")
        return L10n.f("整理完成：{} 条 → {} 条。可在下方撤销。", "\(rows.count)", "\(n)")
    }

    private static func backup(_ rows: [Row]) {
        let arr = rows.map { ["text": $0.s("text"), "cat": $0.s("cat"), "src": $0.s("src")] }
        if let d = try? JSONSerialization.data(withJSONObject: arr), let s = String(data: d, encoding: .utf8) {
            DB.shared.setKV("memory.backup", s)
        }
    }

    static var hasBackup: Bool { !(DB.shared.kv("memory.backup") ?? "").isEmpty }

    static func undoConsolidate() -> Bool {
        guard let s = DB.shared.kv("memory.backup"), let d = s.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return false }
        let backupItems = arr.map { (MemItem(cat: $0["cat"] ?? "其他", text: $0["text"] ?? ""), $0["src"] ?? "手动") }
        DB.shared.run("DELETE FROM memory WHERE pin=0")
        for (it, src) in backupItems { addMany([it], src: src) }
        DB.shared.setKV("memory.backup", "")
        return true
    }
}

// MARK: 导入：解析其他 AI 导出的记忆（列表、Markdown、JSON），或从对话记录导出里提炼
enum MemoryImport {
    private static let preamble = ["好的", "当然", "以下是", "这是", "下面是", "我来", "希望", "如果你", "如有", "以上", "注意", "说明",
                                   "here is", "here are", "here's", "sure", "of course", "okay", "ok,", "i hope", "let me know", "note:", "below"]

    static func parse(_ raw: String) -> [MemItem] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        if t.hasPrefix("[") || t.hasPrefix("{"), let d = t.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) {
            let r = fromJSON(j)
            if !r.isEmpty { return r }
        }
        var cat: String?
        var out: [MemItem] = []
        for rawLine in t.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("```") || line == "---" { continue }
            let hasBullet = line.range(of: "^(?:[-*•+·]|\\d{1,3}[.)、])\\s+", options: .regularExpression) != nil
            if !hasBullet, let h = heading(line) {
                cat = Memory.mapCat(h)
                continue
            }
            if hasBullet {
                line = line.replacingOccurrences(of: "^(?:[-*•+·]|\\d{1,3}[.)、])\\s+", with: "", options: .regularExpression)
            } else {
                let low = line.lowercased()
                if preamble.contains(where: { low.hasPrefix($0) }) { continue }
            }
            // 日期前缀：[2025-01-02] 内容 / 2025-01-02: 内容
            line = line.replacingOccurrences(of: "^[\\[(（]?\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}[^\\]）)\\s]*[\\])）]?\\s*[-:：–—]?\\s*", with: "", options: .regularExpression)
            // 方括号类别：[偏好] 内容
            var lineCat = cat
            if let r = line.range(of: "^[\\[【(（]([^\\]】)）]{1,14})[\\]】)）]\\s*[:：-]?\\s*", options: .regularExpression) {
                let inner = String(line[r]).trimmingCharacters(in: CharacterSet(charactersIn: "[]【】()（）:：- "))
                if let c = Memory.mapCat(inner) {
                    lineCat = c
                    line = String(line[r.upperBound...])
                }
            }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            guard line.count >= 4, line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            let text = String(line.prefix(500))
            out.append(MemItem(cat: lineCat ?? Memory.guess(text), text: text))
        }
        return out
    }

    // 标题行：#、整行加粗、或短的以冒号结尾的行。返回标题文字
    private static func heading(_ line: String) -> String? {
        var t = line
        if t.hasPrefix("#") {
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            return t.isEmpty ? nil : t
        }
        if t.hasPrefix("**"), t.hasSuffix("**") || t.hasSuffix("**:") || t.hasSuffix("**：") {
            return t.trimmingCharacters(in: CharacterSet(charactersIn: "*:： "))
        }
        if t.count <= 24, t.hasSuffix(":") || t.hasSuffix("：") {
            return String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func fromJSON(_ j: Any) -> [MemItem] {
        var out: [MemItem] = []
        let keys = ["memory", "memories", "text", "content", "value", "summary", "fact", "facts", "items", "data"]
        func add(_ s: String, _ cat: String?) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 4 { out.append(MemItem(cat: cat ?? Memory.guess(t), text: String(t.prefix(500)))) }
        }
        func walk(_ v: Any, _ cat: String?, _ depth: Int) {
            if depth > 4 { return }
            if let s = v as? String {
                add(s, cat)
            } else if let a = v as? [Any] {
                for x in a { walk(x, cat, depth + 1) }
            } else if let o = v as? [String: Any] {
                if let k = keys.first(where: { o[$0] != nil }), let inner = o[k] {
                    let label = (o["category"] as? String) ?? (o["type"] as? String) ?? ""
                    walk(inner, Memory.mapCat(label) ?? cat, depth + 1)
                } else if depth == 0 {
                    for (k, val) in o { walk(val, Memory.mapCat(k) ?? cat, depth + 1) }
                }
            }
        }
        walk(j, nil, 0)
        return out
    }

    // MARK: 文件
    struct FileResult {
        var items: [MemItem] = []
        var chat: [String] = []      // 对话记录导出里「用户自己说的话」
        var raw = ""                 // 文件原文（最多 200 万字节），供「AI 提炼」使用
    }

    static func read(_ url: URL) -> FileResult {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url) else { return FileResult() }
        if let chat = ChatExport.userTexts(d), !chat.isEmpty { return FileResult(items: [], chat: chat) }
        let text = String(decoding: d.prefix(2_000_000), as: UTF8.self)
        return FileResult(items: parse(text), chat: [], raw: text)
    }

    // MARK: AI 提炼（把杂乱的文字或对话里的事实整理成干净的记忆）
    static let distillRules = "你是记忆整理器。从用户提供的内容里提取「关于用户本人」长期有效的事实、偏好、背景、正在做的项目、人际关系。只保留稳定且有用的信息；合并重复；删掉一次性的、已过期的、关于别人的闲聊和助手的客套话；不要编造；保持原语言；不要包含密码、证件号、银行卡号、密钥。每条一行，格式「- [类别] 内容」，类别只能是 个人/偏好/工作/项目/人际/其他，最多 40 条，只输出列表。"

    // 返回 nil：没有可用的模型
    @MainActor
    static func distill(_ raw: String, progress: @escaping (String) -> Void) async -> [MemItem]? {
        guard await AI.available() else { return nil }
        var batches: [String] = []
        var cur = ""
        for line in raw.components(separatedBy: .newlines) {
            if cur.count + line.count > 4500, !cur.isEmpty {
                batches.append(cur)
                cur = ""
            }
            cur += String(line.prefix(600)) + "\n"
        }
        if !cur.isEmpty { batches.append(cur) }
        var items: [MemItem] = []
        for (i, b) in batches.prefix(8).enumerated() {
            if Task.isCancelled { break }
            progress(L10n.f("正在提炼 {}/{}…", "\(i + 1)", "\(min(batches.count, 8))"))
            if let out = await AI.oneShot(distillRules, b, maxTokens: 1500) { items += parse(out) }
        }
        return items
    }
}

extension MemoryImport {
    struct QuickResult {
        var ids: [Int] = []
        var found = 0
        var error = ""
    }

    // 看起来已经是「每行一条」的列表、Markdown 或 JSON：直接解析，不需要 AI
    private static func looksStructured(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[") || t.hasPrefix("{") { return true }
        let lines = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("```") }
        guard lines.count >= 3 else { return false }
        let hits = lines.filter { $0.range(of: "^(?:[-*•+·]|\\d{1,3}[.)、]|[\\[【(（#])", options: .regularExpression) != nil }.count
        return Double(hits) / Double(lines.count) >= 0.5
    }

    // 一步到位：识别 → （必要时 AI 提炼）→ 去重写入。不再逐条确认，导入后可一键撤销。
    @MainActor
    static func quick(_ raw: String, chat: [String], source: String, progress: @escaping (String) -> Void) async -> QuickResult {
        var items: [MemItem] = []
        if chat.isEmpty && looksStructured(raw) { items = parse(raw) }
        if items.isEmpty {
            if await AI.available() {
                items = await distill(chat.isEmpty ? raw : chat.joined(separator: "\n"), progress: progress) ?? []
            }
            if items.isEmpty && chat.isEmpty { items = parse(raw) }
        }
        var r = QuickResult()
        r.found = items.count
        guard !items.isEmpty else {
            r.error = chat.isEmpty ? "没有识别出可导入的内容。" : "需要先在设置里配置云端大脑或下载本地模型，才能从对话记录里提炼。"
            return r
        }
        r.ids = Memory.addManyIDs(items, src: source)
        Evolve.logImport(source: source, added: r.ids.count, sample: items.map { $0.text })
        return r
    }
}

// 对话记录导出（ChatGPT 的 conversations.json、Claude 的 conversations.json）
enum ChatExport {
    // 取出用户自己说的话，新的在前，最多 300 条
    static func userTexts(_ data: Data) -> [String]? {
        guard let j = try? JSONSerialization.jsonObject(with: data), let arr = j as? [[String: Any]], !arr.isEmpty else { return nil }
        var items: [(String, String)] = []
        var matched = false
        for conv in arr {
            if let mapping = conv["mapping"] as? [String: Any] {
                matched = true
                for (_, v) in mapping {
                    guard let node = v as? [String: Any], let msg = node["message"] as? [String: Any],
                          let author = msg["author"] as? [String: Any], (author["role"] as? String) == "user",
                          let content = msg["content"] as? [String: Any], let parts = content["parts"] as? [Any] else { continue }
                    let t = parts.compactMap { $0 as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count >= 8 {
                        let time = (msg["create_time"] as? Double) ?? 0
                        items.append((String(format: "%015.3f", time), t))
                    }
                }
            } else if let msgs = conv["chat_messages"] as? [[String: Any]] {
                matched = true
                for m in msgs where (m["sender"] as? String) == "human" {
                    var t = (m["text"] as? String) ?? ""
                    if t.isEmpty, let c = m["content"] as? [[String: Any]] { t = c.compactMap { $0["text"] as? String }.joined(separator: "\n") }
                    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count >= 8 { items.append(((m["created_at"] as? String) ?? "", t)) }
                }
            }
        }
        guard matched else { return nil }
        return items.sorted { $0.0 > $1.0 }.prefix(300).map { String($0.1.prefix(300)) }
    }
}
