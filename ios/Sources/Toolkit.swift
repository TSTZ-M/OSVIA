import SwiftUI
import PhotosUI
import PDFKit
import Vision
import Translation
import NaturalLanguage
import WebKit
import ImageIO
import UniformTypeIdentifiers

// MARK: 图片文字识别（带位置）
extension OCR {
    struct Line {
        let text: String
        let box: CGRect   // 归一化，原点在左上角
    }

    // 按图片方向转正后取 CGImage，长边不超过 maxPixel
    static func cg(_ url: URL, maxPixel: Int = 4096) -> CGImage? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return UIImage(contentsOfFile: url.path)?.cgImage }
        var limit = maxPixel
        if let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
           let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            limit = min(maxPixel, max(w, h))
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        return CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary) ?? UIImage(contentsOfFile: url.path)?.cgImage
    }

    static func lines(_ image: CGImage) -> [Line] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([req])
        return (req.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first else { return nil }
            let b = o.boundingBox
            return Line(text: c.string, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
    }

    static func text(_ image: CGImage) -> String {
        lines(image).map { $0.text }.joined(separator: "\n")
    }

    static func fullText(_ url: URL) -> String {
        guard let img = cg(url) else { return "" }
        return text(img)
    }
}

// MARK: 翻译目标语言：设置里选了就用选的；自动时，外语译成系统语言，系统语言译成英文
enum TransTarget {
    static func pick(for text: String) -> String {
        let sel = UserDefaults.standard.string(forKey: "transTarget") ?? "auto"
        if sel != "auto" { return sel }
        let l = Locale.current.language
        let sys = l.languageCode?.identifier ?? "en"
        let sysID = sys == "zh" ? "zh-" + (l.script?.identifier ?? "Hans") : sys
        let rec = NLLanguageRecognizer()
        rec.processString(String(text.prefix(2000)))
        let dom = rec.dominantLanguage?.rawValue ?? ""
        if dom.hasPrefix(sys) { return sys == "en" ? "zh-Hans" : "en" }
        return sysID
    }
}

// MARK: 相册选择 / 存相册
enum MediaPick {
    static func load(_ item: PhotosPickerItem) async -> (url: URL?, error: String) {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            do {
                if let m = try await item.loadTransferable(type: PickedMovie.self) { return (m.url, "") }
                return (nil, "视频读取失败，请换一个再试")
            } catch {
                return (nil, "视频读取失败：\(error.localizedDescription)")
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return (nil, "图片读取失败，请换一张再试") }
            let stamp = Files.stampText()
            if let ext = ConvertView.imageExt(data) {
                let s = Files.save(data, name: "照片-\(stamp).\(ext)")
                return (s.url, s.url == nil ? "图片保存失败（\(s.error)）" : "")
            }
            if let j = Files.jpegData(fromImageData: data) {
                let s = Files.save(j, name: "照片-\(stamp).jpg")
                return (s.url, s.url == nil ? "图片保存失败（\(s.error)）" : "")
            }
            return (nil, "这张图片的格式无法识别")
        } catch {
            return (nil, "图片读取失败：\(error.localizedDescription)")
        }
    }
}

enum PhotoSave {
    static func save(_ u: URL) {
        if let img = UIImage(contentsOfFile: u.path) {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        } else if Convert.vidExt.contains(u.pathExtension.lowercased()) {
            UISaveVideoAtPathToSavedPhotosAlbum(u.path, nil, nil, nil)
        }
    }
}

// MARK: 文字导出成文件
enum TextExport {
    static func file(_ text: String, base: String, ext: String) async throws -> URL {
        var b = base.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|\n")).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if b.isEmpty { b = "文字" }
        let dst = Convert.out(String(b.prefix(30)), ext)
        switch ext {
        case "docx": try Office.docx(text).write(to: dst)
        case "html": try MD.pre(text).write(to: dst, atomically: true, encoding: .utf8)
        case "pdf": try await MainActor.run { try Convert.textPDF(text, dst) }
        default: try text.write(to: dst, atomically: true, encoding: .utf8)
        }
        return dst
    }
}

// MARK: 网页正文：先用普通请求，读不到（页面靠脚本渲染）再用网页引擎渲染后取文字
@MainActor
final class WebRender: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var cont: CheckedContinuation<(String, String), Never>?

    static func text(_ url: URL) async -> (String, String) {
        let r = WebRender()
        return await r.load(url)
    }

    private func load(_ url: URL) async -> (String, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(String, String), Never>) in
            cont = c
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            w.customUserAgent = Web.ua
            w.navigationDelegate = self
            web = w
            w.load(URLRequest(url: url, timeoutInterval: 15))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 22_000_000_000)
                self?.finish("", "")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            let js = "(document.querySelector('article')||document.querySelector('main')||document.body).innerText"
            let t = (try? await webView.evaluateJavaScript(js)) as? String ?? ""
            finish(webView.title ?? "", t)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish("", "") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish("", "") }

    private func finish(_ title: String, _ text: String) {
        guard let c = cont else { return }
        cont = nil
        web?.stopLoading()
        web = nil
        c.resume(returning: (title, text))
    }
}

enum WebText {
    static func extract(_ url: URL, limit: Int = 200_000) async -> (title: String, text: String) {
        let r = await Web.read(url, limit: limit)
        if r.text.count >= 300 { return r }
        let js = await WebRender.text(url)
        let cleaned = js.1.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > r.text.count { return (js.0.isEmpty ? r.title : js.0, String(cleaned.prefix(limit))) }
        return r
    }

    static func parse(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let u = Agent.firstURL(in: t) { return u }
        if !t.contains(" "), t.contains("."), let u = URL(string: "https://" + t), u.host != nil { return u }
        return nil
    }
}

// MARK: 文字结果面板：复制、翻译、导出、存知识库、交给 AI 总结
struct ResultTextPanel: View {
    let title: String
    let text: String
    @State private var tConfig: TranslationSession.Configuration?
    @State private var translated = ""
    @State private var translating = false
    @State private var note = ""
    @State private var outFile: URL?
    @State private var preview: URL?
    @State private var copied = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.f("提取结果 · {} 字", "\(text.count)")).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Spacer()
            }
            ScrollView {
                Text(verbatim: String(text.prefix(30_000))).font(.system(size: 15)).foregroundStyle(Brand.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            .padding(12)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            actions

            if translating { HStack(spacing: 8) { ProgressView(); Text("正在翻译…").font(.subheadline).foregroundStyle(Brand.sub) } }
            if !translated.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("译文").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { copy(translated, "译文") } label: { Label(copied == "译文" ? "已复制" : "复制译文", systemImage: "doc.on.doc").font(.subheadline) }
                        Menu {
                            Button { export(translated, "txt", suffix: "译文") } label: { Text("文本 .txt") }
                            Button { export(translated, "docx", suffix: "译文") } label: { Text("Word .docx") }
                            Button { export(translated, "pdf", suffix: "译文") } label: { Text("PDF") }
                        } label: { Image(systemName: "square.and.arrow.up") }
                    }
                    ScrollView {
                        Text(verbatim: translated).font(.system(size: 15)).foregroundStyle(Brand.ink)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 280)
                }
                .padding(12)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let f = outFile {
                HStack(spacing: 10) {
                    FileCard(url: f, preview: $preview)
                    ShareLink(item: f) { Label("分享", systemImage: "square.and.arrow.up").font(.subheadline) }.buttonStyle(.bordered)
                }
            }
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(Brand.sub) }
        }
        .quickLookPreview($preview)
        .translationTask(tConfig) { session in await translate(session) }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(copied == "原文" ? "已复制" : "复制", "doc.on.doc") { copy(text, "原文") }
                pill("翻译", "character.bubble") { startTranslate() }
                Menu {
                    Button { export(text, "txt") } label: { Text("文本 .txt") }
                    Button { export(text, "md") } label: { Text("Markdown .md") }
                    Button { export(text, "docx") } label: { Text("Word .docx") }
                    Button { export(text, "pdf") } label: { Text("PDF") }
                    Button { export(text, "html") } label: { Text("网页 .html") }
                } label: { pillLabel("导出", "square.and.arrow.up") }
                pill("存入知识库", "books.vertical") {
                    KB.shared.upsert(String(title.prefix(40)).isEmpty ? "提取内容" : String(title.prefix(40)), text)
                    note = "已存入知识库，之后可以直接问我这里面的内容。"
                }
                pill("让 AI 总结", "sparkles") {
                    let t = text
                    AppState.shared.tool = nil
                    AppState.shared.page = nil
                    Agent.shared.start("请总结下面这段内容的要点：\n\n" + String(t.prefix(6000)))
                }
            }
        }
    }

    private func pillLabel(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.subheadline).foregroundStyle(Brand.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Brand.userBubble).clipShape(Capsule())
    }

    private func pill(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(t, icon) }
    }

    private func copy(_ s: String, _ tag: String) {
        UIPasteboard.general.string = s
        copied = tag
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copied == tag { copied = "" }
        }
    }

    private func export(_ s: String, _ ext: String, suffix: String = "") {
        Task {
            do { outFile = try await TextExport.file(s, base: title + (suffix.isEmpty ? "" : "-" + suffix), ext: ext); note = "" }
            catch { note = "导出失败：" + error.localizedDescription }
        }
    }

    private func startTranslate() {
        translating = true
        translated = ""
        note = ""
        let new = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: TransTarget.pick(for: text)))
        if tConfig == new { tConfig?.invalidate() } else { tConfig = new }
    }

    private func translate(_ session: TranslationSession) async {
        let paras = text.components(separatedBy: "\n")
        let reqs = paras.enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(400)
            .map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        do {
            let rs = try await session.translations(from: Array(reqs))
            var map: [Int: String] = [:]
            for r in rs {
                if let id = r.clientIdentifier, let i = Int(id) { map[i] = r.targetText }
            }
            translated = paras.enumerated().map { map[$0.offset] ?? $0.element }.joined(separator: "\n")
            if paras.count > 400 { note = "内容较长，只翻译了前 400 段。" }
        } catch {
            note = "翻译失败：" + error.localizedDescription
        }
        translating = false
    }
}

// MARK: 一键提取网页文字
struct WebExtractView: View {
    @State private var urlText: String
    @State private var loading = false
    @State private var title = ""
    @State private var text = ""
    @State private var err = ""
    @FocusState private var focus: Bool

    init(initial: String = "") { _urlText = State(initialValue: initial) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TextField("粘贴网址或带网址的文字", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus)
                        .onSubmit { go() }
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(Brand.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    PasteButton(payloadType: String.self) { s in
                        if let v = s.first { urlText = v; go() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
                Button { go() } label: {
                    HStack { if loading { ProgressView() }; Text(loading ? "正在读取…" : "提取正文").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(loading || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                if !text.isEmpty {
                    Text(verbatim: title).font(.headline).foregroundStyle(Brand.ink)
                    ResultTextPanel(title: title, text: text)
                } else if !loading {
                    Text("去掉广告、导航和脚本，只留正文。需要脚本渲染的页面会自动用网页引擎再读一次。读不到的多半是需要登录的页面。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("网页文字提取")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if !urlText.isEmpty && text.isEmpty && !loading { go() } }
    }

    private func go() {
        guard !loading else { return }
        guard let u = WebText.parse(urlText) else { err = "没有找到有效的网址"; return }
        focus = false
        loading = true
        err = ""
        text = ""
        title = ""
        Task {
            let r = await WebText.extract(u)
            loading = false
            if r.text.isEmpty {
                err = "没有读到正文（可能需要登录、被网站拦截，或页面只有图片）"
            } else {
                title = r.title.isEmpty ? (u.host ?? "网页") : r.title
                text = r.text
            }
        }
    }
}

// MARK: 提取图片文字（可翻译、导出）
struct OCRView: View {
    @State private var urls: [URL]
    @State private var text = ""
    @State private var busy = false
    @State private var err = ""
    @State private var showPhotos = false
    @State private var showFile = false
    @State private var showCamera = false
    @State private var items: [PhotosPickerItem] = []
    @State private var ran = false

    init(initial: [URL] = []) { _urls = State(initialValue: initial) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    source("photo.on.rectangle", "相册") { showPhotos = true }
                    source("camera", "拍照") { showCamera = true }
                    source("folder", "文件") { showFile = true }
                    source("doc.on.clipboard", "剪贴板") { pasteImage() }
                }
                if !urls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(urls, id: \.self) { u in
                                Group {
                                    if let ui = Files.thumb(u, max: 220) { Image(uiImage: ui).resizable().scaledToFill() } else { Color.gray.opacity(0.2) }
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                if busy { HStack(spacing: 8) { ProgressView(); Text("正在识别…").font(.subheadline).foregroundStyle(Brand.sub) } }
                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                if !text.isEmpty {
                    ResultTextPanel(title: "图片文字", text: text)
                    Button {
                        translateInPlace()
                    } label: { Label("翻译并把译文贴回原图", systemImage: "photo.badge.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                } else if urls.isEmpty {
                    Text("选一张或几张图片，本机识别中、英、日、韩等文字，不上传。结果可以复制、翻译、导出成 Word 或 PDF。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("图片文字提取")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotos, selection: $items, maxSelectionCount: 9, matching: .images)
        .onChange(of: items) { _, v in
            guard !v.isEmpty else { return }
            items = []
            Task {
                var add: [URL] = []
                for it in v {
                    let r = await MediaPick.load(it)
                    if let u = r.url { add.append(u) } else if !r.error.isEmpty { err = r.error }
                }
                setImages(add)
            }
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { r in
            guard let picked = try? r.get() else { return }
            var add: [URL] = []
            for u in picked {
                let res = Files.importFile(u)
                if let c = res.url { add.append(c) } else if let e = res.error { err = e }
            }
            setImages(add)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { u, e in
                showCamera = false
                if let u { setImages([u]) } else if let e { err = e }
            }
            .ignoresSafeArea()
        }
        .task {
            if !ran && !urls.isEmpty { ran = true; await recognize() }
        }
    }

    private func source(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Brand.mint)
                Text(label).font(.system(size: 12.5)).foregroundStyle(Brand.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func pasteImage() {
        guard UIPasteboard.general.hasImages, let img = UIPasteboard.general.image, let d = Files.jpeg(from: img) else { err = "剪贴板里没有图片"; return }
        let s = Files.save(d, name: "粘贴图片-\(Files.stampText()).jpg")
        if let u = s.url { setImages([u]) } else { err = "保存失败（\(s.error)）" }
    }

    private func setImages(_ add: [URL]) {
        guard !add.isEmpty else { return }
        urls = add
        text = ""
        err = ""
        Task { await recognize() }
    }

    private func recognize() async {
        busy = true
        err = ""
        let list = urls
        let parts: [String] = await Task.detached(priority: .userInitiated) {
            list.map { u -> String in
                if u.pathExtension.lowercased() == "pdf" {
                    return PDFTextOCR.text(u)
                }
                return OCR.fullText(u)
            }
        }.value
        var out: [String] = []
        for (i, p) in parts.enumerated() {
            let s = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            out.append(parts.count > 1 ? L10n.f("第 {} 张：", "\(i + 1)") + "\n" + s : s)
        }
        text = out.joined(separator: "\n\n")
        if text.isEmpty { err = "没有识别到文字，换一张更清晰的图试试" }
        busy = false
    }

    private func translateInPlace() {
        guard let u = urls.first(where: { Files.isImage($0) }), let d = Files.normalizedJPEG(from: u, maxPixel: 3000) else { return }
        AppState.shared.tool = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ScreenTranslator.shared.request(data: d)
        }
    }
}

enum PDFTextOCR {
    // 同步版本：PDF 的文字层，没有就逐页识别（最多 30 页）
    static func text(_ u: URL) -> String {
        guard let doc = PDFDocument(url: u) else { return "" }
        let direct = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if direct.count >= 30 { return direct }
        var parts: [String] = []
        for i in 0..<min(doc.pageCount, 30) {
            guard let p = doc.page(at: i) else { continue }
            let sz = p.bounds(for: .mediaBox).size
            let k = 2000 / max(sz.width, sz.height, 1)
            let img = p.thumbnail(of: CGSize(width: sz.width * k, height: sz.height * k), for: .mediaBox)
            if let cg = img.cgImage {
                let s = OCR.text(cg)
                if !s.isEmpty { parts.append(s) }
            }
        }
        let t = parts.joined(separator: "\n\n")
        return t.isEmpty ? direct : t
    }
}

// MARK: 工具入口：工具箱卡片、「+」托盘、聊天快捷操作共用
enum ToolKind: String, Identifiable, CaseIterable {
    case web, ocr, translateImage, convert, wmImage, wmVideo, audio, mute
    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "网页文字"
        case .ocr: return "识别文字"
        case .translateImage: return "翻译图片"
        case .convert: return "格式转换"
        case .wmImage: return "图片去水印"
        case .wmVideo: return "视频去水印"
        case .audio: return "提取音频"
        case .mute: return "视频去声音"
        }
    }

    var blurb: String {
        switch self {
        case .web: return "粘贴网址，一键取出正文，可翻译、导出"
        case .ocr: return "识别图片里的文字，支持多张、PDF 扫描件"
        case .translateImage: return "把图里的文字翻成你的语言并贴回原位"
        case .convert: return "Word、Excel、PDF、图片、表格、视频互相转换"
        case .wmImage: return "框出水印，本机一键去除"
        case .wmVideo: return "逐帧去除固定位置的水印，声音保留"
        case .audio: return "从视频里取出声音，存成 m4a 或 wav"
        case .mute: return "去掉视频里的声音，画质无损"
        }
    }

    var icon: String {
        switch self {
        case .web: return "globe"
        case .ocr: return "text.viewfinder"
        case .translateImage: return "character.bubble"
        case .convert: return "arrow.triangle.2.circlepath"
        case .wmImage: return "wand.and.stars"
        case .wmVideo: return "film"
        case .audio: return "waveform"
        case .mute: return "speaker.slash"
        }
    }

    @ViewBuilder
    func destination(files: [URL] = [], text: String = "") -> some View {
        switch self {
        case .web: WebExtractView(initial: text)
        case .ocr: OCRView(initial: files.filter { Files.isImage($0) || $0.pathExtension.lowercased() == "pdf" })
        case .translateImage: ScreenTranslateView(title: "翻译图片")
        case .convert: ConvertView(initial: files.first)
        case .wmImage: WatermarkView(video: false, initial: files.first(where: { Files.isImage($0) }))
        case .wmVideo: WatermarkView(video: true, initial: files.first(where: { Convert.vidExt.contains($0.pathExtension.lowercased()) }))
        case .audio: ConvertView(initial: files.first, preset: "m4a", title: "提取音频", videosOnly: true)
        case .mute: ConvertView(initial: files.first, preset: "mute", title: "视频去声音", videosOnly: true)
        }
    }
}

struct ToolRequest: Identifiable {
    let id = UUID()
    let kind: ToolKind
    var files: [URL] = []
    var text = ""
}

struct ToolSheet: View {
    let req: ToolRequest

    var body: some View {
        NavigationStack { req.kind.destination(files: req.files, text: req.text) }
            .environment(\.isPageRoot, true)
            .background(Brand.page.ignoresSafeArea())
            .presentationBackground(Brand.page)
    }
}

// MARK: 对话里调用的动手工具（云端大脑与本地大模型共用）
@MainActor
enum Toolkit {
    static func doc() -> String {
        var s = ""
        s += "- extract_web {\"url\":\"网址\",\"save\":false}：提取网页正文（去掉广告导航，脚本渲染的页面也能读）。用户要「提取网页文字」「把这篇文章拿下来」时用；save 为 true 时同时存成 Markdown 文件附在回复下方\n"
        s += "- convert {\"name\":\"文件名（工作区或刚发来的文件，留空=最近一个）\",\"to\":\"目标格式\"}：文件格式互转，结果附在回复下方。图片→jpg png heic pdf txt docx compress；PDF→docx txt md rtf html png jpg（扫描件自动识别文字）；Word/文本/网页→docx pdf txt md html rtf xlsx；表格 csv json xlsx→csv json xlsx md html pdf txt；视频→mp4 mov m4a(提取音频) wav mute(去掉声音) compress jpg；音频→m4a wav caf\n"
        s += "- remove_watermark {\"name\":\"图片或视频文件名\",\"x\":0.7,\"y\":0.9,\"w\":0.28,\"h\":0.08}：本机去水印。x y w h 是水印区域占整张画面的比例（左上角为原点，0~1）；{\"auto_text\":true} 自动识别图片边缘的文字水印（只用于图片）。适合位置固定、背景简单的水印\n"
        s += "- translate_image {\"name\":\"可选，图片文件名；留空=剪贴板里的图\"}：把图片里的文字翻译成目标语言并贴回原位（会打开「翻译图片」页面）。只想要文字译文时，先用 ocr 再自己翻译\n"
        return s
    }

    static func run(_ c: ToolCall, trace: Tracer) async -> ToolResult? {
        switch c.name {
        case "extract_web": return await extractWeb(c.args, trace)
        case "convert": return await convert(c.args, trace)
        case "remove_watermark": return await watermark(c.args, trace)
        case "translate_image": return translateImage(c.args)
        default: return nil
        }
    }

    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func num(_ a: [String: Any], _ k: String) -> Double? {
        if let n = a[k] as? NSNumber { return n.doubleValue }
        return Double(str(a, k))
    }

    // 找文件：工作区 → 收件箱 → 输出 → 最近发来的文件
    static func file(_ name: String) -> URL? {
        let fm = FileManager.default
        if name.isEmpty { return Agent.shared.lastFile ?? Agent.shared.attachments.last?.url }
        if let u = Hands.workspaceURL(name) { return u }
        let n = (name as NSString).lastPathComponent
        let dirs = [Store.dir("Inbox"), Store.dir("Outputs"), Hands.work]
        for d in dirs {
            let u = d.appendingPathComponent(n)
            if fm.fileExists(atPath: u.path) { return u }
        }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for d in dirs {
            let list = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            if let m = list.filter({ $0.lastPathComponent.localizedCaseInsensitiveContains(n) }).max(by: { date($0) < date($1) }) { return m }
        }
        if let l = Agent.shared.lastFile, l.lastPathComponent.localizedCaseInsensitiveContains(n) { return l }
        return nil
    }

    private static func attach(_ urls: [URL], _ trace: Tracer) {
        for u in urls { Agent.shared.mutate(trace.mid) { $0.files.append(u) } }
    }

    // MARK: 提取网页文字
    private static func extractWeb(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let url = WebText.parse(str(a, "url")) else { return ToolResult(text: "缺少有效的网址。", ok: false) }
        let sid = trace.begin(.read, "提取网页文字", url.host ?? url.absoluteString)
        let r = await WebText.extract(url, limit: 60_000)
        guard !r.text.isEmpty else {
            trace.end(sid, ok: false, detail: L10n.tr("没读到正文"))
            return ToolResult(text: "没有读到正文（可能需要登录或被网站拦截）。", ok: false)
        }
        trace.end(sid, detail: L10n.f("{} 字", "\(r.text.count)"))
        var out = (r.title.isEmpty ? "" : "标题：\(r.title)\n") + "正文（\(r.text.count) 字）：\n" + String(r.text.prefix(9000))
        if r.text.count > 9000 { out += "\n……（后面还有内容，已全部提取）" }
        if (a["save"] as? Bool) == true {
            let name = Hands.safeName((r.title.isEmpty ? (url.host ?? "网页") : String(r.title.prefix(30))) + ".md", defaultExt: "md")
            let u = Hands.uniqueURL(name)
            let md = (r.title.isEmpty ? "" : "# \(r.title)\n\n") + "来源：\(url.absoluteString)\n\n" + r.text
            if (try? md.write(to: u, atomically: true, encoding: .utf8)) != nil {
                attach([u], trace)
                out += "\n\n已存成「\(u.lastPathComponent)」，附在回复下方。"
            }
        }
        return ToolResult(text: out)
    }

    // MARK: 格式转换
    private static func convert(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let to = str(a, "to")
        guard !to.isEmpty else { return ToolResult(text: "需要 to（目标格式）。", ok: false) }
        guard let u = file(str(a, "name")) else { return ToolResult(text: "没有找到这个文件。请让用户先发送文件，或用工作区里的文件名。", ok: false) }
        let sid = trace.begin(.file, "转换文件", u.lastPathComponent + " → " + to)
        do {
            let outs = try await Convert.run(u, to: to)
            attach(outs, trace)
            trace.end(sid, detail: outs.map { $0.lastPathComponent }.joined(separator: "、"))
            return ToolResult(text: "已转换：" + outs.map { $0.lastPathComponent }.joined(separator: "、") + "，已附在回复下方，用户可预览、分享或存入相册。一句话说明即可。")
        } catch {
            trace.end(sid, ok: false, detail: String(error.localizedDescription.prefix(40)))
            return ToolResult(text: "转换失败：" + error.localizedDescription + "。\(u.pathExtension) 可转成：" + Convert.targets(for: u.pathExtension.lowercased()).joined(separator: "、"), ok: false)
        }
    }

    // MARK: 去水印
    private static func watermark(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        guard let u = file(str(a, "name")) else { return ToolResult(text: "没有找到这个文件。", ok: false) }
        let ext = u.pathExtension.lowercased()
        let isVid = Convert.vidExt.contains(ext)
        guard isVid || Files.isImage(u) else { return ToolResult(text: "只能处理图片和视频。", ok: false) }
        var rects: [CGRect] = []
        if let x = num(a, "x"), let y = num(a, "y"), let w = num(a, "w"), let h = num(a, "h"), w > 0, h > 0 {
            let r = CGRect(x: x, y: y, width: w, height: h).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            if !r.isNull && r.width > 0 && r.height > 0 { rects.append(r) }
        }
        if (a["auto_text"] as? Bool) == true, !isVid, let cg = OCR.cg(u, maxPixel: 2400) {
            let found = await Task.detached(priority: .userInitiated) { OCR.lines(cg) }.value
            let edge = found.map { $0.box }.filter { b in
                let cy = b.midY
                let cx = b.midX
                return cy < 0.16 || cy > 0.84 || cx < 0.1 || cx > 0.9
            }
            rects += edge.prefix(4).map { $0.insetBy(dx: -0.004, dy: -0.004) }
        }
        guard !rects.isEmpty else {
            return ToolResult(text: "需要水印的位置：用 x y w h（占整张画面的比例）指定，或对图片用 auto_text。也可以让用户打开「工具箱 → 去水印」手动框选。", ok: false)
        }
        let sid = trace.begin(.file, isVid ? "视频去水印" : "图片去水印", u.lastPathComponent)
        do {
            let out: URL
            if isVid {
                let last = Box()
                out = try await Delogo.video(u, regions: rects, progress: { p in
                    let pct = Int(p * 100)
                    guard pct >= last.v + 5 else { return }
                    last.v = pct
                    Task { @MainActor in trace.detail(sid, "\(pct)%") }
                }, cancel: Delogo.Cancel())
            } else {
                let rs = rects
                out = try await Task.detached(priority: .userInitiated) { try Delogo.image(u, regions: rs, smart: false) }.value
            }
            attach([out], trace)
            trace.end(sid, detail: out.lastPathComponent)
            return ToolResult(text: "已处理并附在回复下方。说明：这是本机填充，纯色或虚化背景效果好，复杂背景会留下痕迹；不满意可让用户到「工具箱 → 去水印」手动框选并开启「保留背景纹理」。")
        } catch {
            trace.end(sid, ok: false, detail: String(error.localizedDescription.prefix(40)))
            return ToolResult(text: "去水印失败：" + error.localizedDescription, ok: false)
        }
    }

    final class Box { var v = -100 }

    // MARK: 翻译图片
    private static func translateImage(_ a: [String: Any]) -> ToolResult {
        let name = str(a, "name")
        var data: Data?
        if name.isEmpty {
            if UIPasteboard.general.hasImages, let img = UIPasteboard.general.image { data = Files.jpeg(from: img, maxPixel: 3000) }
        } else if let u = file(name) {
            data = Files.normalizedJPEG(from: u, maxPixel: 3000)
        }
        guard let d = data else { return ToolResult(text: name.isEmpty ? "剪贴板里没有图片。" : "没有找到这张图片。", ok: false) }
        ScreenTranslator.shared.request(data: d)
        return ToolResult(text: "已打开「翻译图片」，识别并翻译完成后译文会贴回原图，用户可保存或分享。", final: true)
    }
}
