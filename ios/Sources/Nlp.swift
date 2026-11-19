import Foundation

// 中文自然语言时间解析：明早十点、一周后下午三点、每天早上8点、30分钟后、10月30日下午3点、5号……
enum Nlp {
    struct Res {
        var date: Date?
        var rep = 0          // 0 一次，1 每天，7 每周
        var clock = false    // 话里有没有明确的几点几分（或「N 分钟后」）；只说「明天」不算
        var rest = ""        // 去掉时间与口令词后的事项内容
    }

    static let cnDigit: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]

    static func num(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let cs = Array(s)
        if cs.isEmpty { return nil }
        if let ten = cs.firstIndex(of: "十") {
            let a = ten == 0 ? 1 : (cnDigit[cs[0]] ?? 0)
            let b = ten + 1 < cs.count ? (cnDigit[cs[ten + 1]] ?? 0) : 0
            return a * 10 + b
        }
        var v = 0
        for c in cs {
            guard let d = cnDigit[c] else { return nil }
            v = v * 10 + d
        }
        return v
    }

    // Calendar 的星期：周日 = 1
    private static func wd(_ c: String) -> Int {
        switch c {
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        default: return 1
        }
    }

    // 取出匹配的一段并从文本中删除，返回各捕获组
    private static func take(_ s: inout String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        var g: [String] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: s) { g.append(String(s[r])) } else { g.append("") }
        }
        if let r = Range(m.range, in: s) { s.removeSubrange(r) }
        return g
    }

    static func parse(_ input: String, now: Date = Date()) -> Res {
        var s = input
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        var res = Res()
        var dayOff: Int?
        var absBase: Date?
        var weekday: Int?
        var nextWeek = false
        var rel: TimeInterval?
        var period = ""
        var explicitHour = false
        let np = "(\\d+|[零〇一二两三四五六七八九十]+)"

        if let g = take(&s, "(半|\(np))\\s*个?\\s*(小时|钟头|分钟|分)\\s*(?:后|以后|之后)") {
            let n = g[1] == "半" ? 0.5 : Double(num(g[1]) ?? 0)
            rel = g[3] == "分钟" || g[3] == "分" ? n * 60 : n * 3600
        } else if let g = take(&s, "\(np)\\s*(?:天|日)\\s*(?:后|以后|之后)") {
            dayOff = num(g[1])
        } else if let g = take(&s, "\(np)\\s*(?:个)?(?:周|星期|礼拜)\\s*(?:后|以后|之后)") {
            dayOff = (num(g[1]) ?? 1) * 7
        }

        if rel == nil {
            if let g = take(&s, "每(?:周|星期|礼拜)([一二三四五六日天])?") {
                res.rep = 7
                if !g[1].isEmpty { weekday = wd(g[1]) }
            } else if take(&s, "每(?:天|日)") != nil {
                res.rep = 1
            }
        }

        if rel == nil && dayOff == nil {
            if let g = take(&s, "\(np)\\s*月\\s*\(np)\\s*[日号]") {
                // 10月30日、十月三十号：已经过去的日期算明年
                if let mo = num(g[1]), let dd = num(g[2]), (1...12).contains(mo), (1...31).contains(dd) {
                    var c = cal.dateComponents([.year], from: now)
                    c.month = mo
                    c.day = dd
                    if var d = cal.date(from: c) {
                        if d < startToday { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
                        absBase = d
                    }
                }
            } else if take(&s, "大后天") != nil { dayOff = 3 }
            else if take(&s, "后天") != nil { dayOff = 2 }
            else if let g = take(&s, "明(?:天|日|早|晨|晚)") {
                dayOff = 1
                if g[0].hasSuffix("早") || g[0].hasSuffix("晨") { period = "早上" }
                if g[0].hasSuffix("晚") { period = "晚上" }
            } else if let g = take(&s, "今(?:天|日|早|晨|晚)") {
                dayOff = 0
                if g[0].hasSuffix("早") || g[0].hasSuffix("晨") { period = "早上" }
                if g[0].hasSuffix("晚") { period = "晚上" }
            } else if let g = take(&s, "下(?:周|星期|礼拜)([一二三四五六日天])") {
                weekday = wd(g[1]); nextWeek = true
            } else if let g = take(&s, "(?:周|星期|礼拜)([一二三四五六日天])") {
                weekday = wd(g[1])
            } else if let g = take(&s, "(\\d{1,2})\\s*[号日](?![线楼门口车院库店座层])") {
                // 5号：这个月的 5 号，已经过去就算下个月
                if let dd = Int(g[1]), (1...31).contains(dd) {
                    var c = cal.dateComponents([.year, .month], from: now)
                    c.day = dd
                    var d = cal.date(from: c)
                    if d == nil || d! < startToday {
                        c.month = (c.month ?? 1) + 1
                        d = cal.date(from: c)
                    }
                    absBase = d
                }
            }
        }

        var hour: Int?
        var minute = 0
        if rel == nil {
            let periods = "凌晨|清晨|早晨|早上|上午|中午|下午|傍晚|晚上|夜里|半夜"
            if let g = take(&s, "(\(periods))?\\s*(\\d{1,2})\\s*[:：]\\s*(\\d{2})") {
                if !g[1].isEmpty { period = g[1] }
                hour = Int(g[2])
                minute = Int(g[3]) ?? 0
                explicitHour = true
            } else if let g = take(&s, "(\(periods))?\\s*(\\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\\s*(?:点钟|点|时)\\s*(半|一刻|三刻|(\\d{1,2}|[零〇一二三四五六七八九十]{1,3})\\s*分?)?") {
                if !g[1].isEmpty { period = g[1] }
                hour = num(g[2])
                explicitHour = hour != nil
                switch g[3] {
                case "半": minute = 30
                case "一刻": minute = 15
                case "三刻": minute = 45
                case "": minute = 0
                default: minute = num(g[4]) ?? 0
                }
            } else if let g = take(&s, "(\(periods))") {
                period = g[1]
            }
            if var h = hour {
                switch period {
                case "下午", "傍晚", "晚上", "夜里": if h < 12 { h += 12 }
                case "中午": if h < 11 { h += 12 }
                case "凌晨", "半夜": if h == 12 { h = 0 }
                default: break
                }
                hour = h % 24
            } else if !period.isEmpty {
                switch period {
                case "凌晨": hour = 5
                case "清晨", "早晨", "早上": hour = 8
                case "上午": hour = 9
                case "中午": hour = 12
                case "下午": hour = 15
                case "傍晚": hour = 18
                case "晚上": hour = 20
                default: hour = 23
                }
            }
        }
        res.clock = rel != nil || explicitHour

        if let r = rel {
            res.date = now.addingTimeInterval(r)
        } else if dayOff != nil || absBase != nil || weekday != nil || hour != nil || res.rep > 0 {
            let h = hour ?? 9
            var base = startToday
            if let a = absBase {
                base = a
            } else if let d = dayOff {
                base = cal.date(byAdding: .day, value: d, to: startToday) ?? startToday
            } else if let w = weekday {
                let today = cal.component(.weekday, from: now)
                let diff = nextWeek ? (7 - (today + 5) % 7) + (w + 5) % 7 : (w - today + 7) % 7
                base = cal.date(byAdding: .day, value: diff, to: startToday) ?? startToday
            }
            var d = cal.date(bySettingHour: h, minute: minute, second: 0, of: base) ?? base
            if dayOff == nil && absBase == nil && !(weekday != nil && nextWeek) && d <= now {
                d = cal.date(byAdding: .day, value: weekday != nil ? 7 : 1, to: d) ?? d
            }
            res.date = d
        }

        for w in ["提醒我", "提醒", "叫我", "通知我", "帮我", "请你", "请", "设置一个", "设置", "设定", "设个", "定个", "创建", "添加", "新建", "定时任务", "定时", "闹钟", "日程", "记得", "别忘了", "别忘", "一下", "，", ",", "。", "、"] {
            s = s.replacingOccurrences(of: w, with: "")
        }
        res.rest = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return res
    }
}

// 确定性指令路由：闹钟、提醒、日程、定时任务、文件转换，不依赖小模型猜参数
enum Router {
    static func handle(_ t: String) async -> String? {
        func has(_ ks: [String]) -> Bool { ks.contains { t.contains($0) } }
        let p = Nlp.parse(t)
        let alarmW = has(["闹钟", "起床", "叫醒", "闹铃"])
        let eventW = has(["日程", "日历", "开会", "会议", "约会"])
        let remindW = has(["提醒", "记得", "别忘", "通知我", "叫我"])
        let timerW = has(["定时", "每天", "每日", "每周"])
        // 下指令的口气（提醒我、帮我设、添加……）与提问的口气（吗、怎么、什么……）
        let cmd = has(["提醒", "叫我", "叫醒", "通知我", "设置", "设定", "设闹钟", "定闹钟", "设个", "定个", "设一个", "创建", "添加", "新建", "安排", "加个", "加一个", "帮我", "记得", "别忘", "预约", "记一下", "订个"])
        let q = has(["吗", "怎么", "如何", "为什么", "什么", "哪", "是不是", "能不能", "可以", "？", "?", "没响", "不响", "没有响", "失效"])

        guard let d = p.date else {
            // 想设闹钟却没说几点：直接问，不要交给模型瞎编一句「已设置」
            if alarmW && cmd && !q { return "想几点？比如「明早7点叫我起床」「每天8点闹钟」。" }
            return nil
        }
        // 「明天天气怎么样」「明天开会要带什么」是在提问，不是在下指令
        if q && !cmd { return nil }
        // 既没有具体几点、也没有指令词（只是句子里带了个「明天」）：不当成日程任务
        if !(p.clock || p.rep > 0 || cmd) { return nil }

        // 「提醒我查一下报告」是提醒；「每天8点告诉我天气」才是让助理去查并播报的任务
        let aiStrong = has(["总结", "播报", "汇总", "汇报", "简报", "告诉我", "生成", "分析", "天气", "新闻", "查询", "查一下"])
        let doW = alarmW || eventW || has(["提醒", "叫我", "通知我", "记得", "别忘"])
        let aiW = aiStrong && !(doW && !has(["播报", "汇报", "简报", "告诉我", "总结", "汇总"]))

        let content = p.rest

        if alarmW && !aiW {
            let label = content.isEmpty ? "闹钟" : String(content.prefix(20))
            return await Sys.alarmSmart(d, label, rep: p.rep)
        }
        if aiW || (timerW && !remindW && !eventW) {
            guard p.rep > 0 || d > Date() else { return "这个时间已经过了，换一个时间试试。" }
            let instr = content.isEmpty ? t : content
            let title = String(instr.prefix(14))
            Tasks.add(title, instr, d, useModel: aiW, rep: p.rep)
            await Tasks.refresh()
            return "定时任务已创建：\(p.rep > 0 ? Sys.repText(p.rep) + " " : "")\(Sys.friendly(d))「\(title)」。\(aiW ? "到点前我会先准备好内容，再用通知送达。" : "")"
        }
        if eventW {
            let title = content.isEmpty ? "日程" : String(content.prefix(30))
            return await Sys.event(title, d)
        }
        if remindW {
            let title = content.isEmpty ? "提醒" : String(content.prefix(40))
            return await Sys.reminder(title, d, rep: p.rep)
        }
        return nil
    }

    // 带文件时的转换指令：转成PDF、识别文字、压缩……
    static func convert(_ t: String, file: URL) async -> (String, [URL])? {
        let low = t.lowercased()
        var target: String?
        if ["去水印", "去除水印", "去掉水印", "消除水印", "移除水印", "remove watermark"].contains(where: { low.contains($0) }) {
            let vid = Convert.vidExt.contains(file.pathExtension.lowercased())
            AppState.shared.tool = ToolRequest(kind: vid ? .wmVideo : .wmImage, files: [file])
            return ("已打开「" + (vid ? "视频" : "图片") + "去水印」：在画面上框出水印位置，再点「去除水印」。", [])
        }
        if low.contains("识别文字") || low.contains("提取文字") || low.contains("ocr") || low.contains("转文字") || low.contains("转成文字") { target = "txt" }
        else if low.contains("压缩") { target = "compress" }
        else if ["去除声音", "去掉声音", "去掉音频", "去除音频", "静音", "去声音", "去音频", "删除声音", "mute"].contains(where: { low.contains($0) }) { target = "mute" }
        else if low.contains("提取音频") || low.contains("转音频") { target = "m4a" }
        else if let re = try? NSRegularExpression(pattern: "(?:转成|转为|转换成|转换为|转|变成|导出为|导出成|另存为)\\s*(pdf|png|jpg|jpeg|heic|txt|csv|json|md|html|tsv|mp4|mov|m4a|wav|docx|doc|xlsx|xls|word|excel|rtf|文本|表格|图片|网页|音频|视频)"),
                  let m = re.firstMatch(in: low, range: NSRange(low.startIndex..., in: low)),
                  let r = Range(m.range(at: 1), in: low) {
            target = String(low[r])
        }
        guard let tg = target else { return nil }
        do {
            let outs = try await Convert.run(file, to: tg)
            Out.add(outs)
            return ("转换完成，共 \(outs.count) 个文件，点下方文件可预览或分享。", outs)
        } catch {
            return ("转换失败：\(error.localizedDescription)", [])
        }
    }
}
