import SwiftUI
import AVFoundation
import AVKit
import Speech
import ImageIO
import UniformTypeIdentifiers

// MARK: 音视频处理：剪切、转 GIF、变速、截取画面、合并（全部在本机完成）
enum MediaOps {
    enum Op: String, CaseIterable, Identifiable {
        case trim, gif, speed, frame, merge
        var id: String { rawValue }

        var title: String {
            switch self {
            case .trim: return "剪切"
            case .gif: return "转 GIF"
            case .speed: return "变速"
            case .frame: return "截取画面"
            case .merge: return "合并"
            }
        }

        var hint: String {
            switch self {
            case .trim: return "拖动起点和终点，保留中间这一段（视频和音频都行，不重新编码，速度很快）"
            case .gif: return "从视频里截一小段做成 GIF，最长 10 秒"
            case .speed: return "整段加速或放慢，声音同步变化"
            case .frame: return "拖到想要的位置，存成一张高清图片"
            case .merge: return "按顺序把几段视频或几段音频接成一个（尺寸相同的视频效果最好）"
            }
        }

        static func parse(_ s: String) -> Op? {
            switch s.lowercased() {
            case "trim", "cut", "剪切", "剪辑": return .trim
            case "gif", "转gif", "转 gif": return .gif
            case "speed", "变速": return .speed
            case "frame", "截图", "截取画面", "截帧": return .frame
            case "merge", "concat", "合并": return .merge
            default: return nil
            }
        }
    }

    static func duration(_ u: URL) async -> Double {
        guard let d = try? await AVURLAsset(url: u).load(.duration) else { return 0 }
        let s = d.seconds
        return s.isFinite ? max(0, s) : 0
    }

    static func isVideo(_ u: URL) async -> Bool {
        guard let t = try? await AVURLAsset(url: u).loadTracks(withMediaType: .video) else { return false }
        return !t.isEmpty
    }

    static func clock(_ t: Double) -> String {
        let s = t.isFinite ? max(0, min(t, 359_999)) : 0
        let m = Int(s) / 60
        let r = s - Double(m * 60)
        return String(format: "%d:%04.1f", m, r)
    }

    private static func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    // MARK: 剪切
    static func trim(_ u: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: u)
        let dur = try await asset.load(.duration).seconds
        let s = max(0, min(start, dur))
        let e = min(max(end, s + 0.1), dur)
        guard e - s >= 0.1 else { throw Convert.err("剪切范围不正确") }
        let video = await isVideo(u)
        guard let ses = AVAssetExportSession(asset: asset, presetName: video ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A) else { throw Convert.err("无法创建导出任务") }
        ses.timeRange = CMTimeRange(start: time(s), end: time(e))
        let mov = u.pathExtension.lowercased() == "mov"
        let ext = video ? (mov ? "mov" : "mp4") : "m4a"
        let dst = ToolFS.out(ToolFS.base(u) + "-剪切", ext)
        try await ses.export(to: dst, as: video ? (mov ? .mov : .mp4) : .m4a)
        return dst
    }

    // MARK: 变速
    static func speed(_ u: URL, factor: Double) async throws -> URL {
        guard factor > 0.1, factor <= 8 else { throw Convert.err("倍速需要在 0.1 到 8 之间") }
        let asset = AVURLAsset(url: u)
        let dur = try await asset.load(.duration)
        let full = CMTimeRange(start: .zero, duration: dur)
        let comp = AVMutableComposition()
        var video = false
        for type in [AVMediaType.video, AVMediaType.audio] {
            guard let src = try await asset.loadTracks(withMediaType: type).first,
                  let dstTrack = comp.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try dstTrack.insertTimeRange(full, of: src, at: .zero)
            if type == .video {
                video = true
                dstTrack.preferredTransform = try await src.load(.preferredTransform)
            }
        }
        guard (try await comp.load(.tracks)).count > 0 else { throw Convert.err("没有找到可处理的画面或声音") }
        comp.scaleTimeRange(full, toDuration: CMTime(seconds: dur.seconds / factor, preferredTimescale: 600))
        guard let ses = AVAssetExportSession(asset: comp, presetName: video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A) else { throw Convert.err("无法创建导出任务") }
        ses.audioTimePitchAlgorithm = .spectral
        let tag = String(format: "%g", factor) + "x"
        let dst = ToolFS.out(ToolFS.base(u) + "-" + tag, video ? "mp4" : "m4a")
        try await ses.export(to: dst, as: video ? .mp4 : .m4a)
        return dst
    }

    // MARK: 合并
    static func concat(_ urls: [URL]) async throws -> URL {
        guard urls.count >= 2 else { throw Convert.err("请至少选两个文件") }
        let comp = AVMutableComposition()
        var vt: AVMutableCompositionTrack?
        var at: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for u in urls {
            let a = AVURLAsset(url: u)
            let d = try await a.load(.duration)
            let r = CMTimeRange(start: .zero, duration: d)
            if let v = try await a.loadTracks(withMediaType: .video).first {
                if vt == nil {
                    vt = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    vt?.preferredTransform = try await v.load(.preferredTransform)
                }
                try vt?.insertTimeRange(r, of: v, at: cursor)
            }
            if let s = try await a.loadTracks(withMediaType: .audio).first {
                if at == nil { at = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                try at?.insertTimeRange(r, of: s, at: cursor)
            }
            cursor = cursor + d
        }
        let video = vt != nil
        guard video || at != nil else { throw Convert.err("没有找到可合并的内容") }
        guard let ses = AVAssetExportSession(asset: comp, presetName: video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A) else { throw Convert.err("无法创建导出任务") }
        let dst = ToolFS.out("合并-" + ToolFS.base(urls[0]), video ? "mp4" : "m4a")
        try await ses.export(to: dst, as: video ? .mp4 : .m4a)
        return dst
    }

    // MARK: 截取画面
    static func frame(_ u: URL, at t: Double) async throws -> URL {
        let asset = AVURLAsset(url: u)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw Convert.err("这个文件没有画面") }
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        let dur = try await asset.load(.duration).seconds
        let (cg, _) = try await g.image(at: time(max(0, min(t, max(0, dur - 0.05)))))
        guard let d = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { throw Convert.err("生成图片失败") }
        let dst = ToolFS.out(ToolFS.base(u) + "-" + clock(t).replacingOccurrences(of: ":", with: "分"), "jpg")
        try d.write(to: dst)
        return dst
    }

    // MARK: 转 GIF
    static func gif(_ u: URL, start: Double, length: Double, width: CGFloat) async throws -> URL {
        let asset = AVURLAsset(url: u)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw Convert.err("这个文件没有画面") }
        let dur = try await asset.load(.duration).seconds
        let s = max(0, min(start, max(0, dur - 0.5)))
        let len = max(0.5, min(length, 10, dur - s))
        let fps = 10
        let n = max(1, min(Int(len * Double(fps)), 100))
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: width, height: width)
        g.requestedTimeToleranceBefore = time(0.05)
        g.requestedTimeToleranceAfter = time(0.05)
        let dst = ToolFS.out(ToolFS.base(u), "gif")
        guard let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw Convert.err("无法创建 GIF") }
        let loop: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, loop as CFDictionary)
        let each: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]]
        for i in 0..<n {
            let (cg, _) = try await g.image(at: time(s + Double(i) / Double(fps)))
            CGImageDestinationAddImage(dest, cg, each as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw Convert.err("GIF 生成失败") }
        return dst
    }

    static func perform(_ op: Op, files: [URL], start: Double, end: Double, length: Double, factor: Double, at: Double, width: CGFloat) async throws -> URL {
        guard let first = files.first else { throw Convert.err("请先选择文件") }
        switch op {
        case .trim: return try await trim(first, start: start, end: end)
        case .gif: return try await gif(first, start: start, length: length, width: width)
        case .speed: return try await speed(first, factor: factor)
        case .frame: return try await frame(first, at: at)
        case .merge: return try await concat(files)
        }
    }
}

// MARK: 语音转文字：本机识别，长录音自动分段，同时生成 SRT 字幕
enum Transcribe {
    struct Lang: Identifiable {
        let name: String
        let id: String
    }

    static let languages: [Lang] = [
        Lang(name: "跟随系统语言", id: ""), Lang(name: "中文（普通话）", id: "zh-CN"), Lang(name: "English", id: "en-US"), Lang(name: "日本語", id: "ja-JP"),
        Lang(name: "한국어", id: "ko-KR"), Lang(name: "粤语", id: "yue-CN"), Lang(name: "Español", id: "es-ES"), Lang(name: "Français", id: "fr-FR"), Lang(name: "Deutsch", id: "de-DE")
    ]

    struct Output {
        var text: String
        var srt: String
    }

    private struct Seg {
        var text: String
        var start: Double
        var end: Double
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    private static func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("osvia-\(UUID().uuidString).\(ext)")
    }

    // 导出一段（或整段）为 m4a 临时文件
    private static func exportAudio(_ asset: AVURLAsset, from: Double?, to: Double?) async throws -> URL {
        guard let ses = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw Convert.err("无法读取音频") }
        if let f = from, let t = to {
            ses.timeRange = CMTimeRange(start: CMTime(seconds: f, preferredTimescale: 600), end: CMTime(seconds: t, preferredTimescale: 600))
        }
        let dst = tempURL("m4a")
        try await ses.export(to: dst, as: .m4a)
        return dst
    }

    private final class TaskBox { var task: SFSpeechRecognitionTask? }

    private static func recognize(_ rec: SFSpeechRecognizer, _ url: URL, onDevice: Bool) async throws -> SFTranscription? {
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        req.addsPunctuation = true
        if onDevice { req.requiresOnDeviceRecognition = true }
        let box = TaskBox()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<SFTranscription?, Error>) in
            var finished = false
            box.task = rec.recognitionTask(with: req) { res, err in
                if finished { return }
                if let res, res.isFinal {
                    finished = true
                    c.resume(returning: res.bestTranscription)
                } else if let err {
                    finished = true
                    let ns = err as NSError
                    // 这一段没有人声：当作空白继续
                    if ns.code == 1110 || ns.code == 203 || ns.localizedDescription.lowercased().contains("no speech") {
                        c.resume(returning: nil)
                    } else {
                        c.resume(throwing: err)
                    }
                }
            }
        }
    }

    static func run(_ src: URL, locale id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> Output {
        guard await authorize() else { throw Convert.err("请在 设置 → OSVIA 里允许语音识别") }
        let loc = id.isEmpty ? L10n.locale : Locale(identifier: id)
        guard let rec = SFSpeechRecognizer(locale: loc) else { throw Convert.err("系统不支持这种语言的语音识别") }
        guard rec.isAvailable else { throw Convert.err("语音识别暂时不可用，请检查网络后重试") }
        let onDevice = rec.supportsOnDeviceRecognition

        let asset = AVURLAsset(url: src)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw Convert.err("这个文件里没有声音") }
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0 else { throw Convert.err("无法读取时长") }

        // 在线识别每段不能超过约 1 分钟；本机识别分得长一些
        let chunk: Double = onDevice ? 120 : 50
        let count = max(1, Int((total / chunk).rounded(.up)))
        var segs: [Seg] = []
        var paragraphs: [String] = []
        var temps: [URL] = []
        defer { for t in temps { try? FileManager.default.removeItem(at: t) } }

        for i in 0..<count {
            try Task.checkCancellation()
            let from = Double(i) * chunk
            let to = min(total, from + chunk)
            let part: URL
            if count == 1 && ["m4a", "mp3", "wav", "caf", "aac", "aiff"].contains(src.pathExtension.lowercased()) {
                part = src
            } else {
                part = try await exportAudio(asset, from: count == 1 ? nil : from, to: count == 1 ? nil : to)
                temps.append(part)
            }
            if let tr = try await recognize(rec, part, onDevice: onDevice) {
                let text = tr.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { paragraphs.append(text) }
                for s in tr.segments {
                    segs.append(Seg(text: s.substring, start: from + s.timestamp, end: from + s.timestamp + s.duration))
                }
            }
            progress(Double(i + 1) / Double(count))
        }
        guard !paragraphs.isEmpty else { throw Convert.err("没有识别到说话内容。请确认语言选对了，声音够清晰") }
        let lang = loc.language.languageCode?.identifier ?? ""
        let cjk = ["zh", "ja", "yue"].contains(lang)
        return Output(text: paragraphs.joined(separator: "\n\n"), srt: srt(segs, cjk: cjk))
    }

    private static func stamp(_ t: Double) -> String {
        let ms = t.isFinite ? Int((min(max(0, t), 359_999) * 1000).rounded()) : 0
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    // 按停顿、标点和长度切成字幕行
    private static func srt(_ segs: [Seg], cjk: Bool) -> String {
        let maxLen = cjk ? 22 : 48
        var lines: [Seg] = []
        var cur: Seg?
        func flush() { if let c = cur, !c.text.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(c) }; cur = nil }
        for s in segs {
            if var c = cur {
                let gap = s.start - c.end
                if gap > 1.0 || c.text.count >= maxLen {
                    flush()
                    cur = s
                } else {
                    c.text += (cjk ? "" : " ") + s.text
                    c.end = s.end
                    cur = c
                }
            } else {
                cur = s
            }
            if let c = cur, let last = c.text.last, "。！？.!?".contains(last) { flush() }
        }
        flush()
        var out = ""
        for (i, l) in lines.enumerated() {
            out += "\(i + 1)\n\(stamp(l.start)) --> \(stamp(max(l.end, l.start + 0.4)))\n\(l.text.trimmingCharacters(in: .whitespaces))\n\n"
        }
        return out
    }
}

// MARK: 界面：音视频剪辑
struct MediaToolView: View {
    @State private var op: MediaOps.Op
    @State private var files: [URL]
    @State private var dur: Double = 0
    @State private var hasVideo = false
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var gifLen: Double = 4
    @State private var gifWidth: Double = 480
    @State private var factor: Double = 2
    @State private var at: Double = 0
    @State private var player: AVPlayer?
    @State private var out: URL?
    @State private var err = ""
    @State private var busy = false

    init(initial: [URL] = [], op: MediaOps.Op = .trim) {
        _op = State(initialValue: op)
        _files = State(initialValue: initial.filter { Convert.vidExt.contains($0.pathExtension.lowercased()) || Convert.audExt.contains($0.pathExtension.lowercased()) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    ForEach(MediaOps.Op.allCases) { o in
                        Button { op = o; out = nil; err = "" } label: { Label(o.title, systemImage: op == o ? "checkmark" : "film") }
                    }
                } label: {
                    HStack {
                        Text(op.title).fontSz(17, weight: .semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").fontSz(12).foregroundStyle(Brand.sub)
                    }
                    .foregroundStyle(Brand.ink)
                    .padding(14)
                    .background(Brand.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(op.hint).font(.footnote).foregroundStyle(Brand.sub)

                PickSources(types: [.movie, .audio], allowVideo: true, camera: false, paste: false, multiple: op == .merge) { urls in
                    out = nil
                    err = ""
                    if op == .merge { files += urls } else { files = Array(urls.prefix(1)) }
                    Task { await load() }
                } onError: { err = $0 }

                if op != .merge, hasVideo, let p = player {
                    VideoPlayer(player: p)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !files.isEmpty { fileList }
                if op != .merge && dur > 0 { controls }
                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                Button { run() } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "处理中…" : "开始").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || files.isEmpty || (op == .merge && files.count < 2))
                if let o = out { OutputList(urls: [o]) }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("音视频剪辑")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        guard op != .merge, let u = files.first else { return }
        dur = await MediaOps.duration(u)
        hasVideo = await MediaOps.isVideo(u)
        start = 0
        end = dur
        at = 0
        player = hasVideo ? AVPlayer(url: u) : nil
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.offset) { i, u in
                HStack(spacing: 10) {
                    Image(systemName: Convert.vidExt.contains(u.pathExtension.lowercased()) ? "film" : "waveform").foregroundStyle(Brand.mint)
                    Text(u.lastPathComponent).font(.subheadline).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if op == .merge && files.count > 1 {
                        Button { if i > 0 { files.swapAt(i, i - 1) } } label: { Image(systemName: "arrow.up").frame(minWidth: 30, minHeight: 30) }
                            .disabled(i == 0)
                            .accessibilityLabel("上移")
                        Button { if i < files.count - 1 { files.swapAt(i, i + 1) } } label: { Image(systemName: "arrow.down").frame(minWidth: 30, minHeight: 30) }
                            .disabled(i == files.count - 1)
                            .accessibilityLabel("下移")
                    }
                    Button { files.remove(at: i); if op != .merge { dur = 0; player = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.sub).frame(minWidth: 30, minHeight: 30) }
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

    @ViewBuilder private var controls: some View {
        switch op {
        case .trim:
            slider("起点", value: $start, upper: dur) { if start > end { end = start } }
            slider("终点", value: $end, upper: dur) { if end < start { start = end } }
            Text(L10n.f("保留 {}", MediaOps.clock(max(0, end - start)))).font(.footnote).foregroundStyle(Brand.sub)
        case .gif:
            slider("起点", value: $start, upper: dur) {}
            Picker("时长", selection: $gifLen) {
                Text("2 秒").tag(2.0)
                Text("4 秒").tag(4.0)
                Text("6 秒").tag(6.0)
                Text("10 秒").tag(10.0)
            }
            .pickerStyle(.segmented)
            Picker("宽度", selection: $gifWidth) {
                Text("320").tag(320.0)
                Text("480").tag(480.0)
                Text("640").tag(640.0)
            }
            .pickerStyle(.segmented)
        case .speed:
            Picker("倍速", selection: $factor) {
                Text("0.5×").tag(0.5)
                Text("1.5×").tag(1.5)
                Text("2×").tag(2.0)
                Text("3×").tag(3.0)
            }
            .pickerStyle(.segmented)
        case .frame:
            slider("位置", value: $at, upper: dur) { player?.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        case .merge:
            EmptyView()
        }
    }

    private func slider(_ title: String, value: Binding<Double>, upper: Double, changed: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Brand.sub)
                Spacer()
                Text(verbatim: MediaOps.clock(value.wrappedValue)).font(.footnote.monospacedDigit()).foregroundStyle(Brand.ink)
            }
            Slider(value: value, in: 0...max(upper, 0.1))
                .onChange(of: value.wrappedValue) { _, _ in changed() }
        }
        .padding(12)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func run() {
        busy = true
        err = ""
        out = nil
        player?.pause()
        let op = self.op, files = self.files, s = start, e = end, len = gifLen, f = factor, t = at, w = CGFloat(gifWidth)
        Task {
            do {
                out = try await MediaOps.perform(op, files: files, start: s, end: e, length: len, factor: f, at: t, width: w)
            } catch {
                err = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: 界面：音视频转文字 / 字幕
struct TranscribeView: View {
    @State private var file: URL?
    @State private var lang = ""
    @State private var text = ""
    @State private var outs: [URL] = []
    @State private var progress: Double = 0
    @State private var busy = false
    @State private var err = ""
    @State private var job: Task<Void, Never>?

    init(initial: URL? = nil) { _file = State(initialValue: initial) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PickSources(types: [.audio, .movie], allowVideo: true, camera: false, paste: false) { urls in
                    file = urls.first
                    text = ""
                    outs = []
                    err = ""
                } onError: { err = $0 }

                if let f = file {
                    HStack(spacing: 10) {
                        Image(systemName: Convert.vidExt.contains(f.pathExtension.lowercased()) ? "film" : "waveform").foregroundStyle(Brand.mint)
                        Text(f.lastPathComponent).font(.subheadline).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Brand.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("把会议录音、课程视频、语音留言转成文字，同时生成 SRT 字幕。普通话、英语等支持本机识别，不上传；部分语言需要联网。").font(.footnote).foregroundStyle(Brand.sub)
                }

                Picker("语言", selection: $lang) {
                    ForEach(Transcribe.languages) { l in Text(l.name).tag(l.id) }
                }
                .pickerStyle(.menu)

                if busy {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text("正在识别…长录音会分段处理，请保持 App 在前台").font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                if busy {
                    Button(role: .cancel) { job?.cancel() } label: { Text("取消").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    Button { run() } label: { Text("开始转文字").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(file == nil)
                }

                if !text.isEmpty { ResultTextPanel(title: "转写结果", text: text) }
                if !outs.isEmpty { OutputList(urls: outs) }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle("转文字与字幕")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        guard let f = file else { return }
        busy = true
        progress = 0
        err = ""
        text = ""
        outs = []
        let id = lang
        job = Task {
            do {
                let r = try await Transcribe.run(f, locale: id) { p in Task { @MainActor in progress = p } }
                text = r.text
                let base = ToolFS.base(f)
                let t = ToolFS.out(base + "-文字", "txt")
                try r.text.write(to: t, atomically: true, encoding: .utf8)
                let s = ToolFS.out(base, "srt")
                try r.srt.write(to: s, atomically: true, encoding: .utf8)
                outs = [t, s]
            } catch is CancellationError {
                err = "已取消"
            } catch {
                err = error.localizedDescription
            }
            busy = false
            job = nil
        }
    }
}
