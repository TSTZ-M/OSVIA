import Foundation
import UIKit
import PDFKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// 文件格式互转：图片 / PDF / Word / Excel / 文本 / 表格 / 网页 / 视频 / 音频
enum Convert {
    static let imgExt = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
    static let vidExt = ["mp4", "mov", "m4v"]
    static let audExt = ["m4a", "mp3", "wav", "caf", "aac", "aiff", "aif", "flac"]
    static var docExt: Set<String> { KB.textExt.union(Office.exts) }

    static func err(_ s: String) -> NSError { NSError(domain: "转换", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }

    static func out(_ base: String, _ ext: String) -> URL {
        Store.dir("Outputs").appendingPathComponent(base + "-" + String(Int(Date().timeIntervalSince1970) % 100000) + "." + ext)
    }

    static func normalize(_ s: String) -> String {
        let t = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let m = ["jpeg": "jpg", "压缩": "compress", "音频": "m4a", "提取音频": "m4a", "mp3": "m4a", "文本": "txt", "文字": "txt", "表格": "csv",
                 "markdown": "md", "网页": "html", "图片": "png", "视频": "mp4", "heif": "heic", "tif": "tiff",
                 "word": "docx", "doc": "docx", "excel": "xlsx", "xls": "xlsx", "静音": "mute", "去声音": "mute", "去除声音": "mute",
                 "去音频": "mute", "无声": "mute", "wave": "wav", "aif": "aiff"]
        return m[t] ?? t
    }

    // 某种格式的文件能转成什么（转换页与聊天快捷操作共用）
    static func targets(for e: String) -> [String] {
        let list: [String]
        if imgExt.contains(e) { list = ["jpg", "png", "heic", "pdf", "txt", "docx", "compress", "tiff", "gif", "bmp"] }
        else if vidExt.contains(e) { list = ["mp4", "mov", "m4a", "wav", "mute", "compress", "jpg"] }
        else if audExt.contains(e) { list = ["m4a", "wav", "caf"] }
        else {
            switch e {
            case "pdf": list = ["docx", "txt", "md", "rtf", "html", "png", "jpg"]
            case "docx", "rtf", "odt": list = ["pdf", "docx", "txt", "md", "html", "rtf"]
            case "pptx", "odp": list = ["txt", "md", "docx"]
            case "xlsx": list = ["csv", "json", "md", "html", "tsv", "txt", "pdf"]
            case "ods": list = ["txt", "md"]
            case "csv", "tsv", "json": list = ["xlsx", "csv", "json", "md", "html", "tsv", "txt", "pdf", "docx"]
            case "md": list = ["docx", "pdf", "html", "txt", "rtf", "xlsx"]
            case "html", "htm": list = ["pdf", "md", "txt", "docx"]
            default: list = ["docx", "pdf", "md", "html", "rtf", "xlsx"]
            }
        }
        return list.filter { $0 != e && !(e == "jpeg" && $0 == "jpg") }
    }

    static func run(_ src: URL, to target: String) async throws -> [URL] {
        let ext = src.pathExtension.lowercased()
        let t = normalize(target)
        let base = src.deletingPathExtension().lastPathComponent
        if imgExt.contains(ext) { return try await Task.detached(priority: .userInitiated) { try Convert.image(src, base, t) }.value }
        if ext == "pdf" { return try await pdf(src, base, t) }
        if vidExt.contains(ext) { return [try await video(src, base, t)] }
        if audExt.contains(ext) { return [try await audio(src, base, t)] }
        if docExt.contains(ext) { return [try await doc(src, base, ext, t)] }
        throw err("暂不支持 .\(ext) 转 .\(t)")
    }

    // MARK: 图片
    static func image(_ src: URL, _ base: String, _ t: String) throws -> [URL] {
        if t == "compress" {
            guard let cg = OCR.cg(src, maxPixel: 2048), let d = UIImage(cgImage: cg).jpegData(compressionQuality: 0.6) else { throw err("无法读取图片") }
            let dst = out(base + "-压缩", "jpg")
            try d.write(to: dst)
            return [dst]
        }
        guard let img = UIImage(contentsOfFile: src.path) else { throw err("无法读取图片") }
        let dst = out(base, t)
        switch t {
        case "pdf":
            let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: img.size))
            try r.writePDF(to: dst) { c in
                c.beginPage()
                img.draw(at: .zero)
            }
        case "jpg":
            guard let d = img.jpegData(compressionQuality: 0.9) else { throw err("编码失败") }
            try d.write(to: dst)
        case "png":
            guard let d = img.pngData() else { throw err("编码失败") }
            try d.write(to: dst)
        case "heic", "tiff", "gif", "bmp":
            let types: [String: UTType] = ["heic": .heic, "tiff": .tiff, "gif": .gif, "bmp": .bmp]
            guard let ty = types[t], let cg = upright(img),
                  let dest = CGImageDestinationCreateWithURL(dst as CFURL, ty.identifier as CFString, 1, nil) else { throw err("不支持写入 \(t)") }
            CGImageDestinationAddImage(dest, cg, nil)
            guard CGImageDestinationFinalize(dest) else { throw err("编码失败") }
        case "txt":
            let text = OCR.fullText(src)
            if text.isEmpty { throw err("没有识别到文字") }
            try text.write(to: dst, atomically: true, encoding: .utf8)
        case "docx":
            let text = OCR.fullText(src)
            if text.isEmpty { throw err("没有识别到文字") }
            try Office.docx(text).write(to: dst)
        default:
            throw err("图片不能转成 \(t)")
        }
        return [dst]
    }

    // img.cgImage 不带方向信息：竖拍照片直接写出会躺倒，这里先按方向重绘一遍
    private static func upright(_ img: UIImage) -> CGImage? {
        guard img.imageOrientation != .up else { return img.cgImage }
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = img.scale
        f.opaque = false
        return UIGraphicsImageRenderer(size: img.size, format: f).image { _ in img.draw(at: .zero) }.cgImage
    }

    // MARK: PDF（扫描件没有文字层时，逐页识别）
    static func pdf(_ src: URL, _ base: String, _ t: String) async throws -> [URL] {
        guard let doc = PDFDocument(url: src) else { throw err("无法打开 PDF") }
        if ["txt", "md", "docx", "rtf", "html"].contains(t) {
            let text = await pdfText(doc)
            guard !text.isEmpty else { throw err("没有读到文字") }
            let dst = out(base, t)
            switch t {
            case "docx": try Office.docx(text).write(to: dst)
            case "rtf":
                guard let d = Office.rtfData(text) else { throw err("编码失败") }
                try d.write(to: dst)
            case "html": try MDHTML.pre(text).write(to: dst, atomically: true, encoding: .utf8)
            default: try text.write(to: dst, atomically: true, encoding: .utf8)
            }
            return [dst]
        }
        guard t == "png" || t == "jpg" else { throw err("PDF 可转成 docx、txt、md、rtf、html、png、jpg") }
        var outs: [URL] = []
        for i in 0..<min(doc.pageCount, 40) {
            guard let p = doc.page(at: i) else { continue }
            let sz = p.bounds(for: .mediaBox).size
            // 常规页面放大 2 倍；海报级大页面把长边限制在 4000 像素以内，避免内存暴涨
            let k = min(2, 4000 / max(sz.width, sz.height, 1))
            let d = out("\(base)-p\(i + 1)", t)
            try autoreleasepool {
                let img = p.thumbnail(of: CGSize(width: sz.width * k, height: sz.height * k), for: .mediaBox)
                let data = t == "png" ? img.pngData() : img.jpegData(compressionQuality: 0.9)
                try data?.write(to: d)
            }
            outs.append(d)
        }
        if outs.isEmpty { throw err("没有读到页面") }
        return outs
    }

    static func pdfText(_ doc: PDFDocument) async -> String {
        let direct = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if direct.count >= 30 { return direct }
        var parts: [String] = []
        for i in 0..<min(doc.pageCount, 30) {
            guard let p = doc.page(at: i) else { continue }
            let sz = p.bounds(for: .mediaBox).size
            let k = 2000 / max(sz.width, sz.height, 1)
            let cg: CGImage? = autoreleasepool {
                p.thumbnail(of: CGSize(width: sz.width * k, height: sz.height * k), for: .mediaBox).cgImage
            }
            guard let cg else { continue }
            let s = await Task.detached(priority: .userInitiated) { OCR.text(cg) }.value
            if !s.isEmpty { parts.append(s) }
        }
        let ocr = parts.joined(separator: "\n\n")
        return ocr.isEmpty ? direct : ocr
    }

    // MARK: 视频
    static func video(_ src: URL, _ base: String, _ t: String) async throws -> URL {
        let asset = AVURLAsset(url: src)
        if t == "jpg" || t == "png" {
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            let (cg, _) = try await g.image(at: .zero)
            let img = UIImage(cgImage: cg)
            let d = out(base, t)
            try (t == "png" ? img.pngData() : img.jpegData(compressionQuality: 0.9))?.write(to: d)
            return d
        }
        if t == "wav" || t == "caf" || t == "aiff" { return try await audioPCM(src, base, t) }
        if t == "mute" { return try await mute(asset, base, src.pathExtension) }
        let preset: String
        let type: AVFileType
        let ext: String
        switch t {
        case "m4a": preset = AVAssetExportPresetAppleM4A; type = .m4a; ext = "m4a"
        case "mov": preset = AVAssetExportPresetHighestQuality; type = .mov; ext = "mov"
        case "compress": preset = AVAssetExportPreset1280x720; type = .mp4; ext = "mp4"
        case "mp4": preset = AVAssetExportPresetHighestQuality; type = .mp4; ext = "mp4"
        default: throw err("视频可转成 mp4、mov、m4a、wav、jpg，或「去除声音」「压缩」")
        }
        if t == "m4a", (try await asset.loadTracks(withMediaType: .audio)).isEmpty { throw err("这个视频没有声音") }
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw err("无法创建导出任务") }
        let dst = out(base, ext)
        try await s.export(to: dst, as: type)
        return dst
    }

    // 去掉视频里的声音：只保留画面轨道，直接封装，不重新编码，画质无损
    static func mute(_ asset: AVURLAsset, _ base: String, _ srcExt: String) async throws -> URL {
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else { throw err("没有找到视频画面") }
        let dur = try await asset.load(.duration)
        let comp = AVMutableComposition()
        guard let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw err("无法创建视频轨道") }
        try ct.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: .zero)
        ct.preferredTransform = try await vt.load(.preferredTransform)
        guard let s = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw err("无法创建导出任务") }
        let mov = srcExt.lowercased() == "mov"
        let dst = out(base + "-无声", mov ? "mov" : "mp4")
        try await s.export(to: dst, as: mov ? .mov : .mp4)
        return dst
    }

    // MARK: 音频
    static func audio(_ src: URL, _ base: String, _ t: String) async throws -> URL {
        switch t {
        case "m4a":
            guard let s = AVAssetExportSession(asset: AVURLAsset(url: src), presetName: AVAssetExportPresetAppleM4A) else { throw err("无法创建导出任务") }
            let dst = out(base, "m4a")
            try await s.export(to: dst, as: .m4a)
            return dst
        case "wav", "caf", "aiff":
            return try await audioPCM(src, base, t)
        default:
            throw err("音频可转成 m4a、wav、caf（系统不支持编码 MP3）")
        }
    }

    // 解码成 16 位 PCM 再写成 wav / caf / aiff；视频和各种音频都能作为来源
    static func audioPCM(_ src: URL, _ base: String, _ t: String) async throws -> URL {
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw err("没有找到声音（视频可能本来就是无声的）") }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: t == "aiff",
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { throw err("无法读取声音") }
        reader.add(output)
        let type: AVFileType = t == "caf" ? .caf : (t == "aiff" ? .aiff : .wav)
        let dst = out(base, t)
        try? FileManager.default.removeItem(at: dst)
        let writer = try AVAssetWriter(outputURL: dst, fileType: type)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw err("无法写入 \(t)") }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw err("无法开始转换：" + (writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "")) }
        writer.startSession(atSourceTime: .zero)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "osvia.pcm")) {
                while input.isReadyForMoreMediaData {
                    if let b = output.copyNextSampleBuffer(), input.append(b) { continue }
                    input.markAsFinished()
                    c.resume()
                    return
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw err("转换失败：" + (writer.error?.localizedDescription ?? "未知错误")) }
        return dst
    }

    // MARK: 文本、文档与表格
    static func doc(_ src: URL, _ base: String, _ ext: String, _ t: String) async throws -> URL {
        var rows: [[String]]?
        var raw = ""
        if ext == "xlsx" {
            let sh = Office.sheets(of: src)
            guard let first = sh.first else { throw err("没有读到表格内容") }
            rows = first.rows
            raw = csvOut(first.rows, "\t")
        } else {
            raw = KB.shared.text(of: src)
            guard !raw.isEmpty else { throw err("文件为空或无法读取") }
            switch ext {
            case "csv": rows = csvParse(raw, ",")
            case "tsv": rows = csvParse(raw, "\t")
            case "json": rows = jsonRows(raw)
            case "md": rows = raw.contains("|") ? mdRows(raw) : nil
            default: break
            }
        }
        if rows?.isEmpty == true { rows = nil }
        let isHTML = ext == "html" || ext == "htm"
        let plain = isHTML ? (Web.clean((try? String(contentsOf: src, encoding: .utf8)) ?? raw, limit: 5_000_000).text) : raw

        // 目标是表格，但来源是文本：一行一行变成一行表格
        func asRows() -> [[String]] {
            if let r = rows { return r }
            let lines = plain.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return lines.map { $0.contains("\t") ? $0.components(separatedBy: "\t") : [$0] }
        }
        func tableHTML(_ r: [[String]]) -> String {
            func e(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
            return MDHTML.page("<table>" + r.map { row in "<tr>" + row.map { "<td>\(e($0))</td>" }.joined() + "</tr>" }.joined() + "</table>")
        }

        let dst = out(base, t)
        switch t {
        case "csv": try csvOut(asRows(), ",").write(to: dst, atomically: true, encoding: .utf8)
        case "tsv": try csvOut(asRows(), "\t").write(to: dst, atomically: true, encoding: .utf8)
        case "json": try jsonOut(asRows()).write(to: dst, atomically: true, encoding: .utf8)
        case "xlsx": try Office.xlsx(asRows()).write(to: dst)
        case "md": try (rows.map { mdOut($0) } ?? plain).write(to: dst, atomically: true, encoding: .utf8)
        case "txt": try (rows.map { csvOut($0, "\t") } ?? plain).write(to: dst, atomically: true, encoding: .utf8)
        case "html":
            let h: String
            if let r = rows { h = tableHTML(r) } else if ext == "md" { h = MDHTML.html(raw) } else if isHTML { h = raw } else { h = MDHTML.pre(raw) }
            try h.write(to: dst, atomically: true, encoding: .utf8)
        case "docx":
            let text = rows.map { csvOut($0, "\t") } ?? plain
            try Office.docx(text).write(to: dst)
        case "rtf":
            guard let d = Office.rtfData(rows.map { csvOut($0, "\t") } ?? plain) else { throw err("编码失败") }
            try d.write(to: dst)
        case "pdf":
            let html: String?
            if let r = rows { html = tableHTML(r) }
            else if ext == "md" { html = MDHTML.html(raw) }
            else if isHTML { html = (try? String(contentsOf: src, encoding: .utf8)) ?? raw }
            else { html = nil }
            if let html {
                try await MainActor.run { try htmlPDF(html, dst) }
            } else {
                let content = plain
                try await MainActor.run { try textPDF(content, dst) }
            }
        default:
            throw err("\(ext) 不能转成 \(t)，可以转成：" + targets(for: ext).joined(separator: "、"))
        }
        return dst
    }

    private static func renderPDF(_ fmt: UIPrintFormatter, _ dst: URL) throws {
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(fmt, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        r.setValue(page, forKey: "paperRect")
        r.setValue(page.insetBy(dx: 36, dy: 36), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<r.numberOfPages {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        try (data as Data).write(to: dst)
    }

    static func textPDF(_ text: String, _ dst: URL) throws {
        let fmt = UISimpleTextPrintFormatter(text: text)
        fmt.font = UIFont.systemFont(ofSize: 12)
        try renderPDF(fmt, dst)
    }

    static func htmlPDF(_ html: String, _ dst: URL) throws {
        try renderPDF(UIMarkupTextPrintFormatter(markupText: html), dst)
    }

    static func csvParse(_ s: String, _ delim: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cur = String.UnicodeScalarView()
        var q = false
        let dl = delim.unicodeScalars.first ?? ","
        let quote: Unicode.Scalar = "\""
        let cs = Array(s.unicodeScalars)
        func isNL(_ c: Unicode.Scalar) -> Bool { c == "\n" || c == "\r" || c == "\u{2028}" || c == "\u{2029}" || c == "\u{85}" }
        var i = cs.first == "\u{FEFF}" ? 1 : 0   // 跳过 BOM
        while i < cs.count {
            let c = cs[i]
            if q {
                if c == quote {
                    if i + 1 < cs.count && cs[i + 1] == quote { cur.append(quote); i += 1 } else { q = false }
                } else { cur.append(c) }
            } else if c == quote { q = true }
            else if c == dl { row.append(String(cur)); cur = String.UnicodeScalarView() }
            else if isNL(c) {
                // \r\n 算一个换行
                if c == "\r", i + 1 < cs.count, cs[i + 1] == "\n" { i += 1 }
                row.append(String(cur)); cur = String.UnicodeScalarView(); rows.append(row); row = []
            }
            else { cur.append(c) }
            i += 1
        }
        if !cur.isEmpty || !row.isEmpty { row.append(String(cur)); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func jsonRows(_ s: String) -> [[String]] {
        guard let d = s.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], !a.isEmpty else { return [] }
        let keys = Array(Set(a.flatMap { $0.keys })).sorted()
        return [keys] + a.map { o in keys.map { k in (o[k] == nil || o[k] is NSNull) ? "" : "\(o[k]!)" } }
    }

    static func mdRows(_ s: String) -> [[String]] {
        s.split(separator: "\n").map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
            .filter { !$0.replacingOccurrences(of: "[|:\\-\\s]", with: "", options: .regularExpression).isEmpty }
            .map { line in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                return Array(parts.dropFirst().dropLast())
            }
    }

    static func csvOut(_ rows: [[String]], _ d: String) -> String {
        rows.map { r in
            r.map { c in
                (c.contains(d) || c.contains("\"") || c.contains("\n")) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c
            }.joined(separator: d)
        }.joined(separator: "\n")
    }

    static func mdOut(_ rows: [[String]]) -> String {
        guard let h = rows.first else { return "" }
        var l = ["| " + h.joined(separator: " | ") + " |", "|" + h.map { _ in " --- |" }.joined()]
        for r in rows.dropFirst() { l.append("| " + r.joined(separator: " | ") + " |") }
        return l.joined(separator: "\n")
    }

    static func jsonOut(_ rows: [[String]]) -> String {
        guard let h = rows.first else { return "[]" }
        let arr: [[String: String]] = rows.dropFirst().map { r in
            var o: [String: String] = [:]
            for (i, k) in h.enumerated() { o[k] = i < r.count ? r[i] : "" }
            return o
        }
        let d = (try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }
}
