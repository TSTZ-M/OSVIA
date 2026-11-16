import Foundation
import SwiftUI
import FoundationModels

struct Msg: Identifiable {
    let id = UUID()
    var role: String
    var text: String
    var files: [URL] = []
    var streaming = false
    var steps: [Step] = []
    var sources: [Source] = []
    var dur = 0.0
}

// 需要用户确认的操作（比如调用会改变外部状态的 MCP 工具）
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct Attach: Identifiable {
    let id = UUID()
    let url: URL
}

// 工具产出的文件，随助理回复一起显示
enum Out {
    private static let lock = NSLock()
    private static var list: [URL] = []
    static func add(_ u: [URL]) { lock.lock(); list += u; lock.unlock() }
    static func take() -> [URL] { lock.lock(); defer { lock.unlock() }; let r = list; list = []; return r }
}

@MainActor
final class Agent: ObservableObject {
    static let shared = Agent()
    @Published var msgs: [Msg] = []
    @Published var busy = false
    @Published var attachments: [Attach] = []
    @Published var convId = 0
    @Published var confirm: ConfirmRequest?
    var lastFile: URL?
    private var task: Task<Void, Never>?
    private var confirmCont: CheckedContinuation<Bool, Never>?
    private var pend: (UUID, String)?
    private var flushScheduled = false
    private var lastFlush = Date.distantPast

    private var saving: Bool { UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? true }

    init() { loadLatest() }

    // MARK: 对话记录
    func loadLatest() {
        if DB.shared.rows("SELECT id FROM msg WHERE conv=0 LIMIT 1").first != nil {
            let id = DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", ["历史对话", Date().timeIntervalSince1970])
            DB.shared.run("UPDATE msg SET conv=? WHERE conv=0", [id])
        }
        if let r = DB.shared.rows("SELECT id FROM conv ORDER BY ts DESC LIMIT 1").first { open(r.i("id")) } else { newChat() }
    }

    func newChat() {
        task?.cancel()
        answerConfirm(false)
        convId = 0
        msgs = []
        attachments = []
        busy = false
    }

    func open(_ id: Int) {
        task?.cancel()
        answerConfirm(false)
        busy = false
        convId = id
        attachments = []
        msgs = DB.shared.rows("SELECT role,text,files,meta FROM msg WHERE conv=? ORDER BY id", [id]).map { r in
            var urls: [URL] = []
            if let d = r.s("files").data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: d) {
                urls = list.map { Store.abs($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            var m = Msg(role: r.s("role"), text: r.s("text"), files: urls)
            if let d = r.s("meta").data(using: .utf8), let meta = try? JSONDecoder().decode(MsgMeta.self, from: d) {
                m.steps = meta.steps
                m.sources = meta.sources
                m.dur = meta.dur
            }
            return m
        }
    }

    func convs() -> [Row] { DB.shared.rows("SELECT id,title,ts FROM conv ORDER BY ts DESC") }

    func deleteConv(_ id: Int) {
        DB.shared.run("DELETE FROM msg WHERE conv=?", [id])
        DB.shared.run("DELETE FROM conv WHERE id=?", [id])
        if id == convId { newChat() }
    }

    func rename(_ id: Int, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DB.shared.run("UPDATE conv SET title=? WHERE id=?", [t, id])
    }

    func clearAll() {
        DB.shared.run("DELETE FROM msg")
        DB.shared.run("DELETE FROM conv")
        newChat()
    }

    // 只写数据库
    private func persist(_ role: String, _ text: String, _ files: [URL], meta: MsgMeta? = nil) {
        guard saving else { return }
        if convId == 0 {
            let title = role == "user" ? String(text.prefix(16)) : "新对话"
            convId = Int(DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", [title.isEmpty ? "文件" : title, Date().timeIntervalSince1970]))
        }
        let json = (try? JSONEncoder().encode(files.map { Store.rel($0) })).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var metaJSON = ""
        if let meta, !meta.isEmpty, let d = try? JSONEncoder().encode(meta) { metaJSON = String(decoding: d, as: UTF8.self) }
        DB.shared.run("INSERT INTO msg(role,text,ts,conv,files,meta) VALUES(?,?,?,?,?,?)", [role, text, Date().timeIntervalSince1970, convId, json, metaJSON])
        DB.shared.run("UPDATE conv SET ts=? WHERE id=?", [Date().timeIntervalSince1970, convId])
    }

    private func store(_ role: String, _ text: String, _ files: [URL]) {
        msgs.append(Msg(role: role, text: text, files: files))
        persist(role, text, files)
    }

    // MARK: 发送、停止、重新生成
    func start(_ text: String) {
        guard !busy else { return }
        task = Task { await self.send(text) }
    }

    func stop() {
        task?.cancel()
        answerConfirm(false)
    }

    // MARK: 确认操作（一次只问一个，后来的排队）
    func requestConfirm(title: String, detail: String) async -> Bool {
        while confirm != nil {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if Task.isCancelled { return false }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            confirmCont = c
            confirm = ConfirmRequest(title: title, detail: detail)
        }
    }

    func answerConfirm(_ ok: Bool) {
        guard let c = confirmCont else {
            confirm = nil
            return
        }
        confirmCont = nil
        confirm = nil
        c.resume(returning: ok)
    }

    // 给 Tracer 用：修改某条消息
    func mutate(_ mid: UUID, _ f: (inout Msg) -> Void) {
        if let i = msgs.firstIndex(where: { $0.id == mid }) { f(&msgs[i]) }
    }

    func regenerate() {
        guard !busy, let lastUser = msgs.last(where: { $0.role == "user" }) else { return }
        if msgs.last?.role == "assistant" {
            msgs.removeLast()
            DB.shared.run("DELETE FROM msg WHERE id=(SELECT MAX(id) FROM msg WHERE conv=? AND role='assistant')", [convId])
        }
        let t = lastUser.text
        let files = lastUser.files
        busy = true
        task = Task {
            Live.thinking(true)
            await self.respond(t, files: files)
            Live.thinking(false)
            self.busy = false
        }
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.map { $0.url }
        guard !t.isEmpty || !files.isEmpty, !busy else { return }
        busy = true
        Live.thinking(true)
        attachments = []
        store("user", t, files)
        if let f = files.last { lastFile = f }
        await respond(t, files: files)
        Live.thinking(false)
        busy = false
    }

    func quick(_ t: String) async -> String {
        await send(t)
        return msgs.last?.text ?? ""
    }

    // 生成一条助理回复：先放一个空消息，模型边生成边往里填（流式）。
    // 确定性回复（路由、转换、脚本、图片摘要）用中文写死，最后按当前语言翻译；模型回答直接用指定语言生成。
    private func respond(_ t: String, files: [URL]) async {
        let ph = Msg(role: "assistant", text: "", files: [], streaming: true)
        msgs.append(ph)
        let mid = ph.id
        let started = Date()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var reply = ""
        var fixed = true
        let allImages = !files.isEmpty && files.allSatisfy { Convert.imgExt.contains($0.pathExtension.lowercased()) }
        if !files.isEmpty { Live.set(.working, "正在处理文件") }
        if let f = files.last, let r = await Router.convert(t, file: f) {
            reply = r.0
        } else if files.isEmpty, let r = await Router.handle(t) {
            reply = r
        } else if files.isEmpty, let r = await Features.route(t) {
            reply = r
        } else if files.isEmpty, let r = await localIntent(t) {
            reply = r
        } else if files.isEmpty, let r = await scriptIntent(t, mid: mid) {
            reply = r
        } else if t.isEmpty, allImages {
            reply = await Self.imageSummary(files)
        } else if allImages, Self.wantsAnalysis(t) {
            fixed = false
            reply = await analyzeImages(t, files: files, mid: mid)
        } else {
            fixed = false
            var ctx = ""
            for f in files { ctx += await Self.describe(f) }
            reply = await ask(t.isEmpty ? "请处理我发送的文件" : t, ctx: ctx, hasFile: !files.isEmpty, mid: mid)
        }
        finish(mid, reply, translate: fixed, started: started)
    }

    // 立即更新（状态文字、清空）
    private func update(_ mid: UUID, _ text: String) {
        pend = nil
        if let i = msgs.firstIndex(where: { $0.id == mid }) { msgs[i].text = text }
    }

    // 流式文字：合并成每 60 毫秒最多刷新一次，长回答不卡顿
    private func stream(_ mid: UUID, _ text: String) {
        if text.isEmpty {
            update(mid, "")
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastFlush) >= 0.06 {
            lastFlush = now
            update(mid, text)
            return
        }
        pend = (mid, text)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            self.flushScheduled = false
            if let p = self.pend, let i = self.msgs.firstIndex(where: { $0.id == p.0 }), self.msgs[i].streaming {
                self.pend = nil
                self.lastFlush = Date()
                self.msgs[i].text = p.1
            }
        }
    }

    private func partial(_ mid: UUID) -> String { msgs.first(where: { $0.id == mid })?.text ?? "" }

    private func finish(_ mid: UUID, _ text: String, translate: Bool = false, started: Date = Date()) {
        let files = Out.take()
        pend = nil
        let body = text.isEmpty ? L10n.tr("已停止。") : (translate ? L10n.tr(text) : text)
        var meta = MsgMeta()
        if let i = msgs.firstIndex(where: { $0.id == mid }) {
            // 还在「进行中」的步骤（被停止或出错）一律收尾
            for k in msgs[i].steps.indices where msgs[i].steps[k].state == 0 { msgs[i].steps[k].state = 2 }
            msgs[i].text = body
            msgs[i].files = files
            msgs[i].streaming = false
            msgs[i].dur = Date().timeIntervalSince(started)
            meta = MsgMeta(steps: msgs[i].steps, sources: msgs[i].sources, dur: msgs[i].dur)
        }
        persist("assistant", body, files, meta: meta)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // 最近几轮对话，作为真正的多轮上下文交给模型。剔除出错、停止这类没有信息量的回复，避免模型被它们带偏
    private func history() -> [Brain.Turn] {
        msgs.dropLast(2).suffix(12).compactMap { m in
            let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if m.role != "user" {
                let bad = ["出错", "没能完成", "没有返回内容", "已停止", "暂时不可用"]
                if bad.contains(where: { t.contains($0) }) { return nil }
            }
            return Brain.Turn(role: m.role == "user" ? "user" : "assistant", text: String(t.prefix(900)))
        }
    }

    // 「做一个……脚本」：确定性处理，不交给小模型瞎猜
    private func scriptIntent(_ t: String, mid: UUID) async -> String? {
        guard t.contains("脚本") || t.contains("技能") else { return nil }
        let make = ["做一个", "做个", "写一个", "写个", "创建一个", "创建个", "生成一个", "生成个", "帮我做", "帮我写", "编一个", "弄一个"]
        guard make.contains(where: { t.contains($0) }) else { return nil }
        if t.contains("挖矿") {
            return "做不到：iOS 不允许 App 在后台长时间满负载运行，手机也算不动挖矿，脚本技能更不行。\n脚本技能只能处理文字、读网页、查知识库，比如整理文案、提取网页要点、批量改写。想做其中一种，直接告诉我。"
        }
        let banned = ["点赞", "自动点击", "模拟点击", "连点", "刷赞", "刷粉", "刷量", "自动关注", "自动评论", "自动刷", "抢单", "外挂", "抢购", "秒杀", "抢票", "自动下单", "自动交易", "刷单"]
        if banned.contains(where: { t.contains($0) }) {
            return "做不到：iOS 不允许一个 App 自动点击或操作别的 App（点赞、关注、下单、抢购都不行），快捷指令也一样。\n脚本技能只能处理文字、读网页、查知识库，比如整理文案、提取网页要点、批量改写。想做其中一种，直接告诉我。"
        }
        let tr = Tracer(mid)
        let sid = tr.begin(.skill, "生成脚本技能", t)
        Live.set(.working, "正在编写脚本")
        let r = await Skills.create(t) { p in
            Task { @MainActor in tr.detail(sid, p) }
        }
        tr.end(sid, ok: r.ok, detail: r.ok ? r.name : String(r.out.prefix(60)))
        if r.ok {
            return "已创建脚本技能「\(r.name)」，试运行结果：\n\(r.out)\n\n以后说「运行 \(r.name)」，或到 工具箱 → 脚本技能 里使用。"
        }
        return "没能生成可运行的脚本（\(r.out)）。请把需求说具体一点：输入是什么、希望输出什么。"
    }

    // 本地大模型可用时，用它从任何语言的句子里提取闹钟、提醒、日程（中文规则没认出来的也会在这里兜底）。云端大脑启用时由它自己调用工具，这里跳过
    private func localIntent(_ t: String) async -> String? {
        guard LocalLLM.shared.canUse, !CloudLLM.ready, t.count <= 200 else { return nil }
        let low = t.lowercased()
        let ks = ["alarm", "remind", "wake", "schedule", "meeting", "appointment", "timer", "闹钟", "提醒", "叫我", "日程", "起床", "アラーム", "リマインド", "알람", "알림", "despert", "recordar", "rappel", "réveil", "wecker", "erinner", "sveglia", "ricord", "будильник", "напомни", "uyandır", "hatırlat", "đánh thức", "nhắc", "ปลุก", "เตือน", "bangunkan", "ingatkan", "منبه", "ذكرني", "अलार्म", "याद"]
        guard ks.contains(where: { low.contains($0) }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm (EEEE)"
        let ins = "You extract scheduling intents from a message. Current local time: \(f.string(from: Date())). Output ONE JSON object only, no other text: {\"type\":\"alarm|reminder|event|none\",\"title\":\"short title in the user's language\",\"time\":\"yyyy-MM-dd'T'HH:mm\",\"repeat\":\"none|daily|weekly\"}. Resolve relative times such as tomorrow or in 2 hours from the current time. Use type none if the message does not ask to set an alarm, reminder or calendar event."
        guard let text = await LLM.complete(instructions: ins, prompt: t, maxTokens: 120, temperature: 0.1),
              let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let data = String(text[a...b]).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = j["type"] as? String, type != "none",
              let ts = j["time"] as? String else { return nil }
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let d = p.date(from: String(ts.prefix(16))) else { return nil }
        let title = (j["title"] as? String) ?? ""
        let r = j["repeat"] as? String
        let rep = r == "daily" ? 1 : (r == "weekly" ? 7 : 0)
        Live.set(.working)
        switch type {
        case "alarm": return await Sys.alarm(d, title, rep: rep)
        case "reminder": return await Sys.reminder(title.isEmpty ? t : title, d, rep: rep)
        case "event": return await Sys.event(title.isEmpty ? t : title, d)
        default: return nil
        }
    }

    // MARK: 图片与文件理解
    // 用户是否在让助理「看、分析、说明」图片（而不是转换格式）
    nonisolated static func wantsAnalysis(_ t: String) -> Bool {
        let low = t.lowercased()
        let ks = ["分析", "看看", "看一下", "看下", "描述", "这是什么", "是什么", "什么意思", "说明", "解释", "总结", "讲讲", "说说", "内容", "analy", "describe", "explain", "what", "summar", "look", "tell me"]
        return ks.contains { low.contains($0) }
    }

    // 图片分析：本机先识别文字与类别，再让模型只依据识别结果回答（不给工具，避免乱调用）
    private func analyzeImages(_ t: String, files: [URL], mid: UUID) async -> String {
        var ctx = ""
        for (i, f) in files.prefix(3).enumerated() {
            let text = await Task.detached { OCR.text(f) }.value
            let labels = await Task.detached { OCR.labels(f) }.value
            let clean = String(text.replacingOccurrences(of: "\n", with: " ").prefix(700))
            ctx += "【图片\(i + 1)】类别：" + (labels.isEmpty ? "未知" : labels.joined(separator: "、")) + "；文字：" + (clean.isEmpty ? "无" : clean) + "\n"
        }
        return await ask(t, ctx: ctx, hasFile: true, mid: mid, imageMode: true)
    }

    nonisolated static func imagePrompt(_ q: String, _ ctx: String) -> String {
        "以下是本机对用户发来的图片做识别得到的结果（文字可能有错别字，不要编造识别结果以外的内容）：\n" + ctx
            + "\n用户的问题：" + (q.isEmpty ? "说明这张图片的内容" : q)
            + "\n请只依据上面的识别结果回答这个问题，两三句话说清楚；如果文字很少或没有，就说明只能看出类别，并建议用户补充说明。"
    }

    nonisolated static func imageSummary(_ files: [URL]) async -> String {
        var parts = ["收到 \(files.count) 张图片。我能识别图中的文字和大致类别，看不到画面细节。"]
        for f in files.prefix(3) {
            let labels = OCR.labels(f)
            let text = OCR.text(f)
            if !labels.isEmpty { parts.append("类别：" + labels.joined(separator: "、")) }
            parts.append(text.isEmpty ? "图中没有识别到文字。" : "图中文字：" + String(text.prefix(300)))
        }
        parts.append("可以点输入框上方的「识别文字」「转成PDF」「转成PNG」，或直接告诉我要对这张图做什么。")
        return parts.joined(separator: "\n")
    }

    nonisolated static func describe(_ u: URL) async -> String {
        let ext = u.pathExtension.lowercased()
        if Convert.imgExt.contains(ext) {
            let t = OCR.text(u)
            let l = OCR.labels(u)
            return "\n[图片] 类别：" + (l.isEmpty ? "未知" : l.joined(separator: "、")) + "；图中文字：" + (t.isEmpty ? "无" : String(t.prefix(1200)))
        }
        if Convert.vidExt.contains(ext) { return "\n[视频] 已收到" }
        let txt = KB.shared.text(of: u)
        if txt.isEmpty { return "\n[文件] 已收到，无法读取文字" }
        if txt.count <= 1200 { return "\n[文件内容] \(txt)" }
        KB.shared.upsert(u.lastPathComponent, txt)
        return "\n[文件] 内容较长（\(txt.count) 字），已存入知识库，可以直接就这份文件向我提问"
    }

    // MARK: 模型
    // time：只在问题和时间有关时才告诉模型当前日期，否则它会把日期当成要回答的内容
    nonisolated static func instructions(time: Bool, query: String = "") -> String {
        let mem = query.isEmpty ? "" : Memory.block(for: query, budget: 600, recent: false).text
        let prof = Evolve.profile()
        let concise = (UserDefaults.standard.object(forKey: "style") as? Int ?? 0) == 0
        var base = Evolve.prompt()
        if !L10n.isChinese {
            base = base.replacingOccurrences(of: "使用简体中文，", with: "").replacingOccurrences(of: "使用简体中文", with: "")
        }
        return L10n.replyDirective + "\n" + base
            + (time ? "\n现在是" + Sys.fmtFull(Date()) + "，时区" + TimeZone.current.identifier + "。" : "\n")
            + "你是 " + Brand.name + "，运行在用户 iPhone 上的助理。只回答用户当前这一个问题，不要复述问题，不要扔到别的话题，信息够用时不要反问。"
            + "你看不到图片，只能依据识别出的类别和文字回答，不要说无法读取图片。"
            + (concise ? "回答要简短。" : "回答可以详细一些。")
            + "需要列表或代码时用 Markdown。不知道就直说不知道，不要编造。不要向用户提及任何内部工具的名字。"
            + (mem.isEmpty ? "" : "\n" + mem)
            + (prof.isEmpty ? "" : "\n用户画像与回答指引：" + String(prof.prefix(320)))
    }

    // 本地大模型的系统提示：不再提到 remember / recall 之类的工具；工具说明由 LocalBrain 按需追加
    nonisolated static func localInstructions(time: Bool, query: String = "") -> String {
        let concise = (UserDefaults.standard.object(forKey: "style") as? Int ?? 0) == 0
        var s = "你是 " + Brand.name + "，运行在用户 iPhone 上的个人助理。" + L10n.replyDirective
        s += "回答原则：先直接给结论，再补充必要的说明；只回答用户当前这一个问题，不要复述问题，不要自我介绍，不要扯到别的话题。"
        s += "遇到计算、换算、日期推算，先一步步算对再给结果。事实没把握就明说不确定，不要编造人名、数据、链接、版本号。"
        s += "用户要方案或代码时，直接给能用的完整内容，不要只讲思路。"
        s += "你做不到的事要直说：不能操作别的 App，不能代替用户点击屏幕，不能在后台常驻运行。"
        s += concise ? "回答控制在 200 字以内（代码和必要的列表除外）。" : "回答可以详细一些，条理清楚。"
        s += "需要列表或代码时用 Markdown。"
        if time { s += "\n现在是" + Sys.fmtFull(Date()) + "，时区" + TimeZone.current.identifier + "。" }
        let p = Evolve.prompt()
        if p != Evolve.defaultPrompt { s += "\n用户偏好补充：" + String(p.prefix(300)) }
        if !query.isEmpty {
            let mem = Memory.block(for: query, budget: 600, recent: false).text
            if !mem.isEmpty { s += "\n" + mem }
        }
        let prof = Evolve.profile()
        if !prof.isEmpty { s += "\n用户画像与回答指引：" + String(prof.prefix(320)) }
        return s
    }

    nonisolated static func needsTime(_ t: String, _ tools: [any Tool]) -> Bool {
        if tools.contains(where: { $0 is SetAlarm || $0 is AddReminder || $0 is AddEvent }) { return true }
        let low = t.lowercased()
        let ks = ["今天", "明天", "后天", "现在", "几点", "日期", "星期", "周几", "时间", "分钟", "小时", "天后", "today", "tomorrow", "tonight", "date", "time", "week", "hour", "minute"]
        return ks.contains { low.contains($0) }
    }

    // 只在消息确实相关时才给模型工具：工具越多，小模型越容易答非所问。「有附件」不再自动给转换工具，必须说到转换才给
    nonisolated static func tools(for t: String, hasFile: Bool) -> [any Tool] {
        let low = t.lowercased()
        func has(_ k: [String]) -> Bool { k.contains { low.contains($0) } }
        var r: [any Tool] = []
        if has(["记住", "记一下", "别忘了", "remember"]) { r.append(Remember()) }
        if has(["之前", "上次", "知识库", "笔记", "资料", "我的文档", "我存的", "earlier", "notes", "knowledge"]) { r.append(Recall()) }
        if has(["闹钟", "提醒", "日历", "日程", "会议", "定时", "叫我", "起床", "alarm", "remind", "calendar", "schedule", "wake me", "meeting"]) { r += [SetAlarm(), AddReminder(), AddEvent()] }
        if has(["转换", "转成", "转为", "压缩", "导出", "提取", "convert", "compress", "export", "extract", "pdf", "png", "jpg", "mp4"]) { r.append(ConvertFile()) }
        if DB.shared.rows("SELECT name FROM skill").contains(where: { t.contains($0.s("name")) }) { r.append(RunSkill()) }
        if has(["查找文件", "读取文件", "找文件", "文档里", "find file", "read file"]) { r += [FindFile(), ReadFile()] }
        if has(["http", "网页", "网址", "链接", "新闻", "web", "news", "link", "url"]) { r.append(FetchURL()) }
        if Connectors.all().contains(where: { t.contains($0.s("name")) }) { r.append(CallConnector()) }
        return r
    }

    nonisolated static func unavailableText(_ reason: String) -> String {
        if reason.contains("appleIntelligenceNotEnabled") { return "本机模型还没开启：请到 设置 → Apple 智能与 Siri，打开 Apple 智能。" }
        if reason.contains("modelNotReady") { return "本机模型还在下载或准备中，请连上 Wi‑Fi 等几分钟再试。" }
        if reason.contains("deviceNotEligible") { return "这台设备不支持 Apple 智能，没法使用本机模型。" }
        return "本机模型暂时不可用（\(reason)）。"
    }

    // 把底层错误翻译成人话；返回 nil 表示可以重试
    nonisolated static func explain(_ err: String) -> String? {
        let low = err.lowercased()
        if low.contains("guardrail") || low.contains("refus") { return "这个话题触发了系统模型的安全限制，我没法回答。换个说法或说明正当用途再试。" }
        if low.contains("unsupportedlanguage") { return "系统模型暂不支持这种语言或地区设置，请换个说法。" }
        if low.contains("assetsunavailable") { return "本机模型资源还没准备好，请稍等几分钟再试。" }
        return nil
    }

    // MARK: 本机模型回答
    // 联网搜索、知识库检索、网页读取、「记住」先由代码按关键词完成，结果写进提示；没命中关键词时，本地大模型可以自己决定要不要搜索（LocalBrain）
    private func webContext(_ t: String, tr: Tracer) async -> String {
        guard WebSearch.needs(t), Self.firstURL(in: t) == nil else { return "" }
        Live.set(.searching)
        let sid = tr.begin(.search, "联网搜索", t)
        let hits = await WebSearch.search(t)
        if hits.isEmpty {
            tr.end(sid, ok: false, detail: t + " · " + L10n.tr("没有结果"))
            return ""
        }
        let ns = tr.register(hits)
        tr.end(sid, detail: t + " · " + L10n.f("{} 条结果", "\(hits.count)"))
        return "联网搜索结果（回答时说明信息来自网络，仅依据下面内容，不要编造；用 [编号] 标注来源）：\n" + WebSearch.format(hits, numbers: ns)
    }

    private func localContext(_ t: String, tr: Tracer) async -> String {
        var out: [String] = []
        let low = t.lowercased()
        if ["之前", "上次", "知识库", "笔记", "资料", "我的文档", "我存的", "记得", "earlier", "notes", "knowledge"].contains(where: { low.contains($0) }) {
            let hits = KB.shared.search(t, k: 4)
            if !hits.isEmpty {
                tr.note(.memory, "查询知识库", L10n.f("{} 条", "\(hits.count)"))
                out.append("知识库里的相关资料：\n" + hits.map { "- " + String($0.prefix(300)) }.joined(separator: "\n"))
            }
        }
        if let u = Self.firstURL(in: t) {
            let host = (u.host ?? u.absoluteString).replacingOccurrences(of: "www.", with: "")
            let sid = tr.begin(.read, "读取网页", host)
            let page = await Web.read(u, limit: 3500)
            if page.text.isEmpty {
                tr.end(sid, ok: false, detail: host + " · " + L10n.tr("没读到内容"))
            } else {
                let n = tr.register(url: u.absoluteString, title: page.title)
                tr.end(sid, detail: page.title.isEmpty ? host : page.title)
                out.append("网页内容（[\(n)] \(u.absoluteString)）：\n" + page.text)
            }
        }
        let web = await webContext(t, tr: tr)
        if !web.isEmpty { out.append(web) }
        if ["记住", "记一下", "别忘了", "remember"].contains(where: { low.contains($0) }) {
            let fact = t.replacingOccurrences(of: "^(请|帮我|麻烦)*(记住|记一下|别忘了)[，, ：:]*", with: "", options: .regularExpression)
            if Memory.add(fact.isEmpty ? t : fact, src: "对话") { tr.note(.memory, "写入记忆", String(fact.prefix(60))) }
        }
        return out.joined(separator: "\n\n")
    }

    nonisolated static func firstURL(in t: String) -> URL? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let m = det.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length))
        guard let u = m?.url, u.scheme == "http" || u.scheme == "https" else { return nil }
        return u
    }

    nonisolated static func fetchPage(_ u: URL) async -> String {
        await Web.read(u, limit: 3500).text
    }

    // 本地大模型：真多轮历史（最近 6 条）+ 按需工具循环。已经给了联网结果或在看图时不开放工具
    private func askLocal(_ t: String, ctx: String, mid: UUID, imageMode: Bool) async -> String {
        Live.set(.thinking)
        let tr = Tracer(mid)
        var loading: UUID?
        if !LocalLLM.shared.isLoaded { loading = tr.begin(.think, "载入本地模型") }
        let extra = imageMode ? "" : await localContext(t, tr: tr)
        let turns: [Brain.Turn] = imageMode ? [] : Array(history().suffix(6))
        let ins = Self.localInstructions(time: Self.needsTime(t, []), query: t)
        if !imageMode {
            let m = Memory.block(for: t, budget: 600, recent: false)
            if m.lines > 0 { tr.note(.memory, L10n.f("载入 {} 条记忆，{} 条与问题相关", "\(m.lines)", "\(m.relevant)"), "") }
        }
        let user: String
        if imageMode {
            user = Self.imagePrompt(t, ctx)
        } else {
            user = (extra.isEmpty ? "" : extra + "\n\n") + "用户当前的问题（只回答这个问题）：\(t)\(ctx)"
        }
        let useTools = !imageMode && !extra.contains("联网搜索结果")
        let out = await LocalBrain.ask(
            instructions: ins, history: turns, user: user, query: t, tools: useTools, trace: tr,
            onText: { s in
                if let id = loading {
                    tr.end(id)
                    loading = nil
                }
                self.stream(mid, s)
            })
        if let id = loading { tr.end(id) }
        if Task.isCancelled { return partial(mid) }
        return out.isEmpty ? L10n.tr("模型没有返回内容") : out
    }

    // 回答入口：先用云端大脑（用户填了免费密钥才会启用），失败或没启用就用本机模型
    private func ask(_ t: String, ctx: String, hasFile: Bool, mid: UUID, imageMode: Bool = false) async -> String {
        var note = ""
        if CloudLLM.ready {
            Live.set(.thinking)
            let r = await Brain.ask(
                history: imageMode ? [] : history(),
                user: imageMode ? Self.imagePrompt(t, ctx) : t,
                ctx: imageMode ? "" : ctx,
                trace: Tracer(mid),
                onText: { s in self.stream(mid, s) })
            if let r { return r.isEmpty ? partial(mid) : r }
            note = L10n.tr("云端大脑暂时不可用") + "：" + CloudLLM.lastError
            update(mid, "")
        }
        let out = await askOffline(t, ctx: ctx, hasFile: hasFile, mid: mid, imageMode: imageMode)
        if note.isEmpty || Task.isCancelled { return out }
        return out + "\n\n（" + note + "；" + L10n.tr("这次用了本机模型") + "）"
    }

    private func askOffline(_ t: String, ctx: String, hasFile: Bool, mid: UUID, imageMode: Bool) async -> String {
        // 本地大模型已下载并开启时优先用它
        if LocalLLM.shared.canUse { return await askLocal(t, ctx: ctx, mid: mid, imageMode: imageMode) }
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            return L10n.tr(Self.unavailableText("\(reason)"))
        @unknown default:
            break
        }
        let tools: [any Tool] = imageMode ? [] : Self.tools(for: t, hasFile: hasFile)
        // 灵动岛：需要联网读网页时显示「搜索」，否则显示「思考」
        Live.set(tools.contains { $0 is FetchURL } ? .searching : .thinking)
        let hist = imageMode ? "" : history().suffix(4)
            .map { ($0.role == "user" ? "用户：" : "助理：") + String($0.text.prefix(200)) }
            .joined(separator: "\n")
        let tr = Tracer(mid)
        let web = imageMode ? "" : await webContext(t, tr: tr)
        let names = Connectors.all().map { $0.s("name") }.joined(separator: "、")
        let extra = names.isEmpty ? "" : "\n可调用的连接器：" + names
        let ins = Self.instructions(time: Self.needsTime(t, tools), query: imageMode ? "" : t) + extra
        var lastErr = ""
        for attempt in 0..<3 {
            let session = LanguageModelSession(tools: attempt == 2 ? [] : tools, instructions: ins)
            let prompt: String
            if imageMode {
                prompt = attempt < 2 ? Self.imagePrompt(t, ctx) : t
            } else {
                switch attempt {
                case 0: prompt = (hist.isEmpty ? "" : "此前的对话（仅供参考）：\n\(hist)\n\n") + (web.isEmpty ? "" : web + "\n\n") + "用户当前的问题（只回答这个问题）：\(t)\(ctx)"
                case 1: prompt = "用户当前的问题：\(t)" + String(ctx.prefix(300))
                default: prompt = t
                }
            }
            do {
                var last = ""
                for try await snap in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.3)) {
                    last = snap.content
                    stream(mid, last)
                }
                if !last.isEmpty { return last }
                lastErr = "模型没有返回内容"
            } catch {
                if Task.isCancelled || error is CancellationError { return partial(mid) }
                lastErr = "\(error)"
                if let m = Self.explain(lastErr) { return L10n.tr(m) }
            }
            if Task.isCancelled { return partial(mid) }
            update(mid, "")
        }
        return L10n.tr("这次没能完成（\(String(lastErr.prefix(90)))）。可以点「重新生成」，或换个说法。")
    }

    func transcript(_ ms: [Msg]) -> String {
        ms.map { ($0.role == "user" ? L10n.tr("我") : Brand.name) + L10n.colon + $0.text }.joined(separator: "\n\n")
    }
}
