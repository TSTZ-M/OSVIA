import Foundation
import UIKit
import JavaScriptCore
import EventKit
import AVFoundation
import CoreText

// MARK: 动手能力：用户用自然语言说目标，智能体自己拆步骤、自己调工具、自己写代码把事办完。
// 通用工具（写代码运行、任意网络接口、文件工作区、自己造技能、快捷指令）+ 常用的手机动作（天气、日程、导航、打开 App、短信邮件草稿、倒计时……）。
// 对外有影响、不可撤销的动作（发网络写请求、删文件、运行快捷指令）先问用户；草稿类的动作最后一步由用户自己点发送。

private final class HandsOnce: @unchecked Sendable {
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

private final class JSBox: @unchecked Sendable {
    var lines: [String] = []
    var err = ""
}

@MainActor
enum Hands {
    // MARK: 给模型看的说明（云端大脑给全套，本机模型只给天气）
    static func doc(local: Bool) -> String {
        var s = "- weather {\"city\":\"城市（不填就用用户当前位置）\"}：当前天气和未来 3 天预报（比搜索快、准）\n"
        if local { return s }
        s += "- plan {\"steps\":[\"步骤1\",\"步骤2\"],\"done\":0}：多步任务开始时先列计划，每完成几步再调用一次更新 done。界面会显示进度\n"
        s += "- run_js {\"code\":\"JavaScript\"}：沙盒里运行代码，console.log 输出，最后一个表达式的值也会返回；可用 httpGet(url) 同步取网页/接口文本。计算、日期推算、数据整理、统计排序、格式转换、解析 JSON 都写代码做，不要心算\n"
        s += "- http_request {\"method\":\"GET\",\"url\":\"https://…\",\"headers\":{…},\"body\":\"…\"}：调用任意 https 接口（GET 直接执行，其他方法会先问用户）\n"
        s += "- create_file {\"name\":\"文件名.扩展名\",\"content\":\"内容\"}：生成文件（md txt csv json html pdf ics 等）放进工作区，并附在回复下方供预览分享。文章、表格、简历、代码、日历文件用它交付\n"
        s += "- read_file {\"name\":\"文件名\"} / list_files {} / delete_file {\"name\":\"文件名\"}：读写工作区里的文件（删除会先问用户）\n"
        s += "- save_skill {\"name\":\"技能名\",\"desc\":\"用途\",\"sample\":\"测试输入\",\"code\":\"function(input){…return 字符串;}\"}：没有现成工具时，自己写一个可复用的脚本技能（ES5，可用 fetchText(url) 和 kbSearch(词)），测试通过才保存，之后用 run_skill 调用\n"
        s += "- agenda {\"days\":3}：读取用户未来几天的日历日程和提醒事项（安排时间、问「我明天有什么事」时先用它）\n"
        s += "- timer {\"minutes\":10,\"title\":\"泡面\"}：倒计时，到点响铃（相对时间一律用它，不要自己算绝对时间）\n"
        s += "- maps {\"to\":\"目的地\",\"mode\":\"drive|walk|transit\"} 或 {\"q\":\"咖啡店\"}：打开地图导航或搜索周边\n"
        s += "- open_app {\"name\":\"微信\"} 或 {\"url\":\"https://…\"}：打开常用 App，或在浏览器打开网页\n"
        s += "- compose {\"kind\":\"sms|email|call\",\"to\":\"…\",\"subject\":\"…\",\"body\":\"…\"}：打开短信/邮件草稿或拨号界面，用户确认后才会发出\n"
        s += "- run_shortcut {\"name\":\"快捷指令名\",\"input\":\"文本\"}：运行用户的快捷指令（会先问用户），能做到 App 之外的各种事\n"
        s += "- confirm_action {\"title\":\"要做的事\",\"detail\":\"细节\"}：做对外有影响或不可撤销的事之前先向用户确认，返回允许或拒绝\n"
        s += "- device {}：电量、存储、系统版本、低电量模式；torch {\"on\":true}：手电筒；copy_text {\"text\":\"…\"}：复制到剪贴板\n"
        s += DeviceTools.doc()
        s += MoreTools.doc()
        s += Hands2.doc()
        return s
    }

    // MARK: 分发：不是这里的工具返回 nil
    static func run(_ c: ToolCall, trace: Tracer, cloud: Bool) async -> ToolResult? {
        let a = c.args
        switch c.name {
        case "plan": return plan(a, trace)
        case "weather": return await weather(str(a, "city"), trace)
        case "run_js": return await runJSTool(str(a, "code"), trace)
        case "http_request": return await http(a, trace, cloud: cloud)
        case "create_file": return createFile(str(a, "name"), str(a, "content"), trace)
        case "read_file": return readFile(str(a, "name"), trace)
        case "list_files": return listFiles(trace)
        case "delete_file": return await deleteFile(str(a, "name"), trace)
        case "save_skill": return await saveSkill(a, trace)
        case "agenda": return await agenda((a["days"] as? NSNumber)?.intValue ?? 3, trace)
        case "timer": return await timer(a, trace)
        case "maps": return await maps(a, trace)
        case "open_app": return await openApp(a, trace)
        case "compose": return await compose(a, trace)
        case "run_shortcut": return await shortcut(a, trace)
        case "confirm_action": return await confirmAction(a)
        case "device": return device(trace)
        case "torch": return torch(a, trace)
        case "copy_text":
            let t = str(a, "text")
            guard !t.isEmpty else { return ToolResult(text: "没有要复制的内容。", ok: false) }
            UIPasteboard.general.string = t
            trace.note(.phone, "复制到剪贴板", String(t.prefix(40)))
            return ToolResult(text: "已复制到剪贴板。")
        default:
            return await DeviceTools.run(c, trace: trace, cloud: cloud)
        }
    }

    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: 计划：界面上显示成一条带进度的步骤
    private static func plan(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        let steps = ((a["steps"] as? [Any]) ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !steps.isEmpty else { return ToolResult(text: "计划为空。", ok: false) }
        let done = min(max((a["done"] as? NSNumber)?.intValue ?? 0, 0), steps.count)
        let text = steps.prefix(10).enumerated().map { (i, t) in (i < done ? "✓ " : "○ ") + t }.joined(separator: "\n")
        Agent.shared.mutate(trace.mid) { m in
            if let i = m.steps.firstIndex(where: { $0.kind == .plan }) {
                m.steps[i].detail = text
            } else {
                m.steps.insert(Step(kind: .plan, title: L10n.tr("制定计划"), detail: text, state: 1), at: 0)
            }
        }
        return ToolResult(text: done >= steps.count ? "计划已全部完成，现在向用户汇报结果。" : "计划已记录，现在自己连续执行，不要停下来问用户。")
    }

    // MARK: 天气（Open-Meteo，无需密钥）
    private static func getJSON(_ s: String) async -> [String: Any]? {
        guard let u = URL(string: s) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 10
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func wmo(_ c: Int) -> String {
        switch c {
        case 0: return "晴"
        case 1: return "大部晴朗"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "雪粒"
        case 80, 81: return "阵雨"
        case 82: return "强阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "未知"
        }
    }

    private static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private static func weather(_ city: String, _ trace: Tracer) async -> ToolResult {
        var lat = 0.0
        var lon = 0.0
        var place = ""
        let sid = trace.begin(.weather, "查询天气", city.isEmpty ? L10n.tr("当前位置") : city)
        if city.isEmpty || ["当前位置", "我这里", "这里", "本地", "here"].contains(city.lowercased()) {
            let (fix, err) = await LocationService.shared.current()
            guard let f = fix else {
                trace.end(sid, ok: false, detail: L10n.tr(err))
                return ToolResult(text: err + " 也可以直接告诉我城市名。", ok: false)
            }
            lat = f.lat
            lon = f.lon
            place = f.place.isEmpty ? L10n.tr("当前位置") : f.place
        } else {
            guard let g = await getJSON("https://geocoding-api.open-meteo.com/v1/search?name=\(enc(city))&count=1&language=zh&format=json"),
                  let res = (g["results"] as? [[String: Any]])?.first,
                  let la = num(res["latitude"]), let lo = num(res["longitude"]) else {
                trace.end(sid, ok: false, detail: city + " · " + L10n.tr("没找到这个地点"))
                return ToolResult(text: "没找到「\(city)」这个地点，可以换个写法（比如加上省份或国家）。", ok: false)
            }
            lat = la
            lon = lo
            var parts: [String] = []
            for k in ["name", "admin1", "country"] {
                if let v = res[k] as? String, !v.isEmpty, !parts.contains(v) { parts.append(v) }
            }
            place = parts.joined(separator: " · ")
        }
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=4"
        guard let f = await getJSON(url), let cur = f["current"] as? [String: Any] else {
            trace.end(sid, ok: false, detail: city + " · " + L10n.tr("没有结果"))
            return ToolResult(text: "天气服务暂时没有返回数据，可以稍后再试，或用 web_search 查。", ok: false)
        }
        let n = trace.register(url: "https://open-meteo.com/en/docs#latitude=\(lat)&longitude=\(lon)", title: "Open-Meteo · " + place)
        func t(_ v: Any?) -> String { num(v).map { String(format: "%.0f", $0) } ?? "?" }
        var out = "[\(n)] \(place) 天气（Open-Meteo）\n"
        out += "现在：\(wmo(Int(num(cur["weather_code"]) ?? -1)))，\(t(cur["temperature_2m"]))°C（体感 \(t(cur["apparent_temperature"]))°C），湿度 \(t(cur["relative_humidity_2m"]))%，风 \(t(cur["wind_speed_10m"])) km/h，降水 \(t(cur["precipitation"])) mm\n"
        if let d = f["daily"] as? [String: Any], let days = d["time"] as? [String] {
            let codes = d["weather_code"] as? [Any] ?? []
            let hi = d["temperature_2m_max"] as? [Any] ?? []
            let lo = d["temperature_2m_min"] as? [Any] ?? []
            let pr = d["precipitation_probability_max"] as? [Any] ?? []
            out += "预报：\n"
            for i in days.indices {
                let c = i < codes.count ? Int(num(codes[i]) ?? -1) : -1
                out += "- \(days[i])：\(wmo(c))，\(i < lo.count ? t(lo[i]) : "?")~\(i < hi.count ? t(hi[i]) : "?")°C，降水概率 \(i < pr.count ? t(pr[i]) : "?")%\n"
            }
        }
        trace.end(sid, detail: place + " · " + t(cur["temperature_2m"]) + "°C")
        return ToolResult(text: out)
    }

    // MARK: 运行代码（沙盒，无文件无系统访问，只有 console.log 和 httpGet）
    nonisolated private static func evalJS(_ code: String) -> (Bool, String) {
        guard let ctx = JSContext() else { return (false, "脚本环境创建失败") }
        let box = JSBox()
        ctx.exceptionHandler = { _, e in box.err = e?.toString() ?? "运行出错" }
        let log: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []
            box.lines.append(args.map { ($0 as? JSValue)?.toString() ?? "" }.joined(separator: " "))
        }
        if let console = JSValue(newObjectIn: ctx) {
            for k in ["log", "info", "warn", "error"] { console.setObject(log, forKeyedSubscript: k as NSString) }
            ctx.setObject(console, forKeyedSubscript: "console" as NSString)
        }
        let get: @convention(block) (String) -> String = { u in
            guard let url = URL(string: u), url.scheme == "https", let d = try? Data(contentsOf: url) else { return "" }
            return String(decoding: d.prefix(30000), as: UTF8.self)
        }
        ctx.setObject(get, forKeyedSubscript: "httpGet" as NSString)
        let v = ctx.evaluateScript(code)
        if !box.err.isEmpty { return (false, "代码出错：" + box.err + (box.lines.isEmpty ? "" : "\n已输出：\n" + box.lines.joined(separator: "\n"))) }
        var res = ""
        if let v, !v.isUndefined, !v.isNull {
            if v.isObject, !v.isString, let j = ctx.objectForKeyedSubscript("JSON")?.objectForKeyedSubscript("stringify")?.call(withArguments: [v]), !j.isUndefined {
                res = j.toString() ?? ""
            } else {
                res = v.toString() ?? ""
            }
        }
        var out = box.lines.joined(separator: "\n")
        if !res.isEmpty { out += (out.isEmpty ? "" : "\n") + "返回值：" + res }
        return (true, out.isEmpty ? "代码运行完了，没有输出（用 console.log 输出结果）。" : out)
    }

    private static func background(timeout: Double, _ work: @escaping @Sendable () -> (Bool, String)) async -> (Bool, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(Bool, String), Never>) in
            let once = HandsOnce()
            DispatchQueue.global(qos: .userInitiated).async {
                let r = work()
                if once.claim() { c.resume(returning: r) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { c.resume(returning: (false, "运行超过 \(Int(timeout)) 秒，已放弃等待。")) }
            }
        }
    }

    private static func runJSTool(_ code: String, _ trace: Tracer) async -> ToolResult {
        guard !code.isEmpty else { return ToolResult(text: "没有代码。", ok: false) }
        let compact = code.replacingOccurrences(of: " ", with: "")
        if compact.contains("while(true)") || compact.contains("for(;;)") || compact.contains("while(1)") {
            return ToolResult(text: "代码里有死循环，请改成有终止条件的写法。", ok: false)
        }
        let first = code.split(separator: "\n").first.map(String.init) ?? code
        let sid = trace.begin(.code, "运行代码", String(first.prefix(50)))
        let r = await background(timeout: code.contains("httpGet") ? 20 : 6) { evalJS(code) }
        trace.end(sid, ok: r.0, detail: r.0 ? String(r.1.replacingOccurrences(of: "\n", with: " ").prefix(60)) : String(r.1.prefix(60)))
        return ToolResult(text: String(r.1.prefix(5000)), ok: r.0)
    }

    // MARK: 自己造技能
    private static func saveSkill(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let name = str(a, "name")
        let desc = str(a, "desc")
        let code = Skills.clean(str(a, "code"))
        guard !name.isEmpty, !code.isEmpty else { return ToolResult(text: "技能需要名称和代码。", ok: false) }
        let sid = trace.begin(.skill, "创建技能", name)
        let sample = str(a, "sample")
        let r = await background(timeout: 15) { Skills.runCode(code, sample) }
        if !r.0 {
            trace.end(sid, ok: false, detail: name + " · " + String(r.1.prefix(40)))
            return ToolResult(text: "技能测试没通过，没有保存：\(r.1)。请修改代码后重新调用 save_skill。", ok: false)
        }
        Skills.save(name, desc.isEmpty ? name : desc, code)
        trace.end(sid, detail: name)
        return ToolResult(text: "技能「\(name)」测试通过并已保存，测试输出：\(String(r.1.prefix(300)))。以后可以用 run_skill 调用。")
    }

    // MARK: 任意 https 接口
    private static func blockedHost(_ h: String) -> Bool {
        let s = h.lowercased()
        if s == "localhost" || s.hasSuffix(".local") || s.hasSuffix(".internal") { return true }
        if s.hasPrefix("127.") || s.hasPrefix("10.") || s.hasPrefix("192.168.") || s.hasPrefix("169.254.") || s.hasPrefix("0.") { return true }
        if s.hasPrefix("172.") {
            let p = s.split(separator: ".")
            if p.count > 1, let n = Int(p[1]), (16...31).contains(n) { return true }
        }
        return s.contains(":") || s == "::1"
    }

    private static func http(_ a: [String: Any], _ trace: Tracer, cloud: Bool) async -> ToolResult {
        let method = str(a, "method").isEmpty ? "GET" : str(a, "method").uppercased()
        guard let u = URL(string: str(a, "url")), u.scheme == "https", let host = u.host, !blockedHost(host) else {
            return ToolResult(text: "只支持公网的 https 地址。", ok: false)
        }
        var body = str(a, "body")
        if body.isEmpty, let j = a["json"], JSONSerialization.isValidJSONObject(j), let d = try? JSONSerialization.data(withJSONObject: j) {
            body = String(decoding: d, as: UTF8.self)
        }
        if method != "GET" && method != "HEAD" {
            let ok = await Agent.shared.requestConfirm(title: L10n.tr("允许发送网络请求？"), detail: "\(method) \(host)\n" + String(body.prefix(160)))
            if !ok { return ToolResult(text: "用户拒绝了这次请求，没有发送。请告诉用户你没有执行。", ok: false) }
        }
        let sid = trace.begin(.connector, "调用接口", "\(method) \(host)")
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.timeoutInterval = 20
        if let h = a["headers"] as? [String: Any] {
            for (k, v) in h { r.setValue("\(v)", forHTTPHeaderField: k) }
        }
        if !body.isEmpty {
            r.httpBody = body.data(using: .utf8)
            if r.value(forHTTPHeaderField: "Content-Type") == nil {
                r.setValue(body.hasPrefix("{") || body.hasPrefix("[") ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(decoding: d.prefix(cloud ? 8000 : 3000), as: UTF8.self)
            trace.end(sid, ok: (200..<300).contains(code), detail: "\(method) \(host) · HTTP \(code)")
            return ToolResult(text: "HTTP \(code)\n" + text, ok: (200..<300).contains(code))
        } catch {
            trace.end(sid, ok: false, detail: host + " · " + String(error.localizedDescription.prefix(40)))
            return ToolResult(text: "请求失败：" + error.localizedDescription, ok: false)
        }
    }

    // MARK: 文件工作区
    static var work: URL { Store.dir("工作区") }

    static func safeName(_ raw: String, defaultExt: String = "md") -> String {
        var n = (raw as NSString).lastPathComponent
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        if n.isEmpty { n = "文件" }
        if (n as NSString).pathExtension.isEmpty { n += "." + defaultExt }
        return String(n.suffix(80))
    }

    static func uniqueURL(_ name: String) -> URL {
        var u = work.appendingPathComponent(name)
        var i = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: u.path) {
            u = work.appendingPathComponent("\(base)-\(i).\(ext)")
            i += 1
        }
        return u
    }

    private static func plainText(_ md: String) -> String {
        var out: [String] = []
        for l in md.components(separatedBy: "\n") {
            var s = l
            if let r = s.range(of: "^#{1,6}\\s+", options: .regularExpression) { s.removeSubrange(r) }
            if s.hasPrefix("- ") || s.hasPrefix("* ") { s = "• " + s.dropFirst(2) }
            s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            out.append(s)
        }
        return out.joined(separator: "\n")
    }

    private static func writePDF(_ text: String, to url: URL) {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let inset: CGFloat = 54
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        let attr = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12), .paragraphStyle: style, .foregroundColor: UIColor.black])
        let fs = CTFramesetterCreateWithAttributedString(attr)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try? renderer.writePDF(to: url) { ctx in
            var idx = 0
            repeat {
                ctx.beginPage()
                let c = ctx.cgContext
                c.saveGState()
                c.translateBy(x: 0, y: page.height)
                c.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: inset, y: inset, width: page.width - inset * 2, height: page.height - inset * 2), transform: nil)
                let frame = CTFramesetterCreateFrame(fs, CFRange(location: idx, length: 0), path, nil)
                CTFrameDraw(frame, c)
                let vis = CTFrameGetVisibleStringRange(frame)
                c.restoreGState()
                if vis.length == 0 { break }
                idx += vis.length
            } while idx < attr.length
        }
    }

    private static func createFile(_ rawName: String, _ content: String, _ trace: Tracer) -> ToolResult {
        guard !content.isEmpty else { return ToolResult(text: "内容为空。", ok: false) }
        let name = safeName(rawName)
        let ext = (name as NSString).pathExtension.lowercased()
        let sid = trace.begin(.file, "生成文件", name)
        let url = uniqueURL(name)
        if ext == "pdf" {
            writePDF(plainText(content), to: url)
        } else {
            let text = ext == "csv" ? "\u{FEFF}" + content : content
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
                trace.end(sid, ok: false, detail: name + " · " + String(error.localizedDescription.prefix(40)))
                return ToolResult(text: "写文件失败：" + error.localizedDescription, ok: false)
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            trace.end(sid, ok: false, detail: name)
            return ToolResult(text: "文件没有生成成功。", ok: false)
        }
        Agent.shared.mutate(trace.mid) { $0.files.append(url) }
        trace.end(sid, detail: url.lastPathComponent)
        return ToolResult(text: "已生成文件「\(url.lastPathComponent)」，附在回复下方，用户点开可预览、分享或存到「文件」。不要再贴出全文，用一两句话说明内容即可。")
    }

    private static func readFile(_ rawName: String, _ trace: Tracer) -> ToolResult {
        let url = work.appendingPathComponent(safeName(rawName))
        guard let d = try? Data(contentsOf: url) else { return ToolResult(text: "工作区里没有这个文件，可以先用 list_files 看看。", ok: false) }
        trace.note(.file, "读取文件", url.lastPathComponent)
        let t = String(decoding: d.prefix(12000), as: UTF8.self)
        return ToolResult(text: t + (d.count > 12000 ? "\n…（文件较长，只读了前 12000 字节）" : ""))
    }

    private static func listFiles(_ trace: Tracer) -> ToolResult {
        let names = ((try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        trace.note(.file, "查看工作区", L10n.f("{} 个文件", "\(names.count)"))
        if names.isEmpty { return ToolResult(text: "工作区是空的。") }
        let lines = names.prefix(40).map { u -> String in
            let sz = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return "- \(u.lastPathComponent)（\(sz / 1024 + 1) KB）"
        }
        return ToolResult(text: lines.joined(separator: "\n"))
    }

    private static func deleteFile(_ rawName: String, _ trace: Tracer) async -> ToolResult {
        let url = work.appendingPathComponent(safeName(rawName))
        guard FileManager.default.fileExists(atPath: url.path) else { return ToolResult(text: "工作区里没有这个文件。", ok: false) }
        let ok = await Agent.shared.requestConfirm(title: L10n.tr("允许删除文件？"), detail: url.lastPathComponent)
        if !ok { return ToolResult(text: "用户拒绝了删除，文件保留。", ok: false) }
        try? FileManager.default.removeItem(at: url)
        trace.note(.file, "删除文件", url.lastPathComponent)
        return ToolResult(text: "已删除「\(url.lastPathComponent)」。")
    }

    // MARK: 日程
    private static func agenda(_ daysIn: Int, _ trace: Tracer) async -> ToolResult {
        let days = min(max(daysIn, 1), 14)
        let sid = trace.begin(.time, "查看日程", L10n.f("未来 {} 天", "\(days)"))
        let store = EKEventStore()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        var out = ""
        if let ok = try? await store.requestFullAccessToEvents(), ok {
            let evs = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
            out += "日历（\(evs.count) 项）：\n"
            for e in evs.prefix(30) {
                let loc = (e.location ?? "").isEmpty ? "" : "（" + (e.location ?? "") + "）"
                out += "- " + (e.isAllDay ? String(f.string(from: e.startDate).prefix(5)) + " 全天" : f.string(from: e.startDate) + "–" + String(f.string(from: e.endDate).suffix(5))) + " " + (e.title ?? "") + loc + "\n"
            }
        } else {
            out += "没有日历权限（用户可以在系统设置里允许）。\n"
        }
        if let ok = try? await store.requestFullAccessToReminders(), ok {
            let pred = store.predicateForReminders(in: nil)
            let all: [EKReminder] = await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
                store.fetchReminders(matching: pred) { @Sendable r in c.resume(returning: r ?? []) }
            }
            let todo = all.filter { r in
                guard !r.isCompleted, let comps = r.dueDateComponents, let d = cal.date(from: comps) else { return false }
                return d < end
            }
            out += "提醒事项（未完成且到期 \(todo.count) 项）：\n"
            for r in todo.prefix(20) {
                let d = r.dueDateComponents.flatMap { cal.date(from: $0) }
                out += "- " + (d.map { f.string(from: $0) } ?? "") + " " + (r.title ?? "") + "\n"
            }
        }
        trace.end(sid)
        return ToolResult(text: out.isEmpty ? "没有读到日程。" : out)
    }

    // MARK: 倒计时
    private static func timer(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let mins = (a["minutes"] as? NSNumber)?.doubleValue ?? 0
        let secs = (a["seconds"] as? NSNumber)?.doubleValue ?? 0
        let total = mins * 60 + secs
        guard total >= 5, total <= 24 * 3600 else { return ToolResult(text: "倒计时要在 5 秒到 24 小时之间。", ok: false) }
        let title = str(a, "title").isEmpty ? "倒计时" : String(str(a, "title").prefix(20))
        let end = Date().addingTimeInterval(total)
        let sid = trace.begin(.action, "设置倒计时", title)
        Live.set(.working)
        let r: String
        if let t = await Sys.timer(total, title) { r = t } else { r = await Sys.alarm(end, title) }
        trace.end(sid, detail: title + " · " + Sys.friendly(end))
        return ToolResult(text: r, final: true)
    }

    // MARK: 地图、打开 App、草稿、快捷指令
    private static func openURL(_ s: String) async -> Bool {
        guard let u = URL(string: s) else { return false }
        return await UIApplication.shared.open(u)
    }

    private static func maps(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let to = str(a, "to")
        let q = str(a, "q")
        var s = "https://maps.apple.com/?"
        if !to.isEmpty {
            let flag = ["walk": "w", "transit": "r"][str(a, "mode")] ?? "d"
            s += "daddr=\(enc(to))&dirflg=\(flag)"
            if !str(a, "from").isEmpty { s += "&saddr=\(enc(str(a, "from")))" }
        } else if !q.isEmpty {
            s += "q=\(enc(q))"
        } else {
            return ToolResult(text: "需要目的地 to 或搜索词 q。", ok: false)
        }
        let label = to.isEmpty ? q : to
        let sid = trace.begin(.map, to.isEmpty ? "地图搜索" : "地图导航", label)
        let ok = await openURL(s)
        trace.end(sid, ok: ok, detail: label)
        return ToolResult(text: ok ? (to.isEmpty ? L10n.f("已在地图里搜索「{}」。", label) : L10n.f("已在地图里打开去「{}」的路线，点开始即可导航。", label)) : "地图没能打开。", final: ok, ok: ok)
    }

    static let apps: [(names: [String], url: String)] = [
        (["微信", "wechat", "weixin"], "weixin://"), (["支付宝", "alipay"], "alipay://"), (["淘宝", "taobao"], "taobao://"),
        (["京东", "jd"], "openapp.jdmobile://"), (["拼多多"], "pinduoduo://"), (["美团"], "imeituan://"), (["饿了么"], "eleme://"),
        (["抖音", "douyin", "tiktok"], "snssdk1128://"), (["微博", "weibo"], "sinaweibo://"), (["小红书", "xiaohongshu"], "xhsdiscover://"),
        (["哔哩哔哩", "b站", "bilibili"], "bilibili://"), (["qq"], "mqq://"), (["高德", "高德地图"], "iosamap://"), (["百度地图"], "baidumap://"),
        (["网易云音乐", "网易云"], "orpheus://"), (["qq音乐"], "qqmusic://"), (["知乎", "zhihu"], "zhihu://"), (["滴滴"], "diditaxi://"),
        (["钉钉", "dingtalk"], "dingtalk://"), (["飞书", "lark", "feishu"], "lark://"), (["企业微信"], "wxwork://"),
        (["照片", "相册", "photos"], "photos-redirect://"), (["音乐", "apple music", "music"], "music://"), (["备忘录", "notes"], "mobilenotes://"),
        (["日历", "calendar"], "calshow://"), (["提醒事项", "reminders"], "x-apple-reminderkit://"), (["邮件", "mail"], "message://"),
        (["信息", "短信", "messages"], "sms:"), (["电话", "phone"], "tel:"), (["地图", "maps"], "maps://"), (["快捷指令", "shortcuts"], "shortcuts://"),
        (["天气", "weather"], "weather://"), (["健康", "health"], "x-apple-health://"), (["钱包", "wallet"], "shoebox://"),
        (["app store", "应用商店"], "itms-apps://"), (["facetime"], "facetime://"),
        (["obsidian"], "obsidian://"), (["notion"], "notion://"), (["bear"], "bear://"), (["things"], "things:///"),
        (["pages"], "pages://"), (["numbers"], "numbers://"), (["keynote"], "keynote://"), (["word"], "ms-word://"),
        (["excel"], "ms-excel://"), (["telegram"], "tg://"), (["whatsapp"], "whatsapp://"), (["chatgpt"], "chatgpt://"),
        (["gmail"], "googlegmail://"), (["outlook"], "ms-outlook://"), (["spotify"], "spotify://"), (["youtube"], "youtube://"),
        (["谷歌地图", "google maps"], "comgooglemaps://")
    ]

    // 这些 App 的自带 scheme 无需检测，一定存在
    private static let builtin: Set<String> = ["photos-redirect://", "music://", "mobilenotes://", "calshow://", "x-apple-reminderkit://", "message://", "sms:", "tel:", "maps://", "shortcuts://", "weather://", "x-apple-health://", "shoebox://", "itms-apps://", "facetime://"]

    // 能检测到的已安装 App（系统只允许检测 Info.plist 里声明过的 scheme）
    static func installedApps() -> [String] {
        let declared = Set((Bundle.main.infoDictionary?["LSApplicationQueriesSchemes"] as? [String]) ?? [])
        var out: [String] = []
        for a in apps where !builtin.contains(a.url) {
            let scheme = (a.url.components(separatedBy: ":").first ?? "")
            guard declared.contains(scheme), let u = URL(string: a.url), UIApplication.shared.canOpenURL(u) else { continue }
            out.append(a.names[0])
        }
        return out
    }

    static func workspaceURL(_ rawName: String) -> URL? {
        let u = work.appendingPathComponent(safeName(rawName))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private static func openApp(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let urlStr = str(a, "url")
        if !urlStr.isEmpty {
            guard let u = URL(string: urlStr), u.scheme == "https" || u.scheme == "http" else { return ToolResult(text: "只能打开 http(s) 网址。", ok: false) }
            let sid = trace.begin(.phone, "打开网页", u.host ?? urlStr)
            let ok = await UIApplication.shared.open(u)
            trace.end(sid, ok: ok)
            return ToolResult(text: ok ? L10n.f("已打开 {}。", u.host ?? urlStr) : "网页没能打开。", final: ok, ok: ok)
        }
        let name = str(a, "name").lowercased()
        guard !name.isEmpty else { return ToolResult(text: "需要 name 或 url。", ok: false) }
        guard let app = apps.first(where: { $0.names.contains(where: { name == $0 || name.contains($0) }) }) else {
            return ToolResult(text: "不认识这个 App。支持：" + apps.prefix(24).map { $0.names[0] }.joined(separator: "、") + " 等。", ok: false)
        }
        let sid = trace.begin(.phone, "打开应用", app.names[0])
        let ok = await openURL(app.url)
        trace.end(sid, ok: ok, detail: ok ? nil : app.names[0] + " · " + L10n.tr("没有安装或无法打开"))
        return ToolResult(text: ok ? L10n.f("已打开 {}。", app.names[0]) : L10n.f("{} 没有安装，或系统不允许打开。", app.names[0]), final: ok, ok: ok)
    }

    private static func compose(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let kind = str(a, "kind")
        let to = str(a, "to").filter { !$0.isWhitespace }
        let body = str(a, "body")
        var s = ""
        var label = ""
        switch kind {
        case "sms":
            s = "sms:\(to)&body=\(enc(body))"
            label = "短信草稿"
        case "email":
            s = "mailto:\(to)?subject=\(enc(str(a, "subject")))&body=\(enc(body))"
            label = "邮件草稿"
        case "call":
            let digits = to.filter { $0.isNumber || $0 == "+" }
            guard !digits.isEmpty else { return ToolResult(text: "没有号码。", ok: false) }
            s = "tel:\(digits)"
            label = "拨号"
        default:
            return ToolResult(text: "kind 只能是 sms、email、call。", ok: false)
        }
        let sid = trace.begin(.phone, label, to)
        let ok = await openURL(s)
        trace.end(sid, ok: ok, detail: to)
        let done = kind == "call" ? "已打开拨号界面，确认后才会拨出。" : "已打开\(label)，内容已填好，请你检查后自己点发送。"
        return ToolResult(text: ok ? done : "没能打开。", final: ok, ok: ok)
    }

    private static func shortcut(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let name = str(a, "name")
        guard !name.isEmpty else { return ToolResult(text: "需要快捷指令名。", ok: false) }
        let input = str(a, "input")
        let ok = await Agent.shared.requestConfirm(title: L10n.tr("允许运行快捷指令？"), detail: name + (input.isEmpty ? "" : "\n" + String(input.prefix(160))))
        if !ok { return ToolResult(text: "用户拒绝了，没有运行。请告诉用户你没有执行。", ok: false) }
        var s = "shortcuts://x-callback-url/run-shortcut?name=\(enc(name))"
        if !input.isEmpty { s += "&input=text&text=\(enc(input))" }
        s += "&x-success=osvia://shortcut&x-cancel=osvia://shortcut&x-error=osvia://shortcut"
        let sid = trace.begin(.phone, "运行快捷指令", name)
        let opened = await openURL(s)
        trace.end(sid, ok: opened, detail: name)
        return ToolResult(text: opened ? L10n.f("已交给快捷指令「{}」运行。", name) : "快捷指令没能打开，请确认名称正确且已安装快捷指令。", final: opened, ok: opened)
    }

    private static func confirmAction(_ a: [String: Any]) async -> ToolResult {
        let title = str(a, "title")
        guard !title.isEmpty else { return ToolResult(text: "需要说明要做什么。", ok: false) }
        let ok = await Agent.shared.requestConfirm(title: title, detail: str(a, "detail"))
        return ToolResult(text: ok ? "用户允许了，可以继续执行。" : "用户拒绝了，不要执行，并告诉用户已取消。")
    }

    // MARK: 设备
    private static func device(_ trace: Tracer) -> ToolResult {
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        let lvl = d.batteryLevel < 0 ? "未知" : "\(Int(d.batteryLevel * 100))%"
        let st: String
        switch d.batteryState {
        case .charging: st = "充电中"
        case .full: st = "已充满"
        case .unplugged: st = "未充电"
        default: st = "未知"
        }
        var free = "未知"
        if let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            free = String(format: "%.1f GB", Double(v) / 1_000_000_000)
        }
        trace.note(.phone, "查看设备状态", lvl)
        return ToolResult(text: "电量 \(lvl)（\(st)），低电量模式\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "开" : "关")，可用存储 \(free)，\(d.systemName) \(d.systemVersion)，设备 \(d.model)。")
    }

    private static func torch(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        let on = (a["on"] as? Bool) ?? ((a["on"] as? NSNumber)?.boolValue ?? true)
        guard let dev = AVCaptureDevice.default(for: .video), dev.hasTorch else { return ToolResult(text: "这台设备没有手电筒。", ok: false) }
        do {
            try dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        } catch {
            return ToolResult(text: "手电筒没能切换：" + error.localizedDescription, ok: false)
        }
        trace.note(.phone, on ? "打开手电筒" : "关闭手电筒")
        return ToolResult(text: on ? "手电筒已打开。" : "手电筒已关闭。", final: true)
    }
}
