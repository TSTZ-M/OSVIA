import Foundation
import UIKit
import PDFKit

// MARK: 对话里调用的第二批动手工具：PDF、打码、抠图、读二维码、图片处理、zip 打包与解压
@MainActor
enum Toolkit2 {
    static func doc() -> String {
        var s = ""
        s += "- pdf_tool {\"op\":\"merge|split|extract|rotate|compress|protect|unlock|numbers|watermark|images\",\"names\":[\"文件名\",…],\"pages\":\"1-3,5,8-\",\"angle\":90,\"password\":\"密码\",\"text\":\"水印文字\",\"quality\":\"light|medium|strong\"}：本机处理 PDF。merge 合并多个 PDF/图片（按 names 顺序）；split 拆分（pages 留空=每页一个文件）；extract 只留 pages 指定页；rotate 顺时针旋转 angle 度；compress 压缩体积（页面变图片，文字不可选）；protect 加打开密码；unlock 用 password 解除密码；numbers 加页码；watermark 加斜向水印；images 把多张图片做成 PDF。names 留空=最近的文件；结果附在回复下方\n"
        s += "- redact {\"name\":\"图片文件名\",\"kinds\":[\"phone\",\"idcard\",\"bank\",\"email\",\"url\",\"plate\",\"face\",\"all\"],\"style\":\"mosaic|black\"}：自动找出图里的手机号、身份证号、银行卡号、邮箱、网址、车牌、人脸并打码，导出图同时清除拍摄位置等信息。kinds 留空=手机号+身份证+银行卡+邮箱+车牌+人脸；all=所有文字\n"
        s += "- cutout {\"name\":\"图片文件名\",\"bg\":\"clear|white|blue|red|gray\",\"crop\":false}：抠出人物或物品主体。clear 输出透明 PNG；white blue red 是证件照底色（输出 JPG）；crop 为 true 时裁到主体边缘\n"
        s += "- scan_code {\"name\":\"图片文件名\"}：读取图片里的二维码、条形码，返回内容（链接、Wi‑Fi、商品码）\n"
        s += "- image_edit {\"name\":\"图片文件名\",\"op\":\"resize|compress|rotate|flip|crop|strip\",\"long_side\":1080,\"max_kb\":500,\"angle\":90,\"flip\":\"h|v\",\"ratio\":\"1:1\"}：图片处理。resize 按长边缩小；compress 压缩到不超过 max_kb；rotate 顺时针旋转；flip 左右(h)或上下(v)翻转；crop 从中心按 ratio（如 1:1 4:3 16:9）裁剪；strip 清除位置、设备型号等隐私信息\n"
        s += "- media_edit {\"op\":\"trim|gif|speed|frame|merge\",\"names\":[\"文件名\"],\"start\":0,\"end\":10,\"length\":4,\"speed\":2,\"at\":3.5}：音视频剪辑（单位秒）。trim 保留 start 到 end；gif 从 start 起截 length 秒（最长 10）做成 GIF；speed 倍速；frame 截取 at 秒处的画面；merge 按 names 顺序合并多个视频或音频\n"
        s += "- transcribe {\"name\":\"音频或视频文件名\",\"language\":\"zh-CN|en-US|ja-JP|ko-KR|yue-CN\"}：把录音或视频转成文字（本机识别），同时生成 txt 和 SRT 字幕附在回复下方；language 留空=系统语言。耗时约为音频时长的 1/5 到 1/2，长文件请先告诉用户需要等一会儿\n"
        s += "- zip {\"names\":[\"文件名\",…],\"out\":\"压缩包名\"}：把工作区的文件打成 zip；unzip {\"name\":\"压缩包文件名\"}：解压 zip，文件放进输出目录并附在回复下方\n"
        return s
    }

    static func run(_ c: ToolCall, trace: Tracer) async -> ToolResult? {
        switch c.name {
        case "pdf_tool": return await pdfTool(c.args, trace)
        case "redact": return await redact(c.args, trace)
        case "cutout": return await cutout(c.args, trace)
        case "scan_code": return await scanCode(c.args, trace)
        case "image_edit": return await imageEdit(c.args, trace)
        case "media_edit": return await mediaEdit(c.args, trace)
        case "transcribe": return await transcribe(c.args, trace)
        case "zip": return zip(c.args, trace)
        case "unzip": return unzip(c.args, trace)
        default: return nil
        }
    }

    // MARK: 小工具
    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func num(_ a: [String: Any], _ k: String) -> Double? {
        if let n = a[k] as? NSNumber { return n.doubleValue }
        return Double(str(a, k))
    }

    // 模型给的数字可能是 NaN/无穷/超大值，直接 Int() 会崩溃，这里统一截断到安全范围
    private static func int(_ a: [String: Any], _ k: String, _ def: Int, _ lo: Int, _ hi: Int) -> Int {
        guard let d = num(a, k), d.isFinite else { return def }
        return Int(min(Double(hi), max(Double(lo), d)))
    }

    private static func attach(_ urls: [URL], _ trace: Tracer) {
        for u in urls { Agent.shared.mutate(trace.mid) { $0.files.append(u) } }
    }

    // names 数组、单个 name、或留空（最近的文件）
    private static func targets(_ a: [String: Any]) -> (urls: [URL], missing: [String]) {
        var names: [String] = []
        if let arr = a["names"] as? [String] { names = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        if names.isEmpty, !str(a, "name").isEmpty { names = [str(a, "name")] }
        if names.isEmpty {
            if let u = Toolkit.file("") { return ([u], []) }
            return ([], [])
        }
        var urls: [URL] = []
        var missing: [String] = []
        for n in names {
            if let u = Toolkit.file(n) { urls.append(u) } else { missing.append(n) }
        }
        return (urls, missing)
    }

    private static let noFile = ToolResult(text: "没有找到这个文件。请让用户先发送文件，或用工作区里的文件名。", ok: false)

    private static func fail(_ trace: Tracer, _ sid: UUID, _ error: Error, _ what: String) -> ToolResult {
        trace.end(sid, ok: false, detail: String(error.localizedDescription.prefix(40)))
        return ToolResult(text: what + "失败：" + error.localizedDescription, ok: false)
    }

    // MARK: PDF
    private static func pdfTool(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let op = PDFOps.Op.parse(str(a, "op")) else {
            return ToolResult(text: "op 需要是：" + PDFOps.Op.allCases.map { $0.rawValue }.joined(separator: " / "), ok: false)
        }
        let t = targets(a)
        guard !t.urls.isEmpty else { return noFile }
        let spec = str(a, "pages")
        let angle = int(a, "angle", 90, -3600, 3600)
        let pw = str(a, "password")
        let mark = str(a, "text")
        let q: Int = { switch str(a, "quality").lowercased() { case "light", "high", "轻度": return 2; case "strong", "low", "强力": return 0; default: return 1 } }()
        let urls = t.urls
        let sid = trace.begin(.file, "PDF " + op.title, urls.map { $0.lastPathComponent }.joined(separator: "、"))
        do {
            let r = try await Task<([URL], String), Error>.detached(priority: .userInitiated) {
                try PDFOps.perform(op, files: urls, spec: spec, angle: angle, password: pw, mark: mark, quality: q)
            }.value
            attach(r.0, trace)
            trace.end(sid, detail: r.0.map { $0.lastPathComponent }.joined(separator: "、"))
            var out = "已完成，生成 \(r.0.count) 个文件：" + r.0.map { $0.lastPathComponent }.joined(separator: "、") + "，已附在回复下方。"
            if !r.1.isEmpty { out += "体积：" + r.1 + "。" }
            if !t.missing.isEmpty { out += "没找到：" + t.missing.joined(separator: "、") + "。" }
            return ToolResult(text: out + "一句话说明即可。")
        } catch {
            return fail(trace, sid, error, "PDF 处理")
        }
    }

    // MARK: 打码
    private static func redact(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = targets(a).urls.first, Files.isImage(u) else { return ToolResult(text: "没有找到图片。请让用户先发送图片。", ok: false) }
        var kinds = Set<Redact.Kind>()
        if let arr = a["kinds"] as? [String] { for k in arr { if let kk = Redact.Kind.parse(k) { kinds.insert(kk) } } }
        if let one = a["kinds"] as? String { for k in one.components(separatedBy: CharacterSet(charactersIn: ",，、 ")) { if let kk = Redact.Kind.parse(k) { kinds.insert(kk) } } }
        if kinds.isEmpty { kinds = [.phone, .idcard, .bank, .email, .plate, .face] }
        let style: Redact.Style = str(a, "style") == "black" ? .black : .mosaic
        let sid = trace.begin(.file, "图片打码", u.lastPathComponent)
        do {
            let ks = kinds
            let r = try await Task<(URL, Int), Error>.detached(priority: .userInitiated) { try Redact.run(u, kinds: ks, style: style) }.value
            attach([r.0], trace)
            trace.end(sid, detail: L10n.f("{} 处", "\(r.1)"))
            return ToolResult(text: "已打码 \(r.1) 处并附在回复下方（拍摄位置等信息也已清除）。提醒用户自己看一眼有没有漏的。")
        } catch {
            return fail(trace, sid, error, "打码")
        }
    }

    // MARK: 抠图
    private static func cutout(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = targets(a).urls.first, Files.isImage(u) else { return ToolResult(text: "没有找到图片。请让用户先发送图片。", ok: false) }
        let bg = Cutout.Background.parse(str(a, "bg"))
        let crop = (a["crop"] as? Bool) == true
        let sid = trace.begin(.file, "抠图", u.lastPathComponent)
        do {
            let r = try await Task<URL, Error>.detached(priority: .userInitiated) { try Cutout.run(u, bg: bg, crop: crop) }.value
            attach([r], trace)
            trace.end(sid, detail: r.lastPathComponent)
            return ToolResult(text: "已抠出主体（\(bg.title)）并附在回复下方。")
        } catch {
            return fail(trace, sid, error, "抠图")
        }
    }

    // MARK: 读二维码
    private static func scanCode(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = targets(a).urls.first, Files.isImage(u) else { return ToolResult(text: "没有找到图片。请让用户先发送图片。", ok: false) }
        let sid = trace.begin(.file, "读取二维码", u.lastPathComponent)
        let items = await Task<[Barcode.Item], Never>.detached(priority: .userInitiated) { Barcode.scan(u) }.value
        guard !items.isEmpty else {
            trace.end(sid, ok: false, detail: L10n.tr("没有找到"))
            return ToolResult(text: "图片里没有找到二维码或条形码。", ok: false)
        }
        trace.end(sid, detail: L10n.f("{} 个", "\(items.count)"))
        let lines = items.map { it -> String in
            if let w = it.wifi { return "\(it.type)：Wi-Fi 名称「\(w.ssid)」，密码「\(w.password)」，加密 \(w.security)" }
            return "\(it.type)：\(it.text)"
        }
        return ToolResult(text: lines.joined(separator: "\n"))
    }

    // MARK: 图片处理
    private static func imageEdit(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = targets(a).urls.first, Files.isImage(u) else { return ToolResult(text: "没有找到图片。请让用户先发送图片。", ok: false) }
        let op = str(a, "op").lowercased()
        let long = int(a, "long_side", 1080, 16, 16384)
        let kb = int(a, "max_kb", 500, 20, 102400)
        let angle = int(a, "angle", 90, -3600, 3600)
        let flip = str(a, "flip").lowercased()
        let ratioText = str(a, "ratio")
        let cx = num(a, "x"), cy = num(a, "y"), cw = num(a, "w"), ch = num(a, "h")
        let sid = trace.begin(.file, "图片处理", op + " · " + u.lastPathComponent)
        do {
            let r = try await Task<(URL, String), Error>.detached(priority: .userInitiated) {
                let cg = try ImageOps.readCG(u)
                let base = ToolFS.base(u)
                let before = ToolFS.size(u)
                let dst: URL
                switch op {
                case "resize":
                    dst = try ImageOps.write(ImageOps.resize(cg, longSide: max(64, long)), like: u, base: base + "-\(long)px")
                case "compress":
                    guard let d = ImageOps.jpegUnder(ImageOps.resize(cg, longSide: 4096), maxKB: max(20, kb)) else { throw Convert.err("压缩失败") }
                    dst = ToolFS.out(base + "-" + String(kb) + "KB", "jpg")
                    try d.write(to: dst)
                case "rotate":
                    dst = try ImageOps.write(ImageOps.rotate(cg, degrees: angle), like: u, base: base + "-旋转")
                case "flip":
                    dst = try ImageOps.write(ImageOps.rotate(cg, degrees: 0, flipH: flip != "v", flipV: flip == "v"), like: u, base: base + "-翻转")
                case "crop":
                    let w = Double(cg.width), h = Double(cg.height)
                    var rect: (Double, Double, Double, Double)
                    if let x = cx, let y = cy, let ww = cw, let hh = ch {
                        rect = (x, y, ww, hh)
                    } else {
                        let parts = ratioText.replacingOccurrences(of: "：", with: ":").components(separatedBy: ":").compactMap { Double($0) }
                        let rr = parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : 1
                        var tw = w, th = w / rr
                        if th > h { th = h; tw = h * rr }
                        rect = ((w - tw) / 2 / w, (h - th) / 2 / h, tw / w, th / h)
                    }
                    guard let c = ImageOps.crop(cg, x: rect.0, y: rect.1, w: rect.2, h: rect.3) else { throw Convert.err("裁剪范围不正确") }
                    dst = try ImageOps.write(c, like: u, base: base + "-裁剪")
                case "strip":
                    dst = try ImageOps.write(cg, like: u, base: base + "-已清除隐私", quality: 0.95)
                default:
                    throw Convert.err("op 需要是 resize / compress / rotate / flip / crop / strip")
                }
                return (dst, before + " → " + ToolFS.size(dst))
            }.value
            attach([r.0], trace)
            trace.end(sid, detail: r.1)
            return ToolResult(text: "已处理（\(r.1)），已附在回复下方。")
        } catch {
            return fail(trace, sid, error, "图片处理")
        }
    }

    // MARK: 音视频剪辑
    private static func mediaEdit(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let op = MediaOps.Op.parse(str(a, "op")) else {
            return ToolResult(text: "op 需要是：trim / gif / speed / frame / merge", ok: false)
        }
        let t = targets(a)
        guard !t.urls.isEmpty else { return noFile }
        let urls = t.urls
        let start = num(a, "start") ?? 0
        let len = num(a, "length") ?? 4
        let factor = num(a, "speed") ?? 2
        let at = num(a, "at") ?? 0
        let sid = trace.begin(.file, "音视频 " + op.title, urls.map { $0.lastPathComponent }.joined(separator: "、"))
        do {
            let dur = await MediaOps.duration(urls[0])
            let end = num(a, "end") ?? dur
            let r = try await MediaOps.perform(op, files: urls, start: start, end: end, length: len, factor: factor, at: at, width: 480)
            attach([r], trace)
            trace.end(sid, detail: r.lastPathComponent)
            return ToolResult(text: "已完成（\(ToolFS.size(r))），已附在回复下方。")
        } catch {
            return fail(trace, sid, error, "处理")
        }
    }

    // MARK: 转文字
    private static func transcribe(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = targets(a).urls.first else { return noFile }
        let sid = trace.begin(.file, "转文字", u.lastPathComponent)
        do {
            let r = try await Transcribe.run(u, locale: str(a, "language")) { _ in }
            let base = ToolFS.base(u)
            let tx = ToolFS.out(base + "-文字", "txt")
            try r.text.write(to: tx, atomically: true, encoding: .utf8)
            let sr = ToolFS.out(base, "srt")
            try r.srt.write(to: sr, atomically: true, encoding: .utf8)
            attach([tx, sr], trace)
            trace.end(sid, detail: L10n.f("{} 字", "\(r.text.count)"))
            let body = r.text.count > 9000 ? String(r.text.prefix(9000)) + "\n…（已截断，完整内容在 txt 文件里）" : r.text
            return ToolResult(text: "转写完成，txt 和 SRT 字幕已附在回复下方。内容：\n" + body)
        } catch {
            return fail(trace, sid, error, "转文字")
        }
    }

    // MARK: zip
    private static func zip(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        let t = targets(a)
        guard !t.urls.isEmpty else { return noFile }
        let sid = trace.begin(.file, "打包 zip", L10n.f("{} 个文件", "\(t.urls.count)"))
        var entries: [(String, Data)] = []
        var total = 0
        var used = Set<String>()
        for u in t.urls {
            guard let d = try? Data(contentsOf: u, options: .mappedIfSafe) else { continue }
            total += d.count
            if total > 150_000_000 { break }
            var name = u.lastPathComponent
            var n = 2
            while !used.insert(name).inserted {
                name = u.deletingPathExtension().lastPathComponent + "-\(n)." + u.pathExtension
                n += 1
            }
            entries.append((name, d))
        }
        guard !entries.isEmpty else {
            trace.end(sid, ok: false, detail: L10n.tr("没有可打包的文件"))
            return ToolResult(text: "没有可打包的文件。", ok: false)
        }
        let base = str(a, "out").isEmpty ? (entries.count == 1 ? ToolFS.base(t.urls[0]) : "打包-\(entries.count)个文件") : str(a, "out").replacingOccurrences(of: ".zip", with: "")
        let dst = ToolFS.out(base, "zip")
        do {
            try Zip.write(entries).write(to: dst)
        } catch {
            return fail(trace, sid, error, "打包")
        }
        attach([dst], trace)
        trace.end(sid, detail: dst.lastPathComponent)
        return ToolResult(text: "已打包 \(entries.count) 个文件（\(ToolFS.size(dst))），附在回复下方。说明：未做压缩，只是合成一个文件。")
    }

    private static func unzip(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        guard let u = targets(a).urls.first else { return noFile }
        guard let arc = Zip.Archive(url: u) else { return ToolResult(text: "不是有效的 zip 文件，或者文件有密码（暂不支持加密压缩包）。", ok: false) }
        let sid = trace.begin(.file, "解压", u.lastPathComponent)
        let root = Store.dir("Outputs").appendingPathComponent(ToolFS.base(u), isDirectory: true)
        let fm = FileManager.default
        var written: [URL] = []
        var skipped = 0
        for e in arc.list {
            if e.name.hasSuffix("/") || e.name.hasPrefix("__MACOSX") || e.name.contains("/.") { continue }
            let comps = e.name.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }
            // 不允许 .. 和绝对路径，防止写到目录外
            guard !comps.isEmpty, !comps.contains(".."), e.usize < 100_000_000, let data = arc.read(e.name) else { skipped += 1; continue }
            var dst = root
            for (i, c) in comps.enumerated() { dst = dst.appendingPathComponent(c, isDirectory: i < comps.count - 1) }
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: dst)
                written.append(dst)
            } catch {
                skipped += 1
            }
        }
        guard !written.isEmpty else {
            trace.end(sid, ok: false, detail: L10n.tr("没有解出文件"))
            return ToolResult(text: "没有解出文件（可能有密码或使用了不支持的压缩方式）。", ok: false)
        }
        attach(Array(written.prefix(8)), trace)
        trace.end(sid, detail: L10n.f("{} 个文件", "\(written.count)"))
        let names = written.prefix(30).map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }.joined(separator: "\n")
        return ToolResult(text: "已解压 \(written.count) 个文件到「输出/\(ToolFS.base(u))」" + (skipped > 0 ? "，\(skipped) 个跳过" : "") + "：\n" + names + (written.count > 8 ? "\n前 8 个已附在回复下方。" : "\n已附在回复下方。"))
    }
}
