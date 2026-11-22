import SwiftUI
import PhotosUI
import QuickLook
import ImageIO
import UniformTypeIdentifiers

// 相册里的视频：系统选择器给出的临时文件复制进 Inbox
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in
            SentTransferredFile(m.url)
        } importing: { received in
            let e = received.file.pathExtension.lowercased()
            let ext = e.isEmpty ? "mov" : e
            let dst = Store.dir("Inbox").appendingPathComponent("视频-\(Files.stampText()).\(ext)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

// MARK: 文件转换：可以从相册选照片或视频，也可以从「文件」App 选
struct ConvertView: View {
    let initial: URL?
    let preset: String
    let title: String
    let videosOnly: Bool
    @State private var file: URL?
    @State private var showPick = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loading = false
    @State private var target = ""
    @State private var outs: [URL] = []
    @State private var busy = false
    @State private var err = ""
    @State private var preview: URL?

    init(initial: URL? = nil, preset: String = "", title: String = "文件转换", videosOnly: Bool = false) {
        self.initial = initial
        self.preset = preset
        self.title = title
        self.videosOnly = videosOnly
    }

    static let names: [String: String] = [
        "jpg": "JPG 图片", "png": "PNG 图片", "heic": "HEIC 图片", "pdf": "PDF", "tiff": "TIFF 图片", "gif": "GIF 图片", "bmp": "BMP 图片",
        "txt": "文字 TXT", "csv": "CSV 表格", "json": "JSON", "md": "Markdown", "html": "网页 HTML", "tsv": "TSV 表格",
        "docx": "Word 文档", "xlsx": "Excel 表格", "rtf": "RTF 文档",
        "mp4": "MP4 视频", "mov": "MOV 视频", "m4a": "M4A 音频", "wav": "WAV 音频", "caf": "CAF 音频", "mute": "去除声音", "compress": "压缩"
    ]

    // 聊天里快捷按钮的短名
    static let short: [String: String] = [
        "docx": "Word", "xlsx": "Excel", "pdf": "PDF", "txt": "文字", "md": "Markdown", "html": "网页", "rtf": "RTF", "csv": "CSV",
        "json": "JSON", "png": "PNG", "jpg": "JPG", "heic": "HEIC", "tiff": "TIFF", "gif": "GIF", "bmp": "BMP", "tsv": "TSV",
        "mp4": "MP4", "mov": "MOV", "m4a": "音频", "wav": "WAV", "caf": "CAF"
    ]

    var targets: [String] {
        guard let f = file else { return [] }
        return Convert.targets(for: f.pathExtension.lowercased())
    }

    var body: some View {
        List {
            Section {
                Button { showPhotos = true } label: { Label(videosOnly ? "从相册选择视频" : "从相册选择照片或视频", systemImage: "photo.on.rectangle") }
                Button { showPick = true } label: { Label("从「文件」App 选择", systemImage: "folder") }
                if loading {
                    HStack(spacing: 8) { ProgressView(); Text("正在读取…").foregroundStyle(.secondary) }
                } else if let f = file {
                    Label("已选择：" + f.lastPathComponent, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            if !targets.isEmpty {
                Section("转换成") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(targets, id: \.self) { t in
                            Button { target = t } label: {
                                Text(Self.names[t] ?? t).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(target == t ? Brand.accent : Color(.tertiarySystemFill))
                                    .foregroundStyle(target == t ? Brand.onAccent : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    Button { convert() } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "转换中…" : "开始转换").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || target.isEmpty)
                    .listRowBackground(Color.clear)
                }
            }
            if !err.isEmpty { Section { Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            if !outs.isEmpty {
                Section("转换结果") {
                    ForEach(outs, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 8) {
                            FileCard(url: u, preview: $preview)
                            HStack(spacing: 16) {
                                if Convert.imgExt.contains(u.pathExtension.lowercased()) || Convert.vidExt.contains(u.pathExtension.lowercased()) {
                                    Button("存入相册") { saveToPhotos(u) }
                                }
                                ShareLink(item: u) { Text("分享") }
                            }
                            .buttonStyle(.borderless)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
            Section {
                Text(videosOnly ? "视频不会上传，全部在手机上处理。" : "支持图片、PDF、Word、Excel、表格、网页、文本、视频、音频互相转换，也能识别图片和扫描件里的文字。全部在手机上处理，不上传。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task { if let u = initial, file == nil { setFile(u) } }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 1, matching: videosOnly ? PHPickerFilter.videos : PHPickerFilter.any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard let it = items.first else { return }
            photoItems = []
            Task { await loadPicked(it) }
        }
        .fileImporter(isPresented: $showPick, allowedContentTypes: [.item]) { r in
            guard let u = try? r.get() else { return }
            Task { @MainActor in
                let res = await Files.importFileAsync(u)
                if let c = res.url { setFile(c) } else { err = res.error ?? "文件读取失败" }
            }
        }
    }

    func setFile(_ u: URL) {
        file = u
        outs = []
        err = ""
        target = targets.contains(preset) ? preset : (targets.first ?? "")
    }

    // 相册选中的照片或视频 → 落地成文件
    func loadPicked(_ item: PhotosPickerItem) async {
        loading = true
        err = ""
        defer { loading = false }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            do {
                if let m = try await item.loadTransferable(type: PickedMovie.self) { setFile(m.url) } else { err = "视频读取失败，请换一个再试" }
            } catch {
                err = "视频读取失败：\(error.localizedDescription)"
            }
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { err = "图片读取失败，请换一张再试"; return }
            let stamp = Files.stampText()
            if let ext = Self.imageExt(data) {
                let s = Files.save(data, name: "照片-\(stamp).\(ext)")
                if let u = s.url { setFile(u) } else { err = "图片保存失败（\(s.error)）" }
            } else if let j = Files.jpegData(fromImageData: data) {
                let s = Files.save(j, name: "照片-\(stamp).jpg")
                if let u = s.url { setFile(u) } else { err = "图片保存失败（\(s.error)）" }
            } else {
                err = "这张图片的格式无法识别"
            }
        } catch {
            err = "图片读取失败：\(error.localizedDescription)"
        }
    }

    // 按内容判断格式；不在支持列表里返回 nil（会改存为 JPEG）
    static func imageExt(_ data: Data) -> String? {
        guard let s = CGImageSourceCreateWithData(data as CFData, nil),
              let t = CGImageSourceGetType(s),
              let ut = UTType(t as String),
              let e = ut.preferredFilenameExtension else { return nil }
        let x = e.lowercased() == "jpeg" ? "jpg" : e.lowercased()
        return Convert.imgExt.contains(x) ? x : nil
    }

    func convert() {
        guard let f = file else { return }
        busy = true
        err = ""
        Task {
            do { outs = try await Convert.run(f, to: target) } catch { err = error.localizedDescription }
            busy = false
        }
    }

    func saveToPhotos(_ u: URL) {
        if let img = UIImage(contentsOfFile: u.path) { UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil) }
        else if Convert.vidExt.contains(u.pathExtension.lowercased()) { UISaveVideoAtPathToSavedPhotosAlbum(u.path, nil, nil, nil) }
    }
}
