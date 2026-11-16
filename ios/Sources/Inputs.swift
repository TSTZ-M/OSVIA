import Foundation
import UIKit
import Speech
import AVFoundation
import Vision

// 语音输入：边说边出文字，结束后自动填入输入框；聆听时灵动岛显示「聆听中」。
// 语音识别语言跟随应用当前语言。
final class Voice: ObservableObject {
    @Published var listening = false
    @Published var live = ""
    @Published var level: CGFloat = 0
    @Published var error = ""
    var onText: ((String) -> Void)?
    var onFinished: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var req: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var final = ""
    private var limit: Timer?
    private var done = false

    func toggle() { listening ? stop() : start() }

    func start() {
        error = ""
        let rec = SFSpeechRecognizer(locale: L10n.locale)
        recognizer = rec
        guard let rec, rec.isAvailable else {
            error = "语音识别暂时不可用，请检查网络，或在 设置 → 通用 → 键盘 里开启听写"
            return
        }
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { self.error = "请在 设置 → \(Brand.name) 里允许语音识别"; return }
                AVAudioApplication.requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        guard ok else { self.error = "请在 设置 → \(Brand.name) 里允许麦克风"; return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        do {
            final = ""
            live = ""
            done = false
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.record, mode: .measurement, options: .duckOthers)
            try s.setActive(true, options: .notifyOthersOnDeactivation)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.requiresOnDeviceRecognition = false
            req = r
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            // 麦克风被电话或其他 App 占用时采样率是 0，直接装 tap 会抛出系统异常、闪退
            let fmt = input.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
                throw NSError(domain: "osvia.voice", code: 1, userInfo: [NSLocalizedDescriptionKey: "麦克风暂时不可用，可能正被电话或其他 App 占用"])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] b, _ in
                r.append(b)
                guard let ch = b.floatChannelData?[0] else { return }
                let n = Int(b.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = (sum / Float(max(n, 1))).squareRoot()
                DispatchQueue.main.async { self?.level = CGFloat(min(rms * 14, 1)) }
            }
            engine.prepare()
            try engine.start()
            listening = true
            Live.listening(true)
            limit?.invalidate()
            limit = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.stop() }
            task = recognizer?.recognitionTask(with: r) { [weak self] res, err in
                DispatchQueue.main.async {
                    guard let self, !self.done else { return }
                    if let res {
                        self.final = res.bestTranscription.formattedString
                        self.live = self.final
                        self.onText?(self.final)
                    }
                    if res?.isFinal == true {
                        self.finish()
                    } else if err != nil {
                        if self.final.isEmpty { self.error = "没有听清，请靠近一点再说一次" }
                        self.finish()
                    }
                }
            }
        } catch {
            listening = false
            Live.listening(false)
            self.error = L10n.f("无法启动麦克风：{}", error.localizedDescription)
        }
    }

    func stop() {
        guard listening else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        req?.endAudio()
        listening = false
        level = 0
        limit?.invalidate()
        // 等待识别给出最终结果，最多 2.5 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard !done else { return }
        done = true
        task?.cancel()
        task = nil
        req = nil
        listening = false
        level = 0
        limit?.invalidate()
        Live.listening(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if final.isEmpty && error.isEmpty { error = "没有听到声音，请再试一次" }
        onFinished?(final)
    }
}

// 图片文字识别与类别识别（端侧 Vision）
enum OCR {
    static func text(_ url: URL) -> String {
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static let names: [String: String] = [
        "text": "文字", "document": "文档", "screenshot": "截图", "graphic": "图形", "logo": "标志", "poster": "海报",
        "illustration": "插画", "drawing": "绘图", "people": "人物", "person": "人物", "portrait": "人像", "adult": "人物",
        "food": "食物", "animal": "动物", "dog": "狗", "cat": "猫", "plant": "植物", "flower": "花", "sky": "天空",
        "outdoor": "户外", "indoor": "室内", "building": "建筑", "car": "汽车", "vehicle": "车辆", "water": "水景",
        "mountain": "山", "beach": "海滩", "night": "夜景", "computer": "电脑", "electronics": "电子产品", "phone": "手机",
        "furniture": "家具", "clothing": "服饰", "book": "书籍", "table": "桌子", "sign": "标牌", "paper": "纸张"
    ]

    static func labels(_ url: URL) -> [String] {
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { return [] }
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        var out: [String] = []
        for o in req.results ?? [] where o.confidence > 0.2 {
            if let n = names[o.identifier], !out.contains(n) { out.append(n) }
            if out.count >= 4 { break }
        }
        return out
    }
}

// 用户授权的文件夹（iOS 只允许读取授权过的位置）
final class Folders: ObservableObject {
    static let shared = Folders()
    @Published var names: [String] = []
    private var urls: [URL] = []

    init() { reload() }

    func reload() {
        let arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        urls = arr.compactMap { d in
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            _ = u.startAccessingSecurityScopedResource()
            return u
        }
        names = urls.map { $0.lastPathComponent }
    }

    func add(_ u: URL) {
        _ = u.startAccessingSecurityScopedResource()
        guard let d = try? u.bookmarkData() else { return }
        var arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        arr.append(d)
        UserDefaults.standard.set(arr, forKey: "folders")
        reload()
    }

    func remove(at i: Int) {
        var arr = UserDefaults.standard.array(forKey: "folders") as? [Data] ?? []
        guard i < arr.count else { return }
        arr.remove(at: i)
        UserDefaults.standard.set(arr, forKey: "folders")
        reload()
    }

    func find(_ kw: String) -> [URL] {
        var out: [URL] = []
        let roots = urls + [Store.dir("Inbox"), Store.dir("Outputs")]
        for root in roots {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let f as URL in en where f.lastPathComponent.localizedCaseInsensitiveContains(kw) {
                out.append(f)
                if out.count >= 15 { return out }
            }
        }
        return out
    }
}
