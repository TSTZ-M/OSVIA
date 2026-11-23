import SwiftUI
import Photos
import PhotosUI
import Vision
import Translation
import NaturalLanguage
import UIKit

// MARK: 屏幕翻译：识别截图里的文字，用系统翻译（离线可用、免费）翻成目标语言，并把译文贴回原来的位置。
struct TBlock: Identifiable {
    let id = UUID()
    let text: String
    let box: CGRect   // 归一化坐标，原点在左上角
    var out = ""
}

@MainActor
final class ScreenTranslator: ObservableObject {
    static let shared = ScreenTranslator()

    @Published var original: UIImage?
    @Published var result: UIImage?
    @Published var resultURL: URL?
    @Published var blocks: [TBlock] = []
    @Published var status = ""
    @Published var busy = false
    @Published var config: TranslationSession.Configuration?
    @Published var ticket = 0

    private var pending = false
    private var pendingData: Data?

    // 来自对话或快捷指令：打开页面并自动开始。data 为空时翻译相册里最新的一张截图
    func request(data: Data?) {
        pendingData = data
        pending = true
        AppState.shared.drawer = false
        AppState.shared.page = .translate
        ticket += 1
    }

    func runPending() {
        guard pending, !busy else { return }
        pending = false
        let d = pendingData
        pendingData = nil
        Task {
            if let d, let img = UIImage(data: d) { await process(img) } else { await loadLatestScreenshot() }
        }
    }

    func loadLatestScreenshot() async {
        guard !busy else { return }
        busy = true
        status = "正在读取最新截图…"
        let st = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard st == .authorized || st == .limited else {
            status = "没有照片权限：请到 设置 → \(Brand.name) → 照片，允许访问"
            busy = false
            return
        }
        let opt = PHFetchOptions()
        opt.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: opt).firstObject else {
            status = "相册里没有找到截图（如果只授权了部分照片，请改成允许访问全部照片）"
            busy = false
            return
        }
        guard let img = await Self.image(for: asset) else {
            status = "截图读取失败，请重试"
            busy = false
            return
        }
        busy = false
        await process(img)
    }

    func process(_ raw: UIImage) async {
        guard !busy else { return }
        busy = true
        result = nil
        resultURL = nil
        blocks = []
        status = "正在识别文字…"
        let img = Self.normalized(raw)
        original = img
        let found = await Task.detached(priority: .userInitiated) { Self.recognize(img) }.value
        guard !found.isEmpty else {
            result = img
            status = "没有识别到文字"
            busy = false
            return
        }
        blocks = found
        result = img
        status = "正在翻译…"
        startTranslation()
    }

    // 换了目标语言后，对已识别的文字重新翻译
    func retarget() {
        guard !blocks.isEmpty, !busy else { return }
        busy = true
        status = "正在翻译…"
        blocks = blocks.map { var b = $0; b.out = ""; return b }
        startTranslation()
    }

    private func startTranslation() {
        let all = blocks.map(\.text).joined(separator: " ")
        let new = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: targetLanguage(for: all)))
        if config == new { config?.invalidate() } else { config = new }
    }

    func run(_ session: TranslationSession) async {
        guard !blocks.isEmpty else { return }
        do {
            let reqs = blocks.enumerated().map { TranslationSession.Request(sourceText: $0.element.text, clientIdentifier: String($0.offset)) }
            let rs = try await session.translations(from: reqs)
            var nb = blocks
            for r in rs {
                if let id = r.clientIdentifier, let i = Int(id), i < nb.count { nb[i].out = r.targetText }
            }
            blocks = nb
            render()
            status = ""
        } catch {
            status = "翻译失败：" + error.localizedDescription
        }
        busy = false
    }

    // 目标语言：用户手动选了就用选的；自动时，外语译成系统语言，系统语言的文字译成英文
    private func targetLanguage(for text: String) -> String {
        let sel = UserDefaults.standard.string(forKey: "transTarget") ?? "auto"
        if sel != "auto" { return sel }
        let l = Locale.current.language
        let sys = l.languageCode?.identifier ?? "en"
        let sysID = sys == "zh" ? "zh-" + (l.script?.identifier ?? "Hans") : sys
        let rec = NLLanguageRecognizer()
        rec.processString(text)
        let dom = rec.dominantLanguage?.rawValue ?? ""
        if dom.hasPrefix(sys) { return sys == "en" ? "zh-Hans" : "en" }
        return sysID
    }

    // MARK: 渲染：把译文画回原图
    private func render() {
        guard let base = original, let cg = base.cgImage else { return }
        let size = base.size
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            base.draw(at: .zero)
            for b in blocks where !b.out.isEmpty {
                let r = CGRect(x: b.box.minX * size.width, y: b.box.minY * size.height,
                               width: b.box.width * size.width, height: b.box.height * size.height)
                let bg = Self.background(cg, r)
                let fg: UIColor = Self.luma(bg) > 0.55 ? .black : .white
                bg.setFill()
                ctx.cgContext.fill(r.insetBy(dx: -2, dy: -1))
                Self.draw(b.out, in: r, color: fg)
            }
        }
        result = img
        if let d = img.jpegData(compressionQuality: 0.9) {
            let u = Store.dir("Outputs").appendingPathComponent("屏幕翻译.jpg")
            try? d.write(to: u)
            resultURL = u
        }
    }

    nonisolated static func luma(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // 取文字框四个角的颜色平均值作为背景色（框中间有文字，不能直接取平均）
    nonisolated static func background(_ cg: CGImage, _ r: CGRect) -> UIColor {
        let pts = [(r.minX + 1, r.minY + 1), (r.maxX - 3, r.minY + 1), (r.minX + 1, r.maxY - 3), (r.maxX - 3, r.maxY - 3)]
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0
        for p in pts {
            let c = sample(cg, Int(p.0), Int(p.1))
            sr += c.0
            sg += c.1
            sb += c.2
        }
        let n = CGFloat(pts.count)
        return UIColor(red: sr / n, green: sg / n, blue: sb / n, alpha: 1)
    }

    nonisolated static func sample(_ cg: CGImage, _ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat) {
        let xx = min(max(x, 0), max(cg.width - 2, 0))
        let yy = min(max(y, 0), max(cg.height - 2, 0))
        guard let crop = cg.cropping(to: CGRect(x: xx, y: yy, width: 2, height: 2)) else { return (1, 1, 1) }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { buf in
            guard let c = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (CGFloat(px[0]) / 255, CGFloat(px[1]) / 255, CGFloat(px[2]) / 255)
    }

    // 文字放不下就逐步缩小字号
    nonisolated static func draw(_ s: String, in r: CGRect, color: UIColor) {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        var size = max(10, r.height * 0.82)
        var attr = NSAttributedString()
        while true {
            attr = NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium),
                                                              .foregroundColor: color, .paragraphStyle: ps])
            let need = attr.boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin], context: nil).height
            if need <= r.height * 1.15 || size <= 9 { break }
            size *= 0.9
        }
        attr.draw(with: r, options: [.usesLineFragmentOrigin], context: nil)
    }

    // MARK: 图片读取与文字识别
    nonisolated static func image(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            o.isSynchronous = false
            var done = false
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: o) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if done { return }
                done = true
                cont.resume(returning: img)
            }
        }
    }

    // 统一成正向、1 倍像素、最长边不超过 3000
    nonisolated static func normalized(_ img: UIImage) -> UIImage {
        let w = img.size.width * img.scale
        let h = img.size.height * img.scale
        let s = min(1, 3000 / max(w, h, 1))
        let size = CGSize(width: max(1, w * s), height: max(1, h * s))
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    nonisolated static func recognize(_ img: UIImage) -> [TBlock] {
        guard let cg = img.cgImage else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        var out: [TBlock] = []
        for o in req.results ?? [] {
            guard let c = o.topCandidates(1).first, c.confidence >= 0.3 else { continue }
            let t = c.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // 只翻译含有文字的行，纯数字和符号（时间、电量、页码）跳过
            guard t.count >= 1, t.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { continue }
            let b = o.boundingBox
            out.append(TBlock(text: t, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)))
        }
        return out.sorted { a, b in
            abs(a.box.minY - b.box.minY) > 0.004 ? a.box.minY < b.box.minY : a.box.minX < b.box.minX
        }
    }
}

struct ScreenTranslateView: View {
    let title: String
    @ObservedObject private var t = ScreenTranslator.shared
    @AppStorage("transTarget") private var target = "auto"
    @State private var item: PhotosPickerItem?

    private let langs: [(String, String)] = [("auto", "自动"), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")]

    init(title: String = "屏幕翻译") { self.title = title }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Button {
                    Task { await t.loadLatestScreenshot() }
                } label: {
                    Label("翻译最新截图", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(t.busy)

                PhotosPicker(selection: $item, matching: .images) {
                    Label("选择图片翻译", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(t.busy)

                Picker("译成", selection: $target) {
                    ForEach(langs, id: \.0) { l in Text(l.1).tag(l.0) }
                }
                .pickerStyle(.segmented)

                if !t.status.isEmpty {
                    HStack(spacing: 8) {
                        if t.busy { ProgressView() }
                        Text(t.status).font(.subheadline).foregroundStyle(Brand.sub)
                        Spacer(minLength: 0)
                    }
                }

                if let img = t.result {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 1))
                    if let u = t.resultURL {
                        ShareLink(item: u) { Label("分享 / 保存译图", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                }

                if t.blocks.contains(where: { !$0.out.isEmpty }) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("译文").font(.headline)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = t.blocks.map(\.out).filter { !$0.isEmpty }.joined(separator: "\n")
                            } label: { Label("复制全部", systemImage: "doc.on.doc").font(.subheadline) }
                        }
                        ForEach(t.blocks) { b in
                            if !b.out.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: b.out).textSelection(.enabled)
                                    Text(verbatim: b.text).font(.caption).foregroundStyle(Brand.sub)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(14)
                    .background(Brand.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("怎么用").font(.headline)
                    Text("1. 先截一张屏（侧边键 + 音量加），回到这里点「翻译最新截图」。\n2. 想一键完成：打开「快捷指令」新建一个，依次添加「截屏」和 \(Brand.name) 的「翻译屏幕」（把截屏结果传给它），再到 设置 → 辅助功能 → 触控 → 轻点背面，选这个快捷指令。以后轻点两下手机背面，就能翻译当前屏幕。\n3. 第一次翻译时，系统会提示下载语言包，下载后离线也能用。\n4. 只翻译图片里的文字，不会改动原来的截图。")
                        .font(.subheadline)
                        .foregroundStyle(Brand.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .translationTask(t.config) { session in await t.run(session) }
        .onAppear { t.runPending() }
        .onChange(of: t.ticket) { _, _ in t.runPending() }
        .onChange(of: target) { _, _ in t.retarget() }
        .onChange(of: item) { _, v in
            guard let v else { return }
            Task {
                if let d = try? await v.loadTransferable(type: Data.self), let img = UIImage(data: d) { await t.process(img) }
                item = nil
            }
        }
    }
}
