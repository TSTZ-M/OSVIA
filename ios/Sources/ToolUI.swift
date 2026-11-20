import SwiftUI
import PhotosUI
import QuickLook
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: 选文件的统一入口：相册、拍照、文件、剪贴板，选好后回调本地文件地址
struct PickSources: View {
    var types: [UTType] = [.image]
    var allowVideo = false
    var camera = true
    var paste = true
    var multiple = false
    var onPick: ([URL]) -> Void
    var onError: (String) -> Void

    @State private var showPhotos = false
    @State private var showFile = false
    @State private var showCamera = false
    @State private var items: [PhotosPickerItem] = []

    init(types: [UTType] = [.image], allowVideo: Bool = false, camera: Bool = true, paste: Bool = true, multiple: Bool = false,
         onPick: @escaping ([URL]) -> Void, onError: @escaping (String) -> Void) {
        self.types = types
        self.allowVideo = allowVideo
        self.camera = camera
        self.paste = paste
        self.multiple = multiple
        self.onPick = onPick
        self.onError = onError
    }

    private var imageOK: Bool { types.contains { $0.conforms(to: .image) } }

    var body: some View {
        HStack(spacing: 10) {
            if imageOK || allowVideo { tile("photo.on.rectangle", "相册") { showPhotos = true } }
            if camera && imageOK { tile("camera", "拍照") { showCamera = true } }
            tile("folder", "文件") { showFile = true }
            if paste && imageOK { tile("doc.on.clipboard", "剪贴板") { pasteImage() } }
        }
        .photosPicker(isPresented: $showPhotos, selection: $items, maxSelectionCount: multiple ? 20 : 1, matching: filter)
        .onChange(of: items) { _, v in
            guard !v.isEmpty else { return }
            items = []
            Task {
                var add: [URL] = []
                for it in v {
                    let r = await MediaPick.load(it)
                    if let u = r.url { add.append(u) } else if !r.error.isEmpty { onError(r.error) }
                }
                if !add.isEmpty { onPick(add) }
            }
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: types, allowsMultipleSelection: multiple) { r in
            guard let picked = try? r.get() else { return }
            var add: [URL] = []
            for u in picked {
                let res = Files.importFile(u)
                if let c = res.url { add.append(c) } else if let e = res.error { onError(e) }
            }
            if !add.isEmpty { onPick(add) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { u, e in
                showCamera = false
                if let u { onPick([u]) } else if let e { onError(e) }
            }
            .ignoresSafeArea()
        }
    }

    private var filter: PHPickerFilter {
        if imageOK && allowVideo { return PHPickerFilter.any(of: [.images, .videos]) }
        return allowVideo ? PHPickerFilter.videos : PHPickerFilter.images
    }

    private func tile(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Brand.mint)
                Text(LocalizedStringKey(label)).fontSz(12.5).foregroundStyle(Brand.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pasteImage() {
        guard UIPasteboard.general.hasImages, let img = UIPasteboard.general.image, let d = Files.jpeg(from: img) else { onError("剪贴板里没有图片"); return }
        let s = Files.save(d, name: "粘贴图片-\(Files.stampText()).jpg")
        if let u = s.url { onPick([u]) } else { onError("保存失败（\(s.error)）") }
    }
}

// MARK: 结果列表：预览、存入相册、分享
struct OutputList: View {
    let urls: [URL]
    @State private var preview: URL?

    init(urls: [URL]) { self.urls = urls }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(urls, id: \.self) { u in
                VStack(alignment: .leading, spacing: 8) {
                    FileCard(url: u, preview: $preview)
                    HStack(spacing: 18) {
                        if Files.isImage(u) { Button("存入相册") { PhotoSave.save(u) } }
                        ShareLink(item: u) { Text("分享") }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .quickLookPreview($preview)
    }
}

private struct ToolNote: View {
    let text: String
    var body: some View {
        Text(LocalizedStringKey(text)).font(.footnote).foregroundStyle(Brand.sub)
    }
}

private struct ToolError: View {
    let text: String
    var body: some View {
        if !text.isEmpty { Label(text, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
    }
}

private struct ToolCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Brand.card).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: 文档扫描：系统扫描器 → 自动裁边 → 可搜索的 PDF
struct DocScanner: UIViewControllerRepresentable {
    var onDone: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let v = VNDocumentCameraViewController()
        v.delegate = context.coordinator
        return v
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocScanner
        init(_ p: DocScanner) { parent = p }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var imgs: [UIImage] = []
            for i in 0..<scan.pageCount { imgs.append(scan.imageOfPage(at: i)) }
            parent.onDone(imgs)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onCancel() }
    }
}

enum DocEnhance {
    // 黑白文档增强：去色、提亮、提高对比度、锐化
    static func apply(_ cg: CGImage) -> CGImage {
        let ci = CIImage(cgImage: cg)
        let c = CIFilter.colorControls()
        c.inputImage = ci
        c.saturation = 0
        c.contrast = 1.3
        c.brightness = 0.05
        guard let o1 = c.outputImage else { return cg }
        let s = CIFilter.sharpenLuminance()
        s.inputImage = o1
        s.sharpness = 0.45
        guard let o2 = s.outputImage, let out = CIContext().createCGImage(o2, from: ci.extent) else { return cg }
        return out
    }
}

enum SearchablePDF {
    // 每页：图片铺满，再把识别出的文字隐形叠在原位，PDF 里就能搜索、选中、复制
    static func make(_ items: [(CGImage, [OCR.Line])]) -> Data {
        let pageW: CGFloat = 595
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: 842))
        return renderer.pdfData { ctx in
            for (cg, lines) in items {
                let h = pageW * CGFloat(cg.height) / CGFloat(max(cg.width, 1))
                let size = CGSize(width: pageW, height: h)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
                let c = ctx.cgContext
                c.saveGState()
                c.setTextDrawingMode(.invisible)
                for l in lines {
                    let r = CGRect(x: l.box.minX * size.width, y: l.box.minY * size.height, width: l.box.width * size.width, height: l.box.height * size.height)
                    let fs = max(4, r.height * 0.85)
                    let attr = NSAttributedString(string: l.text, attributes: [.font: UIFont.systemFont(ofSize: fs)])
                    let line = CTLineCreateWithAttributedString(attr)
                    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    let sx = w > 0 ? r.width / w : 1
                    c.textMatrix = CGAffineTransform(a: sx, b: 0, c: 0, d: -1, tx: 0, ty: 0)
                    c.textPosition = CGPoint(x: r.minX, y: r.maxY - r.height * 0.2)
                    CTLineDraw(line, c)
                }
                c.restoreGState()
            }
        }
    }
}

struct ScanView: View {
    @State private var pages: [UIImage] = []
    @State private var showScanner = false
    @State private var enhance = true
    @State private var out: URL?
    @State private var text = ""
    @State private var busy = false
    @State private var err = ""

    private var supported: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { showScanner = true } label: {
                    Label(pages.isEmpty ? "开始扫描" : "继续扫描（追加页面）", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!supported || busy)
                if !supported { ToolError(text: "这台设备不支持文档扫描") }

                Toggle("黑白增强（文字更清晰）", isOn: $enhance)
                    .padding(12)
                    .modifier(ToolCardBackground())
                    .onChange(of: enhance) { _, _ in if !pages.isEmpty { build() } }

                if pages.isEmpty {
                    ToolNote(text: "把文件放在桌面上，对准即可自动识别边缘、拍照并拉直。可连续扫多页，生成的 PDF 里文字可搜索、可复制，全部在本机完成。")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { i, img in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 84, height: 112)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Button {
                                        pages.remove(at: i)
                                        if pages.isEmpty { out = nil; text = "" } else { build() }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.black.opacity(0.6)).padding(6)
                                    }
                                    .accessibilityLabel("删除这一页")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if busy { HStack(spacing: 8) { ProgressView(); Text("正在整理并识别文字…").font(.subheadline).foregroundStyle(Brand.sub) } }
                ToolError(text: err)
                if let o = out { OutputList(urls: [o]) }
                if !text.isEmpty { ResultTextPanel(title: "识别出的文字", text: text) }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("文档扫描")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) {
            DocScanner(onDone: { imgs in
                showScanner = false
                pages += imgs
                build()
            }, onCancel: { showScanner = false })
                .ignoresSafeArea()
        }
    }

    private func build() {
        busy = true
        err = ""
        let list = pages
        let enh = enhance
        Task {
            let r = await Task<(Data, String)?, Never>.detached(priority: .userInitiated) {
                var items: [(CGImage, [OCR.Line])] = []
                var all: [String] = []
                for (i, img) in list.prefix(40).enumerated() {
                    guard var cg = img.cgImage else { continue }
                    if enh { cg = DocEnhance.apply(cg) }
                    let lines = OCR.lines(cg)
                    items.append((cg, lines))
                    let t = lines.map { $0.text }.joined(separator: "\n")
                    if !t.isEmpty { all.append(list.count > 1 ? "—— 第 \(i + 1) 页 ——\n" + t : t) }
                }
                guard !items.isEmpty else { return nil }
                return (SearchablePDF.make(items), all.joined(separator: "\n\n"))
            }.value
            if let r {
                let dst = ToolFS.out("扫描-" + Files.stampText(), "pdf")
                do {
                    try r.0.write(to: dst)
                    out = dst
                    text = r.1
                } catch {
                    err = "保存失败：" + error.localizedDescription
                }
            } else {
                err = "没有扫描到有效的页面"
            }
            busy = false
        }
    }
}

// MARK: 二维码：读取 / 生成
struct QRView: View {
    @State private var mode = 0
    @State private var found: [Barcode.Item] = []
    @State private var scanned = false
    @State private var busy = false
    @State private var err = ""
    @State private var input = ""
    @State private var made: URL?
    @State private var copied = ""
    private let initial: URL?

    init(initial: [URL] = []) { self.initial = initial.first(where: { Files.isImage($0) }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("模式", selection: $mode) {
                    Text("读取").tag(0)
                    Text("生成").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 { scanPane } else { makePane }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("二维码")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let u = initial, !scanned else { return }
            busy = true
            found = await Task.detached(priority: .userInitiated) { Barcode.scan(u) }.value
            scanned = true
            busy = false
        }
    }

    @ViewBuilder private var scanPane: some View {
        PickSources(types: [.image], multiple: false) { urls in
            guard let u = urls.first else { return }
            busy = true
            err = ""
            Task {
                let r = await Task.detached(priority: .userInitiated) { Barcode.scan(u) }.value
                found = r
                scanned = true
                busy = false
            }
        } onError: { err = $0 }
        if busy { ProgressView() }
        ToolError(text: err)
        if scanned && found.isEmpty && !busy { ToolNote(text: "没有找到二维码或条形码。换一张更清晰、码更大的图试试。") }
        if !scanned { ToolNote(text: "选一张含二维码或条形码的图片，本机读出内容，不上传。") }
        ForEach(found) { it in
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedStringKey(it.type)).font(.caption.weight(.semibold)).foregroundStyle(Brand.mint)
                if let w = it.wifi {
                    Text(verbatim: "Wi-Fi：\(w.ssid)").fontSz(16, weight: .semibold)
                    Text(verbatim: L10n.tr("密码") + "：" + (w.password.isEmpty ? "—" : w.password)).font(.subheadline).foregroundStyle(Brand.sub).textSelection(.enabled)
                } else {
                    Text(verbatim: it.text).font(.body).foregroundStyle(Brand.ink).textSelection(.enabled)
                }
                HStack(spacing: 18) {
                    Button(copied == it.text ? "已复制" : "复制") {
                        UIPasteboard.general.string = it.wifi?.password.isEmpty == false ? it.wifi?.password : it.text
                        copied = it.text
                    }
                    if let u = it.url { Link("打开", destination: u) }
                    ShareLink(item: it.text) { Text("分享") }
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .modifier(ToolCardBackground())
        }
    }

    @ViewBuilder private var makePane: some View {
        TextField("网址、文字、Wi-Fi（WIFI:T:WPA;S:名称;P:密码;;）", text: $input, axis: .vertical)
            .lineLimit(2...6)
            .padding(12)
            .modifier(ToolCardBackground())
        Button {
            let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let img = Barcode.makeQR(t), let d = img.pngData() else { err = "内容为空或太长，无法生成"; return }
            let dst = ToolFS.out("二维码", "png")
            do { try d.write(to: dst); made = dst; err = "" } catch { err = error.localizedDescription }
        } label: { Text("生成二维码").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        ToolError(text: err)
        if let u = made, let ui = UIImage(contentsOfFile: u.path) {
            Image(uiImage: ui).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 260).frame(maxWidth: .infinity)
            OutputList(urls: [u])
        }
    }
}

// MARK: 打码
struct RedactView: View {
    @State private var url: URL?
    @State private var hits: [Redact.Hit] = []
    @State private var chosen: Set<Redact.Kind> = []
    @State private var style = 0
    @State private var busy = false
    @State private var analyzed = false
    @State private var out: URL?
    @State private var leaked: [String] = []
    @State private var err = ""

    init(initial: URL? = nil) {
        _url = State(initialValue: initial)
    }

    private func count(_ k: Redact.Kind) -> Int { hits.filter { $0.kind == k }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PickSources(types: [.image], multiple: false) { urls in
                    guard let u = urls.first else { return }
                    load(u)
                } onError: { err = $0 }

                if let u = url, let ui = Files.thumb(u, max: 900) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if busy { HStack(spacing: 8) { ProgressView(); Text("正在识别…").font(.subheadline).foregroundStyle(Brand.sub) } }
                ToolError(text: err)
                if url == nil {
                    ToolNote(text: "自动找出图里的手机号、身份证号、银行卡号、邮箱、网址、车牌和人脸，一键打码后再发出去。结果会同时清除拍摄位置等隐私信息。")
                }
                if analyzed {
                    VStack(spacing: 0) {
                        ForEach(Redact.Kind.allCases) { k in
                            let n = count(k)
                            if n > 0 {
                                Toggle(isOn: Binding(get: { chosen.contains(k) }, set: { on in
                                    if on { chosen.insert(k) } else { chosen.remove(k) }
                                })) {
                                    Label {
                                        Text(LocalizedStringKey(k.title)) + Text(verbatim: "  ·  \(n)")
                                    } icon: { Image(systemName: k.icon) }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                Divider().padding(.leading, 12)
                            }
                        }
                        if hits.isEmpty { Text("没有发现需要遮挡的内容").font(.subheadline).foregroundStyle(Brand.sub).padding(14) }
                    }
                    .modifier(ToolCardBackground())
                    if !hits.isEmpty {
                        Picker("样式", selection: $style) {
                            Text("马赛克").tag(0)
                            Text("涂黑").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                    if !leaked.isEmpty {
                        ToolNote(text: "原图里带有：" + leaked.map { L10n.tr($0) }.joined(separator: "、") + "。导出的图片已清除。")
                    }
                    Button { apply() } label: { Text("打码并导出").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(busy || chosen.isEmpty)
                }
                if let o = out { OutputList(urls: [o]) }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("图片打码")
        .navigationBarTitleDisplayMode(.inline)
        .task { if let u = url, !analyzed { load(u) } }
    }

    private func load(_ u: URL) {
        url = u
        out = nil
        err = ""
        analyzed = false
        hits = []
        chosen = []
        leaked = ImageOps.privacy(u)
        busy = true
        Task {
            let r = await Task<[Redact.Hit], Never>.detached(priority: .userInitiated) {
                guard let cg = OCR.cg(u, maxPixel: 4096) else { return [] }
                return Redact.analyze(cg)
            }.value
            hits = r
            chosen = Set(Redact.Kind.allCases.filter { $0 != .all && r.contains(where: { h in h.kind == $0 }) })
            analyzed = true
            busy = false
        }
    }

    private func apply() {
        guard let u = url else { return }
        busy = true
        err = ""
        let pick = hits.filter { chosen.contains($0.kind) }
        let st: Redact.Style = style == 0 ? .mosaic : .black
        Task {
            let d = await Task<Data?, Never>.detached(priority: .userInitiated) {
                guard let cg = OCR.cg(u, maxPixel: 4096) else { return nil }
                return Redact.apply(cg, hits: pick, style: st)
            }.value
            if let d {
                let dst = ToolFS.out("打码-" + ToolFS.base(u), "jpg")
                do { try d.write(to: dst); out = dst } catch { err = error.localizedDescription }
            } else {
                err = "生成图片失败"
            }
            busy = false
        }
    }
}

// MARK: 抠图 / 证件照换底色
struct CutoutView: View {
    @State private var url: URL?
    @State private var bg = Cutout.Background.clear
    @State private var crop = false
    @State private var out: URL?
    @State private var busy = false
    @State private var err = ""

    init(initial: URL? = nil) { _url = State(initialValue: initial) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PickSources(types: [.image], multiple: false) { urls in
                    url = urls.first
                    out = nil
                    err = ""
                } onError: { err = $0 }
                if let u = url, let ui = Files.thumb(u, max: 900) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ToolNote(text: "自动识别人物、宠物、物品等主体并去掉背景，可存成透明图，也可换成证件照常用的白、蓝、红底。")
                }
                Picker("背景", selection: $bg) {
                    ForEach(Cutout.Background.allCases) { b in Text(LocalizedStringKey(b.title)).tag(b) }
                }
                .pickerStyle(.segmented)
                Toggle("裁到主体边缘", isOn: $crop)
                    .padding(12)
                    .modifier(ToolCardBackground())
                if busy { HStack(spacing: 8) { ProgressView(); Text("正在抠图…").font(.subheadline).foregroundStyle(Brand.sub) } }
                ToolError(text: err)
                Button { run() } label: { Text("开始抠图").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy || url == nil)
                if let o = out, let ui = UIImage(contentsOfFile: o.path) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 320)
                        .background(Brand.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    OutputList(urls: [o])
                }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("抠图换底")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        guard let u = url else { return }
        busy = true
        err = ""
        let b = bg, c = crop
        Task {
            do {
                out = try await Task.detached(priority: .userInitiated) { try Cutout.run(u, bg: b, crop: c) }.value
            } catch {
                err = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: 图片处理：尺寸、压缩、旋转翻转、裁剪、清除隐私信息
struct ImageToolView: View {
    enum Mode: Int, CaseIterable {
        case size, compress, rotate, crop, strip
        var title: String {
            switch self {
            case .size: return "缩小尺寸"
            case .compress: return "压缩到指定大小"
            case .rotate: return "旋转翻转"
            case .crop: return "裁剪比例"
            case .strip: return "清除隐私信息"
            }
        }
    }

    @State private var files: [URL]
    @State private var mode = Mode.size
    @State private var longSide = 1080
    @State private var maxKB = 500
    @State private var rot = 90
    @State private var ratio = 0
    @State private var outs: [URL] = []
    @State private var note = ""
    @State private var err = ""
    @State private var busy = false

    init(initial: [URL] = []) { _files = State(initialValue: initial.filter { Files.isImage($0) }) }

    private let ratios: [(String, Double)] = [("1:1", 1), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    ForEach(Mode.allCases, id: \.rawValue) { m in
                        Button { mode = m; outs = []; note = "" } label: { Label(LocalizedStringKey(m.title), systemImage: mode == m ? "checkmark" : "photo") }
                    }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(mode.title)).fontSz(17, weight: .semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").fontSz(12).foregroundStyle(Brand.sub)
                    }
                    .foregroundStyle(Brand.ink)
                    .padding(14)
                    .modifier(ToolCardBackground())
                }
                PickSources(types: [.image], multiple: true) { urls in
                    files += urls
                    outs = []
                    note = ""
                    err = ""
                } onError: { err = $0 }

                if !files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(files.enumerated()), id: \.offset) { i, u in
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if let ui = Files.thumb(u, max: 200) { Image(uiImage: ui).resizable().scaledToFill() } else { Color.gray.opacity(0.2) }
                                    }
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Button { files.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.black.opacity(0.6)).padding(5)
                                    }
                                    .accessibilityLabel("移除")
                                }
                            }
                        }
                    }
                }
                options
                ToolError(text: err)
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
        .navigationTitle("图片处理")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var options: some View {
        switch mode {
        case .size:
            Picker("长边", selection: $longSide) {
                Text("4096").tag(4096)
                Text("2048").tag(2048)
                Text("1080").tag(1080)
                Text("720").tag(720)
            }
            .pickerStyle(.segmented)
            ToolNote(text: "按长边缩小，保持比例；不会放大。")
        case .compress:
            Picker("目标大小", selection: $maxKB) {
                Text("100 KB").tag(100)
                Text("200 KB").tag(200)
                Text("500 KB").tag(500)
                Text("1 MB").tag(1024)
                Text("2 MB").tag(2048)
            }
            .pickerStyle(.segmented)
            ToolNote(text: "先降画质，仍然太大再缩小尺寸，存成 JPG。适合各种表单上传限制。")
        case .rotate:
            Picker("操作", selection: $rot) {
                Text("右转 90°").tag(90)
                Text("180°").tag(180)
                Text("左转 90°").tag(270)
                Text("左右翻转").tag(1)
                Text("上下翻转").tag(2)
            }
            .pickerStyle(.menu)
        case .crop:
            Picker("比例", selection: $ratio) {
                ForEach(0..<ratios.count, id: \.self) { i in Text(verbatim: ratios[i].0).tag(i) }
            }
            .pickerStyle(.segmented)
            ToolNote(text: "从中心裁出所选比例。")
        case .strip:
            ToolNote(text: "重新生成图片，清除拍摄位置、设备型号、拍摄时间等信息，发朋友圈或论坛前更安心。")
        }
    }

    private func run() {
        busy = true
        err = ""
        outs = []
        note = ""
        let list = files, m = mode, ls = longSide, kb = maxKB, rt = rot, rr = ratios[min(ratio, ratios.count - 1)].1
        Task {
            do {
                let r = try await Task<([URL], String), Error>.detached(priority: .userInitiated) {
                    var urls: [URL] = []
                    var before: Int64 = 0
                    var after: Int64 = 0
                    for u in list {
                        before += Files.size(u) ?? 0
                        let cg = try ImageOps.readCG(u)
                        let base = ToolFS.base(u)
                        let dst: URL
                        switch m {
                        case .size:
                            dst = try ImageOps.write(ImageOps.resize(cg, longSide: ls), like: u, base: base + "-\(ls)px")
                        case .compress:
                            guard let d = ImageOps.jpegUnder(ImageOps.resize(cg, longSide: 4096), maxKB: kb) else { throw Convert.err("压缩失败") }
                            let tag = kb >= 1024 ? String(kb / 1024) + "MB" : String(kb) + "KB"
                            dst = ToolFS.out(base + "-" + tag, "jpg")
                            try d.write(to: dst)
                        case .rotate:
                            let out = ImageOps.rotate(cg, degrees: rt <= 270 ? rt : 0, flipH: rt == 1, flipV: rt == 2)
                            dst = try ImageOps.write(out, like: u, base: base + "-调整")
                        case .crop:
                            let w = Double(cg.width), h = Double(cg.height)
                            var cw = w, ch = w / rr
                            if ch > h { ch = h; cw = h * rr }
                            guard let c = ImageOps.crop(cg, x: (w - cw) / 2 / w, y: (h - ch) / 2 / h, w: cw / w, h: ch / h) else { throw Convert.err("裁剪失败") }
                            dst = try ImageOps.write(c, like: u, base: base + "-裁剪")
                        case .strip:
                            dst = try ImageOps.write(cg, like: u, base: base + "-已清除隐私", quality: 0.95)
                        }
                        after += Files.size(dst) ?? 0
                        urls.append(dst)
                    }
                    let a = ByteCountFormatter.string(fromByteCount: before, countStyle: .file)
                    let b = ByteCountFormatter.string(fromByteCount: after, countStyle: .file)
                    return (urls, "\(a) → \(b)")
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
