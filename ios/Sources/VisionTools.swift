import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

// MARK: 输出文件命名：放进「输出」目录，重名自动加序号
enum ToolFS {
    static func out(_ base: String, _ ext: String) -> URL {
        var b = base.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|\n")).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if b.isEmpty { b = "文件" }
        b = String(b.prefix(40))
        let dir = Store.dir("Outputs")
        var u = dir.appendingPathComponent(b + "." + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(b + "-\(n)." + ext)
            n += 1
        }
        return u
    }

    static func base(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent }

    static func jpeg(_ cg: CGImage, quality: CGFloat = 0.92) -> Data? {
        UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    static func size(_ u: URL) -> String {
        ByteCountFormatter.string(fromByteCount: Files.size(u) ?? 0, countStyle: .file)
    }
}

// MARK: 打码：自动找出图里的手机号、身份证号、银行卡、邮箱、网址、车牌和人脸，涂黑或打马赛克
enum Redact {
    enum Kind: String, CaseIterable, Identifiable {
        case phone, idcard, bank, email, url, plate, face, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .phone: return "手机号"
            case .idcard: return "身份证号"
            case .bank: return "银行卡号"
            case .email: return "邮箱"
            case .url: return "网址"
            case .plate: return "车牌"
            case .face: return "人脸"
            case .all: return "所有文字"
            }
        }

        var icon: String {
            switch self {
            case .phone: return "phone"
            case .idcard: return "person.text.rectangle"
            case .bank: return "creditcard"
            case .email: return "envelope"
            case .url: return "link"
            case .plate: return "car"
            case .face: return "face.smiling"
            case .all: return "text.alignleft"
            }
        }

        var pattern: String? {
            switch self {
            case .phone: return "(?<![0-9])(?:\\+?86[ -]?)?1[3-9][0-9][ -]?[0-9]{4}[ -]?[0-9]{4}(?![0-9])"
            case .idcard: return "(?<![0-9])[0-9]{17}[0-9Xx](?![0-9])"
            case .bank: return "(?<![0-9])(?:[0-9][ -]?){15,18}[0-9](?![0-9])"
            case .email: return "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
            case .url: return "(?:https?://|www\\.)[^\\s]+"
            case .plate: return "[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z][ ·]?[A-Z0-9]{5,6}"
            case .face, .all: return nil
            }
        }

        static func parse(_ s: String) -> Kind? {
            let t = s.lowercased()
            switch t {
            case "phone", "手机号", "手机", "电话": return .phone
            case "id", "idcard", "身份证", "身份证号": return .idcard
            case "card", "bank", "银行卡", "银行卡号": return .bank
            case "email", "邮箱": return .email
            case "url", "link", "网址", "链接": return .url
            case "plate", "车牌": return .plate
            case "face", "faces", "人脸", "脸": return .face
            case "all", "text", "所有文字", "全部文字": return .all
            default: return nil
            }
        }
    }

    enum Style: String { case mosaic, black }

    struct Hit {
        let kind: Kind
        let box: CGRect      // 归一化，原点在左下角（Vision 坐标）
        let preview: String  // 给界面看的遮挡后文字
    }

    // 部分遮住再展示，避免在界面里再次暴露隐私
    static func masked(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count <= 4 { return String(repeating: "•", count: t.count) }
        return String(t.prefix(2)) + String(repeating: "•", count: min(t.count - 4, 8)) + String(t.suffix(2))
    }

    static func analyze(_ cg: CGImage) -> [Hit] {
        var hits: [Hit] = []
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        let h = VNImageRequestHandler(cgImage: cg, orientation: .up)
        let faces = VNDetectFaceRectanglesRequest()
        try? h.perform([req, faces])

        for o in req.results ?? [] {
            guard let c = o.topCandidates(1).first else { continue }
            let text = c.string
            hits.append(Hit(kind: .all, box: o.boundingBox, preview: masked(text)))
            let ns = text as NSString
            for k in Kind.allCases {
                guard let p = k.pattern, let re = try? NSRegularExpression(pattern: p) else { continue }
                for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    guard let r = Range(m.range, in: text) else { continue }
                    let box = (try? c.boundingBox(for: r))?.boundingBox ?? o.boundingBox
                    hits.append(Hit(kind: k, box: box, preview: masked(String(text[r]))))
                }
            }
        }
        for f in faces.results ?? [] {
            let b = f.boundingBox
            hits.append(Hit(kind: .face, box: b.insetBy(dx: -b.width * 0.12, dy: -b.height * 0.12), preview: ""))
        }
        return hits
    }

    // 画出遮挡：返回无元数据的 JPEG（原图的拍摄位置等信息也一并去掉）
    static func apply(_ cg: CGImage, hits: [Hit], style: Style) -> Data? {
        let ci = CIImage(cgImage: cg)
        let w = ci.extent.width
        let h = ci.extent.height
        let ctx = CIContext()
        var out = ci
        for hit in hits {
            let r = CGRect(x: hit.box.minX * w, y: hit.box.minY * h, width: hit.box.width * w, height: hit.box.height * h)
                .insetBy(dx: -3, dy: -3)
                .intersection(ci.extent)
            guard !r.isNull, r.width > 1, r.height > 1 else { continue }
            let patch: CIImage
            if style == .black {
                patch = CIImage(color: CIColor.black).cropped(to: r)
            } else {
                let f = CIFilter.pixellate()
                f.inputImage = ci
                f.scale = Float(max(min(r.height, r.width) / 3, 10))
                f.center = CGPoint(x: r.midX, y: r.midY)
                guard let o = f.outputImage else { continue }
                patch = o.cropped(to: r)
            }
            out = patch.composited(over: out)
        }
        guard let res = ctx.createCGImage(out, from: ci.extent) else { return nil }
        return ToolFS.jpeg(res)
    }

    // 一步完成（给对话工具用）
    static func run(_ url: URL, kinds: Set<Kind>, style: Style) throws -> (URL, Int) {
        guard let cg = OCR.cg(url, maxPixel: 4096) else { throw Convert.err("图片读取失败") }
        let all = analyze(cg)
        let chosen = all.filter { kinds.contains($0.kind) }
        guard !chosen.isEmpty else { throw Convert.err("没有找到需要遮挡的内容") }
        guard let d = apply(cg, hits: chosen, style: style) else { throw Convert.err("生成图片失败") }
        let dst = ToolFS.out("打码-" + ToolFS.base(url), "jpg")
        try d.write(to: dst)
        return (dst, chosen.count)
    }
}

// MARK: 抠图 / 换底色：用系统的主体识别，证件照蓝底红底白底一步到位
enum Cutout {
    enum Background: String, CaseIterable, Identifiable {
        case clear, white, blue, red, gray
        var id: String { rawValue }

        var title: String {
            switch self {
            case .clear: return "透明"
            case .white: return "白底"
            case .blue: return "蓝底"
            case .red: return "红底"
            case .gray: return "灰底"
            }
        }

        var color: CIColor? {
            switch self {
            case .clear: return nil
            case .white: return CIColor(red: 1, green: 1, blue: 1)
            case .blue: return CIColor(red: 0.26, green: 0.56, blue: 0.84)    // 证件照常用蓝 #438EDB
            case .red: return CIColor(red: 0.86, green: 0.15, blue: 0.15)
            case .gray: return CIColor(red: 0.93, green: 0.93, blue: 0.93)
            }
        }

        static func parse(_ s: String) -> Background {
            switch s.lowercased() {
            case "white", "白", "白底": return .white
            case "blue", "蓝", "蓝底": return .blue
            case "red", "红", "红底": return .red
            case "gray", "grey", "灰", "灰底": return .gray
            default: return .clear
            }
        }
    }

    static func run(_ url: URL, bg: Background, crop: Bool) throws -> URL {
        guard let cg = OCR.cg(url, maxPixel: 3072) else { throw Convert.err("图片读取失败") }
        let req = VNGenerateForegroundInstanceMaskRequest()
        let h = VNImageRequestHandler(cgImage: cg, options: [:])
        try h.perform([req])
        guard let obs = req.results?.first, !obs.allInstances.isEmpty else { throw Convert.err("没有识别到清晰的主体（人物、物品、宠物都可以），换一张主体更突出的图试试") }
        let pb = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: h, croppedToInstancesExtent: crop)
        var ci = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext()
        let base = "抠图-" + ToolFS.base(url)
        if let c = bg.color {
            let solid = CIImage(color: c).cropped(to: ci.extent)
            ci = ci.composited(over: solid)
            guard let out = ctx.createCGImage(ci, from: ci.extent), let d = ToolFS.jpeg(out, quality: 0.95) else { throw Convert.err("生成图片失败") }
            let dst = ToolFS.out(base + "-" + bg.title, "jpg")
            try d.write(to: dst)
            return dst
        }
        guard let out = ctx.createCGImage(ci, from: ci.extent), let d = UIImage(cgImage: out).pngData() else { throw Convert.err("生成图片失败") }
        let dst = ToolFS.out(base, "png")
        try d.write(to: dst)
        return dst
    }
}

// MARK: 二维码 / 条形码：从图片里读出内容，也能生成二维码
enum Barcode {
    struct Item: Identifiable {
        let id = UUID()
        let type: String
        let text: String

        var url: URL? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: t), let s = u.scheme?.lowercased(), ["http", "https", "tel", "mailto", "sms"].contains(s) else { return nil }
            return u
        }

        // WIFI:T:WPA;S:名称;P:密码;;
        var wifi: (ssid: String, password: String, security: String)? {
            guard text.uppercased().hasPrefix("WIFI:") else { return nil }
            func field(_ k: String) -> String {
                let body = String(text.dropFirst(5))
                var cur = ""
                var parts: [String] = []
                var esc = false
                for ch in body {
                    if esc { cur.append(ch); esc = false; continue }
                    if ch == "\\" { esc = true; continue }
                    if ch == ";" { parts.append(cur); cur = ""; continue }
                    cur.append(ch)
                }
                if !cur.isEmpty { parts.append(cur) }
                return parts.first(where: { $0.hasPrefix(k + ":") }).map { String($0.dropFirst(k.count + 1)) } ?? ""
            }
            return (field("S"), field("P"), field("T"))
        }
    }

    static func symbology(_ s: VNBarcodeSymbology) -> String {
        switch s {
        case .qr, .microQR: return "二维码"
        case .ean13, .ean8, .upce: return "商品条码"
        case .code128, .code39, .code93, .itf14, .i2of5, .codabar: return "条形码"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        default: return "条码"
        }
    }

    static func scan(_ cg: CGImage) -> [Item] {
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req])
        var seen = Set<String>()
        var items: [Item] = []
        for o in req.results ?? [] {
            guard let t = o.payloadStringValue, !t.isEmpty, seen.insert(t).inserted else { continue }
            items.append(Item(type: symbology(o.symbology), text: t))
        }
        return items
    }

    static func scan(_ url: URL) -> [Item] {
        guard let cg = OCR.cg(url, maxPixel: 3000) else { return [] }
        let r = scan(cg)
        if !r.isEmpty { return r }
        // 图片很大、码很小时，缩小后再试一次往往更准
        if let small = OCR.cg(url, maxPixel: 1200) { return scan(small) }
        return []
    }

    static func makeQR(_ text: String, side: CGFloat = 1024) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let o = f.outputImage else { return nil }
        let k = max(1, (side / o.extent.width).rounded(.down))
        let big = o.transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
        // 加白边
        let pad: CGFloat = 48
        let size = CGSize(width: CGFloat(cg.width) + pad * 2, height: CGFloat(cg.height) + pad * 2)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { c in
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: size))
            c.cgContext.interpolationQuality = .none
            UIImage(cgImage: cg).draw(in: CGRect(x: pad, y: pad, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        }
    }
}

// MARK: 图片处理：缩放、压缩到指定大小、旋转翻转、裁剪、清除隐私信息
enum ImageOps {
    static func readCG(_ u: URL, maxPixel: Int = 6144) throws -> CGImage {
        guard let cg = OCR.cg(u, maxPixel: maxPixel) else { throw Convert.err("图片读取失败") }
        return cg
    }

    static func resize(_ cg: CGImage, longSide: Int) -> CGImage {
        let w = cg.width
        let h = cg.height
        let m = max(w, h)
        guard longSide > 0, m > longSide else { return cg }
        let k = Double(longSide) / Double(m)
        let nw = max(1, Int((Double(w) * k).rounded()))
        let nh = max(1, Int((Double(h) * k).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? cg
    }

    static func rotate(_ cg: CGImage, degrees: Int, flipH: Bool = false, flipV: Bool = false) -> CGImage {
        var ci = CIImage(cgImage: cg)
        let d = ((degrees % 360) + 360) % 360
        if d != 0 {
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(d) * .pi / 180))   // 顺时针
        }
        if flipH { ci = ci.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
        if flipV { ci = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1)) }
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))
        return CIContext().createCGImage(ci, from: ci.extent) ?? cg
    }

    // 裁剪：比例坐标，左上角为原点
    static func crop(_ cg: CGImage, x: Double, y: Double, w: Double, h: Double) -> CGImage? {
        let r = CGRect(x: x * Double(cg.width), y: y * Double(cg.height), width: w * Double(cg.width), height: h * Double(cg.height))
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return cg.cropping(to: r)
    }

    // 压缩到不超过 maxKB：先降质量，再缩小尺寸
    static func jpegUnder(_ cg: CGImage, maxKB: Int) -> Data? {
        let limit = maxKB * 1024
        var img = cg
        for _ in 0..<8 {
            var lo: CGFloat = 0.25
            var hi: CGFloat = 0.95
            var best: Data?
            for _ in 0..<7 {
                let mid = (lo + hi) / 2
                guard let d = ToolFS.jpeg(img, quality: mid) else { break }
                if d.count <= limit { best = d; lo = mid } else { hi = mid }
            }
            if let b = best { return b }
            img = resize(img, longSide: Int(Double(max(img.width, img.height)) * 0.8))
            if max(img.width, img.height) < 200 { break }
        }
        return ToolFS.jpeg(img, quality: 0.25)
    }

    // 带透明通道的图（png）保持 png，其余输出 jpg
    static func write(_ cg: CGImage, like src: URL, base: String, quality: CGFloat = 0.9) throws -> URL {
        let hasAlpha: Bool = {
            switch cg.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return src.pathExtension.lowercased() == "png"
            }
        }()
        if hasAlpha, let d = UIImage(cgImage: cg).pngData() {
            let u = ToolFS.out(base, "png")
            try d.write(to: u)
            return u
        }
        guard let d = ToolFS.jpeg(cg, quality: quality) else { throw Convert.err("生成图片失败") }
        let u = ToolFS.out(base, "jpg")
        try d.write(to: u)
        return u
    }

    // 文件里带了哪些隐私信息（位置、设备型号、拍摄时间）
    static func privacy(_ u: URL) -> [String] {
        guard let s = CGImageSourceCreateWithURL(u as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return [] }
        var list: [String] = []
        if p[kCGImagePropertyGPSDictionary] != nil { list.append("拍摄位置") }
        if let t = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any], t[kCGImagePropertyTIFFModel] != nil { list.append("设备型号") }
        if let e = p[kCGImagePropertyExifDictionary] as? [CFString: Any], e[kCGImagePropertyExifDateTimeOriginal] != nil { list.append("拍摄时间") }
        return list
    }
}
