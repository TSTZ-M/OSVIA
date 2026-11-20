import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: PDF 工具箱：合并、拆分、提取页、旋转、压缩、加密、解密、加页码、加水印、图片转 PDF（全部在手机上处理）
enum PDFOps {
    enum Op: String, CaseIterable, Identifiable {
        case merge, split, extract, rotate, compress, protect, unlock, numbers, watermark, images
        var id: String { rawValue }

        var title: String {
            switch self {
            case .merge: return "合并"
            case .split: return "拆分"
            case .extract: return "提取页面"
            case .rotate: return "旋转"
            case .compress: return "压缩"
            case .protect: return "加密"
            case .unlock: return "解除密码"
            case .numbers: return "加页码"
            case .watermark: return "加水印"
            case .images: return "图片转 PDF"
            }
        }

        var hint: String {
            switch self {
            case .merge: return "选多个 PDF 或图片，按顺序合成一个 PDF"
            case .split: return "每页一个文件；或写页码范围，如 1-3,5,8-，每段一个文件"
            case .extract: return "只留下指定页码，如 1-3,5,8-（8- 表示第 8 页到最后）"
            case .rotate: return "整份或指定页顺时针旋转"
            case .compress: return "把页面压成图片以缩小体积（文字将不能选中，适合扫描件）"
            case .protect: return "设置打开密码"
            case .unlock: return "输入密码后存成没有密码的新文件"
            case .numbers: return "在每页底部加「第 n 页 / 共 N 页」"
            case .watermark: return "在每页中间斜着加半透明文字"
            case .images: return "把多张图片按顺序做成一个 PDF"
            }
        }

        static func parse(_ s: String) -> Op? {
            let t = s.lowercased()
            if let o = Op(rawValue: t) { return o }
            switch t {
            case "合并": return .merge
            case "拆分", "分割": return .split
            case "提取", "提取页面", "extract_pages": return .extract
            case "旋转": return .rotate
            case "压缩", "compress": return .compress
            case "加密", "encrypt": return .protect
            case "解密", "解除密码", "decrypt": return .unlock
            case "页码", "加页码", "page_numbers": return .numbers
            case "水印", "加水印": return .watermark
            case "图片转pdf", "img2pdf", "images_to_pdf": return .images
            default: return nil
            }
        }
    }

    // 页码范围：1-3,5,8-（从 1 开始）。返回 0 起的下标，保持书写顺序、去重
    static func pages(_ spec: String, count: Int) -> [Int] {
        var out: [Int] = []
        for part in spec.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",").components(separatedBy: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            let seg = p.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "~", with: "-").components(separatedBy: "-")
            if seg.count == 1, let n = Int(seg[0]) {
                if n >= 1 && n <= count { out.append(n - 1) }
            } else if seg.count == 2 {
                let a = Int(seg[0].trimmingCharacters(in: .whitespaces)) ?? 1
                let b = Int(seg[1].trimmingCharacters(in: .whitespaces)) ?? count
                let lo = max(1, min(a, b))
                let hi = min(count, max(a, b))
                if lo <= hi { out += Array((lo - 1)...(hi - 1)) }
            }
        }
        var seen = Set<Int>()
        return out.filter { seen.insert($0).inserted }
    }

    // 按书写的每一段分组（拆分用）
    static func groups(_ spec: String, count: Int) -> [[Int]] {
        spec.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",")
            .map { pages($0, count: count) }
            .filter { !$0.isEmpty }
    }

    static func open(_ u: URL, password: String = "") throws -> PDFDocument {
        guard let d = PDFDocument(url: u) else { throw Convert.err("无法打开 \(u.lastPathComponent)，可能不是有效的 PDF") }
        if d.isLocked && !(password.isEmpty ? false : d.unlock(withPassword: password)) {
            throw Convert.err("「\(u.lastPathComponent)」有密码，需要先输入密码")
        }
        return d
    }

    private static func copyPage(_ p: PDFPage) -> PDFPage { (p.copy() as? PDFPage) ?? p }

    private static func save(_ doc: PDFDocument, _ base: String, options: [PDFDocumentWriteOption: Any]? = nil) throws -> URL {
        let dst = ToolFS.out(base, "pdf")
        let ok = options == nil ? doc.write(to: dst) : doc.write(to: dst, withOptions: options)
        guard ok else { throw Convert.err("保存 PDF 失败") }
        return dst
    }

    private static func make(_ list: [PDFPage]) -> PDFDocument {
        let d = PDFDocument()
        for p in list { d.insert(copyPage(p), at: d.pageCount) }
        return d
    }

    // MARK: 合并（PDF 与图片可以混合）
    static func merge(_ urls: [URL], password: String = "") throws -> URL {
        guard urls.count >= 1 else { throw Convert.err("请至少选一个文件") }
        let doc = PDFDocument()
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                let src = try open(u, password: password)
                for i in 0..<src.pageCount { if let p = src.page(at: i) { doc.insert(copyPage(p), at: doc.pageCount) } }
            } else if Files.isImage(u), let cg = OCR.cg(u, maxPixel: 2400), let p = PDFPage(image: UIImage(cgImage: cg)) {
                doc.insert(p, at: doc.pageCount)
            }
        }
        guard doc.pageCount > 0 else { throw Convert.err("没有可合并的页面") }
        return try save(doc, "合并-" + ToolFS.base(urls[0]))
    }

    static func imagesToPDF(_ urls: [URL]) throws -> URL {
        let imgs = urls.filter { Files.isImage($0) }
        guard !imgs.isEmpty else { throw Convert.err("请选择图片") }
        let doc = PDFDocument()
        for u in imgs {
            guard let cg = OCR.cg(u, maxPixel: 2400), let p = PDFPage(image: UIImage(cgImage: cg)) else { continue }
            doc.insert(p, at: doc.pageCount)
        }
        guard doc.pageCount > 0 else { throw Convert.err("图片读取失败") }
        return try save(doc, imgs.count == 1 ? ToolFS.base(imgs[0]) : "图片合集-\(imgs.count)张")
    }

    // MARK: 拆分
    static func split(_ u: URL, spec: String, password: String = "") throws -> [URL] {
        let src = try open(u, password: password)
        let n = src.pageCount
        let base = ToolFS.base(u)
        var gs: [[Int]] = spec.trimmingCharacters(in: .whitespaces).isEmpty ? (0..<n).map { [$0] } : groups(spec, count: n)
        guard !gs.isEmpty else { throw Convert.err("页码范围不正确（共 \(n) 页）") }
        if gs.count > 60 { gs = Array(gs.prefix(60)) }
        var outs: [URL] = []
        for (i, g) in gs.enumerated() {
            let d = make(g.compactMap { src.page(at: $0) })
            let label = g.count == 1 ? "第\(g[0] + 1)页" : "第\(g[0] + 1)-\(g[g.count - 1] + 1)页"
            outs.append(try save(d, "\(base)-\(gs.count == n ? label : "部分\(i + 1)(\(label))")"))
        }
        return outs
    }

    static func extract(_ u: URL, spec: String, password: String = "") throws -> URL {
        let src = try open(u, password: password)
        let idx = pages(spec, count: src.pageCount)
        guard !idx.isEmpty else { throw Convert.err("页码不正确（共 \(src.pageCount) 页）") }
        return try save(make(idx.compactMap { src.page(at: $0) }), ToolFS.base(u) + "-提取\(idx.count)页")
    }

    // MARK: 旋转（顺时针，pages 为空 = 全部）
    static func rotate(_ u: URL, degrees: Int, spec: String, password: String = "") throws -> URL {
        let src = try open(u, password: password)
        let doc = make((0..<src.pageCount).compactMap { src.page(at: $0) })
        let idx = spec.trimmingCharacters(in: .whitespaces).isEmpty ? Array(0..<doc.pageCount) : pages(spec, count: doc.pageCount)
        guard !idx.isEmpty else { throw Convert.err("页码不正确（共 \(doc.pageCount) 页）") }
        for i in idx {
            guard let p = doc.page(at: i) else { continue }
            p.rotation = (((p.rotation + degrees) % 360) + 360) % 360
        }
        return try save(doc, ToolFS.base(u) + "-旋转")
    }

    // MARK: 压缩：每页渲染成 JPEG 再合成
    static func compress(_ u: URL, quality: Int, password: String = "") throws -> (URL, Int64, Int64) {
        let src = try open(u, password: password)
        let (maxSide, q): (CGFloat, CGFloat) = quality >= 2 ? (2000, 0.8) : (quality == 1 ? (1500, 0.6) : (1100, 0.45))
        let doc = PDFDocument()
        for i in 0..<src.pageCount {
            guard let p = src.page(at: i) else { continue }
            let box = p.bounds(for: .mediaBox)
            let k = min(1, maxSide / max(box.width, box.height, 1))
            let sz = CGSize(width: max(1, (box.width * k).rounded()), height: max(1, (box.height * k).rounded()))
            let img = p.thumbnail(of: sz, for: .mediaBox)
            guard let jd = img.jpegData(compressionQuality: q), let ji = UIImage(data: jd), let np = PDFPage(image: ji) else { continue }
            // 保持原来的页面尺寸
            np.setBounds(CGRect(origin: .zero, size: box.size), for: .mediaBox)
            doc.insert(np, at: doc.pageCount)
        }
        guard doc.pageCount > 0 else { throw Convert.err("压缩失败") }
        let before = Files.size(u) ?? 0
        let dst = try save(doc, ToolFS.base(u) + "-压缩")
        return (dst, before, Files.size(dst) ?? 0)
    }

    // MARK: 加密 / 解密
    static func protect(_ u: URL, password: String, openPassword: String = "") throws -> URL {
        guard password.count >= 1 else { throw Convert.err("请输入要设置的密码") }
        let src = try open(u, password: openPassword)
        let doc = make((0..<src.pageCount).compactMap { src.page(at: $0) })
        return try save(doc, ToolFS.base(u) + "-已加密", options: [.userPasswordOption: password, .ownerPasswordOption: password])
    }

    static func unlock(_ u: URL, password: String) throws -> URL {
        guard let src = PDFDocument(url: u) else { throw Convert.err("无法打开这个 PDF") }
        if src.isLocked {
            guard !password.isEmpty, src.unlock(withPassword: password) else { throw Convert.err("密码不正确") }
        }
        let doc = make((0..<src.pageCount).compactMap { src.page(at: $0) })
        return try save(doc, ToolFS.base(u) + "-已解除密码")
    }

    // MARK: 在每一页上叠加内容（页码、水印）：逐页重绘，保留文字与矢量内容
    private static func stamp(_ src: PDFDocument, _ base: String, draw: (Int, Int, CGSize, CGContext) -> Void) throws -> URL {
        let n = src.pageCount
        var rotations: [Int] = []
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { ctx in
            for i in 0..<n {
                guard let page = src.page(at: i) else { continue }
                let copy = copyPage(page)
                rotations.append(page.rotation)
                copy.rotation = 0
                let box = copy.bounds(for: .mediaBox)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: box.size), pageInfo: [:])
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: box.height)
                cg.scaleBy(x: 1, y: -1)
                cg.translateBy(x: -box.minX, y: -box.minY)
                copy.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                draw(i, n, box.size, cg)
            }
        }
        guard let out = PDFDocument(data: data), out.pageCount > 0 else { throw Convert.err("生成 PDF 失败") }
        for (i, r) in rotations.enumerated() where r != 0 { out.page(at: i)?.rotation = r }
        return try save(out, base)
    }

    static func numbers(_ u: URL, password: String = "") throws -> URL {
        let src = try open(u, password: password)
        return try stamp(src, ToolFS.base(u) + "-页码") { i, n, size, _ in
            let text = "第 \(i + 1) 页 / 共 \(n) 页" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: max(9, size.width * 0.018)), .foregroundColor: UIColor.darkGray]
            let w = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - w.width) / 2, y: size.height - w.height - size.height * 0.02), withAttributes: attrs)
        }
    }

    static func watermark(_ u: URL, text: String, password: String = "") throws -> URL {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Convert.err("请输入水印文字") }
        let src = try open(u, password: password)
        return try stamp(src, ToolFS.base(u) + "-水印") { _, _, size, cg in
            let fs = min(size.width / CGFloat(max(t.count, 4)) * 1.1, size.width * 0.16)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: fs), .foregroundColor: UIColor.gray.withAlphaComponent(0.28)]
            let s = t as NSString
            let w = s.size(withAttributes: attrs)
            cg.saveGState()
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -.pi / 4)
            s.draw(at: CGPoint(x: -w.width / 2, y: -w.height / 2), withAttributes: attrs)
            cg.restoreGState()
        }
    }

    // 界面和对话工具共用的入口
    static func perform(_ op: Op, files: [URL], spec: String = "", angle: Int = 90, password: String = "", mark: String = "", quality: Int = 1) throws -> ([URL], String) {
        guard let first = files.first else { throw Convert.err("请先选择文件") }
        switch op {
        case .merge: return ([try merge(files, password: password)], "")
        case .images: return ([try imagesToPDF(files)], "")
        case .split: return (try split(first, spec: spec, password: password), "")
        case .extract: return ([try extract(first, spec: spec, password: password)], "")
        case .rotate: return ([try rotate(first, degrees: angle, spec: spec, password: password)], "")
        case .compress:
            let c = try compress(first, quality: quality, password: password)
            let a = ByteCountFormatter.string(fromByteCount: c.1, countStyle: .file)
            let b = ByteCountFormatter.string(fromByteCount: c.2, countStyle: .file)
            return ([c.0], "\(a) → \(b)")
        case .protect: return ([try protect(first, password: password)], "")
        case .unlock: return ([try unlock(first, password: password)], "")
        case .numbers: return ([try numbers(first, password: password)], "")
        case .watermark: return ([try watermark(first, text: mark, password: password)], "")
        }
    }

    static func info(_ u: URL) -> (pages: Int, locked: Bool)? {
        guard let d = PDFDocument(url: u) else { return nil }
        return (d.pageCount, d.isLocked)
    }
}

// MARK: 界面
struct PDFToolView: View {
    @State private var op: PDFOps.Op
    @State private var files: [URL]
    @State private var pageSpec = ""
    @State private var angle = 90
    @State private var password = ""
    @State private var openPassword = ""
    @State private var mark = ""
    @State private var quality = 1
    @State private var outs: [URL] = []
    @State private var note = ""
    @State private var err = ""
    @State private var busy = false

    init(initial: [URL] = [], op: PDFOps.Op = .merge) {
        let pdfs = initial.filter { $0.pathExtension.lowercased() == "pdf" }
        let imgs = initial.filter { Files.isImage($0) }
        var o = op
        var f = initial
        if !imgs.isEmpty && pdfs.isEmpty { o = .images; f = imgs }
        else if pdfs.count == 1 && imgs.isEmpty && op == .merge { o = .compress; f = pdfs }
        _op = State(initialValue: o)
        _files = State(initialValue: f)
    }

    private var multi: Bool { op == .merge || op == .images }
    private var types: [UTType] { (op == .images ? [.image] : (op == .merge ? [.pdf, .image] : [.pdf])) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    ForEach(PDFOps.Op.allCases) { o in
                        Button { change(o) } label: { Label(LocalizedStringKey(o.title), systemImage: op == o ? "checkmark" : "doc.richtext") }
                    }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(op.title)).fontSz(17, weight: .semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").fontSz(12).foregroundStyle(Brand.sub)
                    }
                    .foregroundStyle(Brand.ink)
                    .padding(14)
                    .background(Brand.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(LocalizedStringKey(op.hint)).font(.footnote).foregroundStyle(Brand.sub)

                PickSources(types: types, camera: false, paste: false, multiple: multi) { urls in
                    err = ""
                    outs = []
                    note = ""
                    files = multi ? files + urls : Array(urls.prefix(1))
                } onError: { err = $0 }

                if !files.isEmpty { fileList }
                options

                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                Button { run() } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "处理中…" : "开始").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || files.isEmpty)

                if !outs.isEmpty {
                    if !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(Brand.sub) }
                    OutputList(urls: outs)
                }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("PDF 工具")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change(_ o: PDFOps.Op) {
        op = o
        outs = []
        err = ""
        note = ""
        if !multi && files.count > 1 { files = Array(files.prefix(1)) }
        files = files.filter { op == .images ? Files.isImage($0) : ($0.pathExtension.lowercased() == "pdf" || (op == .merge && Files.isImage($0))) }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.offset) { i, u in
                HStack(spacing: 10) {
                    Image(systemName: Files.isImage(u) ? "photo" : "doc.richtext").foregroundStyle(Brand.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.lastPathComponent).font(.subheadline).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                        if u.pathExtension.lowercased() == "pdf", let inf = PDFOps.info(u) {
                            Text(L10n.f("{} 页", "\(inf.pages)") + (inf.locked ? " · " + L10n.tr("有密码") : "")).font(.caption).foregroundStyle(Brand.sub)
                        }
                    }
                    Spacer(minLength: 0)
                    if multi && files.count > 1 {
                        Button { if i > 0 { files.swapAt(i, i - 1) } } label: { Image(systemName: "arrow.up").frame(minWidth: 30, minHeight: 30) }
                            .disabled(i == 0)
                            .accessibilityLabel("上移")
                        Button { if i < files.count - 1 { files.swapAt(i, i + 1) } } label: { Image(systemName: "arrow.down").frame(minWidth: 30, minHeight: 30) }
                            .disabled(i == files.count - 1)
                            .accessibilityLabel("下移")
                    }
                    Button { files.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.sub).frame(minWidth: 30, minHeight: 30) }
                        .accessibilityLabel("移除")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if i < files.count - 1 { Divider().padding(.leading, 12) }
            }
        }
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var options: some View {
        switch op {
        case .split, .extract:
            field("页码范围", "如 1-3,5,8-（拆分时留空 = 每页一个文件）", text: $pageSpec)
        case .rotate:
            Picker("角度", selection: $angle) {
                Text("顺时针 90°").tag(90)
                Text("180°").tag(180)
                Text("逆时针 90°").tag(270)
            }
            .pickerStyle(.segmented)
            field("页码范围（留空 = 全部）", "如 2,4-6", text: $pageSpec)
        case .compress:
            Picker("压缩程度", selection: $quality) {
                Text("轻度").tag(2)
                Text("中等").tag(1)
                Text("强力").tag(0)
            }
            .pickerStyle(.segmented)
        case .protect:
            secure("设置打开密码", $password)
        case .unlock:
            secure("PDF 的密码", $password)
        case .watermark:
            field("水印文字", "如：仅供办理业务使用", text: $mark)
        default:
            EmptyView()
        }
    }

    private func field(_ title: String, _ ph: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.footnote.weight(.semibold)).foregroundStyle(Brand.sub)
            TextField(LocalizedStringKey(ph), text: text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func secure(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.footnote.weight(.semibold)).foregroundStyle(Brand.sub)
            SecureField("密码", text: text)
                .padding(12)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func run() {
        busy = true
        err = ""
        note = ""
        outs = []
        let op = self.op, files = self.files, spec = self.pageSpec, angle = self.angle, pw = self.password, mark = self.mark, quality = self.quality
        Task {
            do {
                let r = try await Task<([URL], String), Error>.detached(priority: .userInitiated) {
                    try PDFOps.perform(op, files: files, spec: spec, angle: angle, password: pw, mark: mark, quality: quality)
                }.value
                outs = r.0
                note = r.1
            } catch {
                err = error.localizedDescription
            }
            busy = false
        }
    }
}
