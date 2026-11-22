import AppIntents
import Foundation
import UniformTypeIdentifiers

// 这些动作出现在系统「快捷指令」App 里：和别的 App、自动化串起来用
// 例如：截屏 → 识别文字 → 存进备忘录；相册新增照片 → 压缩 → 上传；扫描件 → 转 PDF → 发邮件
enum IntentIO {
    // 快捷指令传进来的文件落成临时文件（处理库都按文件地址工作）
    static func stage(_ f: IntentFile, ext: String = "") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("osvia-intent-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var name = f.filename
        let typeExt = f.type?.preferredFilenameExtension ?? ""
        let fallback = typeExt.isEmpty ? ext : typeExt
        if name.isEmpty { name = "文件" + (fallback.isEmpty ? "" : "." + fallback) }
        else if URL(fileURLWithPath: name).pathExtension.isEmpty, !fallback.isEmpty { name += "." + fallback }
        let u = dir.appendingPathComponent(name)
        try f.data.write(to: u)
        return u
    }

    static func cleanup(_ u: URL) { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) }

    // 读出结果后删掉输出目录里的文件，免得自动化反复运行把空间占满
    static func result(_ u: URL) throws -> IntentFile {
        let d = try Data(contentsOf: u)
        let type = UTType(filenameExtension: u.pathExtension) ?? .data
        try? FileManager.default.removeItem(at: u)
        return IntentFile(data: d, filename: u.lastPathComponent, type: type)
    }
}

struct OCRImageIntent: AppIntent {
    static let title: LocalizedStringResource = "识别图片文字"
    static let description = IntentDescription("识别图片里的文字（中文、英文、日文、韩文），在本机完成，不上传")
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let u = try IntentIO.stage(image, ext: "jpg")
        defer { IntentIO.cleanup(u) }
        return .result(value: OCR.fullText(u))
    }
}

struct WebTextIntent: AppIntent {
    static let title: LocalizedStringResource = "提取网页文字"
    static let description = IntentDescription("提取网页正文，去掉广告和导航")
    @Parameter(title: "网址") var url: URL

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let r = await WebText.extract(url)
        let text = r.title.isEmpty ? r.text : r.title + "\n\n" + r.text
        return .result(value: text)
    }
}

struct CompressImageIntent: AppIntent {
    static let title: LocalizedStringResource = "压缩图片到指定大小"
    static let description = IntentDescription("把图片压缩到不超过指定的 KB，输出 JPG")
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile
    @Parameter(title: "最大体积（KB）", default: 500) var maxKB: Int

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let u = try IntentIO.stage(image, ext: "jpg")
        defer { IntentIO.cleanup(u) }
        let cg = try ImageOps.readCG(u)
        guard let d = ImageOps.jpegUnder(ImageOps.resize(cg, longSide: 4096), maxKB: min(102400, max(20, maxKB))) else { throw Convert.err("压缩失败") }
        return .result(value: IntentFile(data: d, filename: ToolFS.base(u) + "-压缩.jpg", type: .jpeg))
    }
}

struct MergePDFIntent: AppIntent {
    static let title: LocalizedStringResource = "合并为 PDF"
    static let description = IntentDescription("把多个 PDF 或图片按顺序合成一个 PDF")
    @Parameter(title: "文件", supportedContentTypes: [.pdf, .image]) var files: [IntentFile]

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        var urls: [URL] = []
        defer { for u in urls { IntentIO.cleanup(u) } }
        for f in files { urls.append(try IntentIO.stage(f, ext: f.type?.conforms(to: .pdf) == true ? "pdf" : "jpg")) }
        let out = try PDFOps.merge(urls)
        return .result(value: try IntentIO.result(out))
    }
}

enum CutoutBG: String, AppEnum {
    case clear, white, blue, red

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "背景")
    static let caseDisplayRepresentations: [CutoutBG: DisplayRepresentation] = [
        .clear: DisplayRepresentation(title: "透明"),
        .white: DisplayRepresentation(title: "白底"),
        .blue: DisplayRepresentation(title: "蓝底"),
        .red: DisplayRepresentation(title: "红底")
    ]
}

struct RemoveBackgroundIntent: AppIntent {
    static let title: LocalizedStringResource = "抠图换底色"
    static let description = IntentDescription("识别图片里的主体并去掉背景，可换成证件照常用的底色")
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile
    @Parameter(title: "背景", default: .clear) var background: CutoutBG

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let u = try IntentIO.stage(image, ext: "jpg")
        defer { IntentIO.cleanup(u) }
        let out = try Cutout.run(u, bg: Cutout.Background.parse(background.rawValue), crop: false)
        return .result(value: try IntentIO.result(out))
    }
}

struct RedactImageIntent: AppIntent {
    static let title: LocalizedStringResource = "图片自动打码"
    static let description = IntentDescription("自动给图里的手机号、身份证号、银行卡号、邮箱、车牌和人脸打马赛克，并清除拍摄位置")
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let u = try IntentIO.stage(image, ext: "jpg")
        defer { IntentIO.cleanup(u) }
        let r = try Redact.run(u, kinds: [.phone, .idcard, .bank, .email, .plate, .face], style: .mosaic)
        return .result(value: try IntentIO.result(r.0))
    }
}

struct ReadQRIntent: AppIntent {
    static let title: LocalizedStringResource = "读取二维码"
    static let description = IntentDescription("读出图片里的二维码和条形码内容")
    @Parameter(title: "图片", supportedContentTypes: [.image]) var image: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let u = try IntentIO.stage(image, ext: "jpg")
        defer { IntentIO.cleanup(u) }
        return .result(value: Barcode.scan(u).map { $0.text })
    }
}

struct ConvertFileIntent: AppIntent {
    static let title: LocalizedStringResource = "转换文件格式"
    static let description = IntentDescription("Word、Excel、PDF、图片、表格、音视频等互相转换，例如 pdf、docx、xlsx、jpg、png、txt、md、m4a")
    @Parameter(title: "文件") var file: IntentFile
    @Parameter(title: "目标格式", description: "如 pdf、docx、xlsx、jpg、png、txt、md、html、csv、m4a、mp4") var target: String

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let u = try IntentIO.stage(file)
        defer { IntentIO.cleanup(u) }
        let outs = try await Convert.run(u, to: target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard let first = outs.first else { throw Convert.err("转换没有产生文件") }
        let f = try IntentIO.result(first)
        for extra in outs.dropFirst() { try? FileManager.default.removeItem(at: extra) }
        return .result(value: f)
    }
}

struct TranscribeIntent: AppIntent {
    static let title: LocalizedStringResource = "录音或视频转文字"
    static let description = IntentDescription("把录音、语音备忘录、视频里的说话转成文字（首次需要先在 App 里允许语音识别）")
    @Parameter(title: "音频或视频", supportedContentTypes: [.audio, .movie]) var file: IntentFile
    @Parameter(title: "语言代码", description: "留空=系统语言；如 zh-CN、en-US、ja-JP") var language: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let u = try IntentIO.stage(file, ext: "m4a")
        defer { IntentIO.cleanup(u) }
        let r = try await Transcribe.run(u, locale: language ?? "") { _ in }
        return .result(value: r.text)
    }
}
