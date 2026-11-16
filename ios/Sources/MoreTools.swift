import Foundation
import UIKit
import EventKit
import Vision
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: 更多动手工具：朗读、二维码、识别图片文字、找空闲时间、搜工作区文件
@MainActor
enum MoreTools {
    static func doc() -> String {
        var s = ""
        s += "- speak {\"text\":\"要朗读的内容\",\"lang\":\"可选，如 zh-CN en-US ja-JP\"}：用语音把内容读出来（用户说「读给我听」「念一下」时用；{\"stop\":true} 停止）\n"
        s += "- qr_code {\"text\":\"链接或文字\",\"name\":\"可选文件名\"}：生成二维码图片，附在回复下方（Wi‑Fi 分享、网址、名片、取件码都能用；Wi‑Fi 写成 WIFI:T:WPA;S:名称;P:密码;;）\n"
        s += "- ocr {}：识别剪贴板里的图片文字（用户说「识别我刚截的图」时用）；{\"name\":\"工作区图片文件名\"}：识别工作区里的图片\n"
        s += "- calendar_free {\"days\":3,\"minutes\":60,\"from\":\"09:00\",\"to\":\"18:00\"}：在用户日历里找连续空闲的时间段（约时间、排日程时用，比 agenda 自己推算准）\n"
        s += "- photos_find {\"keywords\":[\"cat\",\"beach\"],\"days\":30,\"limit\":6}：按画面内容在相册里找照片（本机识别，不上传）。keywords 用英文的常见物体或场景词，如 cat dog food beach mountain sunset flower car document baby；留空 = 取最近的照片。找到的缩略图附在回复下方\n"
        s += "- search_files {\"q\":\"关键词\"}：在工作区的文件名和文件内容里搜索\n"
        return s
    }

    static func run(_ c: ToolCall, trace: Tracer, cloud: Bool) async -> ToolResult? {
        let a = c.args
        switch c.name {
        case "speak": return speak(a, trace)
        case "qr_code": return qr(a, trace)
        case "ocr": return await ocr(a, trace)
        case "calendar_free": return await calendarFree(a, trace)
        case "search_files": return searchFiles(str(a, "q"), trace)
        case "photos_find": return await photosFind(a, trace)
        default: return await Hands2.run(c, trace: trace, cloud: cloud)
        }
    }

    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func int(_ a: [String: Any], _ k: String, _ d: Int, _ lo: Int, _ hi: Int) -> Int {
        let v = (a[k] as? NSNumber)?.intValue ?? Int(str(a, k)) ?? d
        return min(max(v, lo), hi)
    }

    // MARK: 朗读
    private static func speak(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        if (a["stop"] as? Bool) == true {
            Speaker.shared.stop()
            return ToolResult(text: "已停止朗读。")
        }
        let t = str(a, "text")
        guard !t.isEmpty else { return ToolResult(text: "没有要朗读的内容。", ok: false) }
        trace.note(.phone, "朗读", String(t.prefix(24)))
        Speaker.shared.say(String(t.prefix(4000)), lang: str(a, "lang"))
        return ToolResult(text: "已开始朗读（\(min(t.count, 4000)) 字）。用户可以点回答下方的朗读按钮或让你停止。")
    }

    // MARK: 二维码
    private static func qr(_ a: [String: Any], _ trace: Tracer) -> ToolResult {
        let t = str(a, "text")
        guard !t.isEmpty, t.utf8.count <= 1500 else { return ToolResult(text: t.isEmpty ? "没有要编码的内容。" : "内容太长，二维码最多约 1500 字节。", ok: false) }
        let sid = trace.begin(.file, "生成二维码", String(t.prefix(30)))
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(t.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { trace.end(sid, ok: false); return ToolResult(text: "二维码生成失败。", ok: false) }
        let px = 1024.0
        let scaled = out.transformed(by: CGAffineTransform(scaleX: px / out.extent.width, y: px / out.extent.height))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { trace.end(sid, ok: false); return ToolResult(text: "二维码生成失败。", ok: false) }
        // 四周留白，白底黑码，扫码更稳
        let pad = 80.0
        let size = CGSize(width: px + pad * 2, height: px + pad * 2)
        let img = UIGraphicsImageRenderer(size: size).image { g in
            UIColor.white.setFill()
            g.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cg).draw(in: CGRect(x: pad, y: pad, width: px, height: px))
        }
        guard let png = img.pngData() else { trace.end(sid, ok: false); return ToolResult(text: "二维码生成失败。", ok: false) }
        let url = Hands.uniqueURL(Hands.safeName(str(a, "name").isEmpty ? "二维码.png" : str(a, "name"), defaultExt: "png"))
        do { try png.write(to: url) } catch {
            trace.end(sid, ok: false)
            return ToolResult(text: "保存二维码失败：" + error.localizedDescription, ok: false)
        }
        Agent.shared.mutate(trace.mid) { $0.files.append(url) }
        trace.end(sid, detail: url.lastPathComponent)
        return ToolResult(text: "已生成二维码图片「\(url.lastPathComponent)」，附在回复下方，用户可预览、分享或存到相册。一句话说明扫码后是什么即可。")
    }

    // MARK: 识别图片文字（本机 Vision，不上传）
    private static func ocr(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let name = str(a, "name")
        var image: UIImage?
        var src = L10n.tr("剪贴板")
        if name.isEmpty {
            image = UIPasteboard.general.hasImages ? UIPasteboard.general.image : nil
        } else if let u = Hands.workspaceURL(name), let d = try? Data(contentsOf: u) {
            image = UIImage(data: d)
            src = u.lastPathComponent
        }
        guard let cg = image?.cgImage else {
            return ToolResult(text: name.isEmpty ? "剪贴板里没有图片。请让用户先复制一张图片或截图，或用 name 指定工作区里的图片。" : "工作区里没有这张图片，或者它不是图片。", ok: false)
        }
        let sid = trace.begin(.read, "识别图片文字", src)
        let text: String = await Task.detached(priority: .userInitiated) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            let h = VNImageRequestHandler(cgImage: cg, orientation: .up)
            try? h.perform([req])
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
        trace.end(sid, ok: !text.isEmpty, detail: text.isEmpty ? nil : L10n.f("{} 字", "\(text.count)"))
        if text.isEmpty { return ToolResult(text: "图片里没有识别出文字。", ok: false) }
        return ToolResult(text: "图片中的文字：\n" + String(text.prefix(8000)))
    }

    // MARK: 找空闲时间
    private static func hm(_ s: String, _ dh: Int, _ dm: Int) -> (Int, Int) {
        let p = s.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count >= 1, (0...23).contains(p[0]) else { return (dh, dm) }
        return (p[0], p.count > 1 && (0...59).contains(p[1]) ? p[1] : 0)
    }

    private static func calendarFree(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let days = int(a, "days", 3, 1, 14)
        let need = int(a, "minutes", 60, 15, 480)
        let (fh, fm) = hm(str(a, "from"), 9, 0)
        let (th, tm) = hm(str(a, "to"), 18, 0)
        let sid = trace.begin(.time, "查找空闲时间", L10n.f("未来 {} 天 · 至少 {} 分钟", "\(days)", "\(need)"))
        let store = EKEventStore()
        guard let ok = try? await store.requestFullAccessToEvents(), ok else {
            trace.end(sid, ok: false, detail: L10n.tr("没有日历权限"))
            return ToolResult(text: "没有日历权限（用户可以在系统设置里允许）。", ok: false)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
        let evs = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).filter { !$0.isAllDay && $0.availability != .free }
        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: L10n.info.locale)
        dayF.dateFormat = "M/d EEE"
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        var out = "按 \(String(format: "%02d:%02d", fh, fm))–\(String(format: "%02d:%02d", th, tm)) 的时段，连续空闲至少 \(need) 分钟：\n"
        var total = 0
        for d in 0..<days {
            guard let day = cal.date(byAdding: .day, value: d, to: start),
                  var cur = cal.date(bySettingHour: fh, minute: fm, second: 0, of: day),
                  let stop = cal.date(bySettingHour: th, minute: tm, second: 0, of: day) else { continue }
            if d == 0 {
                // 今天从下一个整 15 分钟开始算
                let now = Date()
                let c = cal.dateComponents([.hour, .minute], from: now)
                let m = ((c.minute ?? 0) / 15 + 1) * 15
                if let r = cal.date(bySettingHour: c.hour ?? 0, minute: 0, second: 0, of: now)?.addingTimeInterval(Double(m) * 60), r > cur { cur = r }
            }
            let busy = evs.filter { $0.endDate > cur && $0.startDate < stop }.sorted { $0.startDate < $1.startDate }
            var slots: [String] = []
            func add(_ x: Date, _ y: Date) {
                if y.timeIntervalSince(x) >= Double(need) * 60 { slots.append(timeF.string(from: x) + "–" + timeF.string(from: y)) }
            }
            for e in busy {
                add(cur, e.startDate)
                cur = max(cur, e.endDate)
            }
            add(cur, stop)
            total += slots.count
            out += "- " + dayF.string(from: day) + "：" + (slots.isEmpty ? "没有合适的空档" : slots.joined(separator: "、")) + "\n"
        }
        trace.end(sid, detail: L10n.f("{} 个空档", "\(total)"))
        return ToolResult(text: out)
    }

    // MARK: 相册找图（Vision 本机分类，只看缩略图）
    private nonisolated static func scan(_ assets: [PHAsset], _ kws: [String], _ limit: Int) -> [PHAsset] {
        if kws.isEmpty { return Array(assets.prefix(limit)) }
        let mgr = PHImageManager.default()
        let opt = PHImageRequestOptions()
        opt.isSynchronous = true
        opt.deliveryMode = .fastFormat
        opt.resizeMode = .fast
        opt.isNetworkAccessAllowed = false
        var out: [PHAsset] = []
        let deadline = Date().addingTimeInterval(25)
        for a in assets {
            if out.count >= limit || Date() > deadline { break }
            var cg: CGImage?
            mgr.requestImage(for: a, targetSize: CGSize(width: 299, height: 299), contentMode: .aspectFit, options: opt) { img, _ in cg = img?.cgImage }
            guard let cg else { continue }
            let req = VNClassifyImageRequest()
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            let hit = (req.results ?? []).contains { o in o.confidence >= 0.3 && kws.contains { o.identifier.lowercased().contains($0) } }
            if hit { out.append(a) }
        }
        return out
    }

    private nonisolated static func export(_ assets: [PHAsset]) -> [(Data, Date?)] {
        let mgr = PHImageManager.default()
        let opt = PHImageRequestOptions()
        opt.isSynchronous = true
        opt.deliveryMode = .highQualityFormat
        opt.isNetworkAccessAllowed = false
        var out: [(Data, Date?)] = []
        for a in assets {
            mgr.requestImage(for: a, targetSize: CGSize(width: 1280, height: 1280), contentMode: .aspectFit, options: opt) { img, _ in
                if let d = img?.jpegData(compressionQuality: 0.85) { out.append((d, a.creationDate)) }
            }
        }
        return out
    }

    private static func photosFind(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        var st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .notDetermined { st = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard st == .authorized || st == .limited else { return ToolResult(text: "没有相册权限（用户可以在 设置 → OSVIA 里允许）。", ok: false) }
        var kws: [String] = (a["keywords"] as? [String]) ?? []
        if kws.isEmpty { kws = str(a, "keywords").split(whereSeparator: { ",，、 ".contains($0) }).map(String.init) }
        kws = kws.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let days = int(a, "days", 30, 1, 3650)
        let limit = int(a, "limit", 6, 1, 12)
        let sid = trace.begin(.read, "查找照片", kws.isEmpty ? L10n.f("最近 {} 天", "\(days)") : kws.joined(separator: " "))
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@", PHAssetMediaType.image.rawValue, Date().addingTimeInterval(-Double(days) * 86400) as NSDate)
        o.fetchLimit = 400
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: o).enumerateObjects { x, _, _ in assets.append(x) }
        guard !assets.isEmpty else {
            trace.end(sid, ok: false, detail: L10n.tr("没有照片"))
            return ToolResult(text: "最近 \(days) 天的相册里没有照片（或只授权了部分照片）。", ok: false)
        }
        let total = assets.count
        let list = assets
        let words = kws
        let shots: [(Data, Date?)] = await Task.detached(priority: .userInitiated) {
            export(scan(list, words, limit))
        }.value
        if shots.isEmpty {
            trace.end(sid, ok: false, detail: L10n.tr("没有找到"))
            return ToolResult(text: "在最近 \(days) 天的 \(total) 张照片里没有找到「\(kws.joined(separator: "、"))」。可以换个英文关键词，或把 days 调大再试。")
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let show = DateFormatter()
        show.dateFormat = "M月d日 HH:mm"
        var names: [String] = []
        for (d, date) in shots {
            let n = "照片-" + (date.map { f.string(from: $0) } ?? "\(names.count + 1)") + ".jpg"
            let url = Hands.uniqueURL(Hands.safeName(n, defaultExt: "jpg"))
            if (try? d.write(to: url)) != nil {
                Agent.shared.mutate(trace.mid) { $0.files.append(url) }
                names.append(date.map { show.string(from: $0) } ?? url.lastPathComponent)
            }
        }
        trace.end(sid, detail: L10n.f("{} 张", "\(names.count)"))
        return ToolResult(text: "找到 \(names.count) 张（扫描了最近 \(days) 天的 \(total) 张照片）：" + names.joined(separator: "、") + "。已附在回复下方，缩略图可预览、分享。")
    }

    // MARK: 搜工作区文件
    private static func searchFiles(_ q: String, _ trace: Tracer) -> ToolResult {
        guard !q.isEmpty else { return ToolResult(text: "缺少关键词。", ok: false) }
        let sid = trace.begin(.file, "搜索文件", q)
        let files = ((try? FileManager.default.contentsOfDirectory(at: Hands.work, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .prefix(300)
        var hits: [String] = []
        for u in files {
            let n = u.lastPathComponent
            if n.localizedCaseInsensitiveContains(q) { hits.append("- 文件名匹配：\(n)") }
            let ext = u.pathExtension.lowercased()
            guard ["md", "txt", "csv", "json", "html", "ics", "js", "py", "swift", "xml", "yaml", "yml", "log"].contains(ext),
                  let d = try? Data(contentsOf: u), d.count < 400_000 else { continue }
            let lines = String(decoding: d, as: UTF8.self).components(separatedBy: "\n")
            var shown = 0
            for (i, l) in lines.enumerated() where l.localizedCaseInsensitiveContains(q) {
                hits.append("- \(n):\(i + 1)：" + String(l.trimmingCharacters(in: .whitespaces).prefix(120)))
                shown += 1
                if shown >= 3 { break }
            }
            if hits.count >= 25 { break }
        }
        trace.end(sid, detail: L10n.f("{} 处", "\(hits.count)"))
        return ToolResult(text: hits.isEmpty ? "工作区的文件里没有找到「\(q)」。" : hits.joined(separator: "\n"))
    }
}
