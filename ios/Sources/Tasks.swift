import Foundation
import UserNotifications
import FoundationModels

// 定时任务：计算与送达分离。打开 App 时提前生成内容，到点由系统通知准时送达。
enum Tasks {
    // rep：0 一次，1 每天，7 每周
    @discardableResult
    static func add(_ title: String, _ instr: String, _ due: Date, useModel: Bool, rep: Int) -> Int64 {
        DB.shared.run(
            "INSERT INTO task(title,instr,due,use_model,rep,result,state,notified) VALUES(?,?,?,?,?,?,0,0)",
            [title, instr, due.timeIntervalSince1970, useModel ? 1 : 0, rep, ""]
        )
    }

    static func list() -> [Row] { DB.shared.rows("SELECT * FROM task ORDER BY state, due") }

    static func remove(_ id: Int) {
        DB.shared.run("DELETE FROM task WHERE id=?", [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["task-\(id)"])
    }

    static func alarms() -> [Row] { DB.shared.rows("SELECT * FROM alarm ORDER BY due") }

    // 任务内容用当前应用语言生成（通知里显示的就是这段文字）。
    // 天气、新闻这类要实时数据的任务，先把真实数据取回来，再让模型整理成几句话；否则模型只能凭空编。
    static func gen(_ instr: String) async -> String {
        var data = ""
        var weatherText = ""
        if Weather.words.contains(where: { instr.contains($0) }) {
            let typed = Weather.city(from: instr)
            let city = typed.isEmpty ? (DB.shared.kv("weather.city") ?? "") : typed
            if !city.isEmpty, let w = await Weather.report(city: city) {
                weatherText = w
                data += "实时天气数据：\n" + w + "\n\n"
            }
        }
        if data.isEmpty, WebSearch.needs(instr) {
            let hits = await WebSearch.search(instr)
            if !hits.isEmpty { data += "联网搜索结果：\n" + WebSearch.format(hits) + "\n\n" }
        }
        let ins = "你是个人助理。直接输出任务结果，简洁，不超过120字，不要出现代码。"
            + (data.isEmpty ? "需要资料时先调用工具。" : "只依据下面给出的资料，不要编造。")
            + L10n.replyDirective + "当前时间：" + Sys.fmtFull(Date())
        let prompt = data + "任务：" + instr
        if let r = await LLM.complete(instructions: ins, prompt: prompt, maxTokens: 300, temperature: 0.4) { return r }
        if !weatherText.isEmpty { return weatherText }
        let s = LanguageModelSession(tools: [Recall(), FetchURL()], instructions: ins)
        return (try? await s.respond(to: prompt).content) ?? ""
    }

    // 返回本次处理的任务数
    @discardableResult
    static func refresh() async -> Int {
        await Sys.ensureNotif()
        let now = Date().timeIntervalSince1970
        var n = 0
        for r in DB.shared.rows("SELECT * FROM task WHERE state=0 ORDER BY due") {
            let id = r.i("id")
            let due = r.d("due")
            let useModel = r.i("use_model") == 1
            let rep = r.i("rep")
            var result = r.s("result")
            if useModel && result.isEmpty && due - now < 48 * 3600 {
                result = await gen(r.s("instr"))
                DB.shared.run("UPDATE task SET result=? WHERE id=?", [result, id])
            }
            let body = String((result.isEmpty ? r.s("instr") : result).prefix(160))
            if due > now {
                let pureRepeat = rep > 0 && !useModel
                Sys.notify(id: "task-\(id)", title: r.s("title"), body: body, at: Date(timeIntervalSince1970: due), rep: pureRepeat ? rep : 0)
                DB.shared.run("UPDATE task SET notified=1 WHERE id=?", [id])
                if due - now < 8 * 3600 { Live.timer(title: r.s("title"), subtitle: "定时任务", end: Date(timeIntervalSince1970: due)) }
                n += 1
            } else {
                if r.i("notified") == 0 {
                    Sys.notify(id: "task-\(id)", title: "补跑：" + r.s("title"), body: body, at: Date().addingTimeInterval(2))
                }
                if rep > 0 {
                    var next = due
                    while next <= now { next += Double(rep) * 86400 }
                    DB.shared.run("UPDATE task SET due=?, result='', notified=0 WHERE id=?", [next, id])
                } else {
                    DB.shared.run("UPDATE task SET state=1 WHERE id=?", [id])
                }
            }
        }
        return n
    }
}

// 进化：增量提炼长期事实入知识库，每次都留下记录。
// 不再自动改写系统提示：小模型改出来的提示词必须带上 remember、recall 两个工具名，
// 这些内部字眼会被拼进每次请求，反而让大脑更糊涂。旧版本记录保留，但不再生效。
enum Evolve {
    static let defaultPrompt = "你是用户的私人助理，回答简洁直接，使用简体中文。需要记住的信息调用 remember；需要回忆或查资料调用 recall。涉及文件转换的请求必须调用对应工具完成，不要编造结果。"

    static func prompt() -> String {
        let latest = DB.shared.rows("SELECT body FROM prompt ORDER BY ver DESC LIMIT 1").first?.s("body") ?? defaultPrompt
        // 旧版本自动改写出来的提示词带着内部工具名，一律不用
        if latest.contains("remember") || latest.contains("recall") { return defaultPrompt }
        return latest
    }

    static func versions() -> [Row] { DB.shared.rows("SELECT ver, body, ts FROM prompt ORDER BY ver DESC LIMIT 8") }

    @discardableResult
    static func saveVersion(_ body: String) -> Int {
        Int(DB.shared.run("INSERT INTO prompt(body,ts) VALUES(?,?)", [body, Date().timeIntervalSince1970]))
    }

    static func lastTime() -> Date? {
        guard let s = DB.shared.kv("evolve.time"), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func log() -> [Row] { DB.shared.rows("SELECT id, ts, summary, facts, ver FROM evo ORDER BY id DESC LIMIT 30") }

    // 一次性生成：云端大脑、本地大模型、系统模型依次尝试
    private static func ask(_ ins: String, _ prompt: String) async -> String? {
        await AI.oneShot(ins, prompt, maxTokens: 400)
    }

    // 记录一次「从其他 AI 导入记忆」，在进化记录里显示
    static func logImport(source: String, added: Int, sample: [String]) {
        let summary = L10n.f("从 {} 导入了 {} 条记忆", source, "\(added)")
        DB.shared.run("INSERT INTO evo(ts,summary,facts,ver) VALUES(?,?,?,?)",
                      [Date().timeIntervalSince1970, summary, sample.prefix(5).joined(separator: "\n"), 0])
    }

    // 返回本次进化的摘要
    @discardableResult
    static func run(force: Bool = false) async -> String {
        let last = Int(DB.shared.kv("evolve.last") ?? "0") ?? 0
        let rows = DB.shared.rows("SELECT id, role, text FROM msg WHERE id > ? ORDER BY id LIMIT 20", [last])
        guard rows.count >= (force ? 2 : 6), let maxId = rows.last?.i("id") else {
            return force ? "还没有足够的新对话可供进化。" : ""
        }
        let logs = String(rows.map { $0.s("role") + ": " + String($0.s("text").prefix(150)) }.joined(separator: "\n").suffix(1200))
        guard let facts = await ask("反思引擎，只输出结果，不闲聊", "提炼不超过5条关于用户的长期事实或偏好，每行一条；没有就只输出“无”：\n" + logs) else {
            return force ? "进化时模型没有返回结果，稍后再试。" : ""
        }
        var learned: [String] = []
        if facts.count > 3 && facts != "无" {
            let lines = facts.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•*· 0123456789.、)）")) }.filter { $0.count >= 4 && $0 != "无" }
            Memory.addMany(lines.map { MemItem(cat: "", text: $0) }, src: "对话")
            learned = lines
        }
        DB.shared.setKV("evolve.last", String(maxId))
        DB.shared.setKV("evolve.time", String(Date().timeIntervalSince1970))
        let summary = "分析了 \(rows.count) 条新对话；新增 \(learned.count) 条记忆；提示词保持不变"
        DB.shared.run("INSERT INTO evo(ts,summary,facts,ver) VALUES(?,?,?,?)", [Date().timeIntervalSince1970, summary, learned.joined(separator: "\n"), 0])
        return summary
    }
}
