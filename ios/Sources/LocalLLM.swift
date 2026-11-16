import Foundation
import SwiftUI
import UIKit
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: 本地大模型（MLX）：把开源大模型下载到手机，完全离线、免费运行。
// 下载走国内可用的镜像 hf-mirror.com，失败时改用 huggingface.co。

struct LocalModel: Identifiable, Hashable {
    let id: String        // Hugging Face 仓库名
    let name: String
    let gb: String
    let note: String
}

enum LocalLLMError: LocalizedError {
    case notInstalled
    case noFiles
    case http(Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return L10n.tr("本地模型还没下载，请先到 设置 → 本地大模型 下载。")
        case .noFiles: return L10n.tr("没有找到模型文件，请检查网络")
        case .http(let c): return "HTTP \(c)"
        case .other(let s): return s
        }
    }
}

// MARK: 分词器桥接（与官方 MLXHuggingFace 宏展开的代码相同，手工展开以免在 Xcode 里确认宏信任）
struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

struct TransformersLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

// MARK: 下载器：镜像优先，逐个文件下载，已下载完整的文件不重复下载；下载完成后写入标记，之后完全离线
struct MirrorDownloader: MLXLMCommon.Downloader {
    static let hosts = ["https://hf-mirror.com", "https://huggingface.co"]

    static func dir(for id: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalLLM", isDirectory: true)
        return base.appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    static func marker(for id: String) -> URL { dir(for: id).appendingPathComponent(".complete") }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Foundation.Progress) -> Void
    ) async throws -> URL {
        let dir = Self.dir(for: id)
        if !useLatest, FileManager.default.fileExists(atPath: Self.marker(for: id).path) { return dir }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rev = revision ?? "main"

        var files: [(name: String, size: Int64)] = []
        var host = ""
        var lastErr: Error = LocalLLMError.noFiles
        for h in Self.hosts {
            do {
                let list = try await Self.listFiles(host: h, id: id, rev: rev)
                if !list.isEmpty { files = list; host = h; break }
            } catch {
                lastErr = error
            }
        }
        guard !files.isEmpty else { throw lastErr }

        let wanted = files.filter { f in
            patterns.isEmpty || patterns.contains { fnmatch($0, f.name, 0) == 0 }
        }
        guard !wanted.isEmpty else { throw LocalLLMError.noFiles }

        let total = max(wanted.reduce(Int64(0)) { $0 + $1.size }, 1)
        let prog = Foundation.Progress(totalUnitCount: total)
        var done: Int64 = 0
        for f in wanted {
            try Task.checkCancellation()
            let dest = dir.appendingPathComponent(f.name)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if f.size > 0, let n = Files.size(dest), n == f.size {
                done += f.size
                prog.completedUnitCount = done
                progressHandler(prog)
                continue
            }
            let base = done
            try await Self.fetch(host: host, id: id, rev: rev, file: f.name, to: dest) { got in
                prog.completedUnitCount = min(base + got, total)
                progressHandler(prog)
            }
            done += (Files.size(dest) ?? f.size)
        }
        try Data().write(to: Self.marker(for: id))
        return dir
    }

    static func listFiles(host: String, id: String, rev: String) async throws -> [(name: String, size: Int64)] {
        guard let url = URL(string: "\(host)/api/models/\(id)/revision/\(rev)?blobs=true") else { throw LocalLLMError.noFiles }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw LocalLLMError.http(h.statusCode) }
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sib = j["siblings"] as? [[String: Any]] else { throw LocalLLMError.noFiles }
        return sib.compactMap { s in
            guard let n = s["rfilename"] as? String else { return nil }
            let size = (s["size"] as? NSNumber)?.int64Value ?? 0
            return (n, size)
        }
    }

    static func fetch(host: String, id: String, rev: String, file: String, to dest: URL, progress: @escaping (Int64) -> Void) async throws {
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        guard let url = URL(string: "\(host)/\(id)/resolve/\(rev)/\(encoded)") else { throw LocalLLMError.noFiles }
        var last: Error = LocalLLMError.noFiles
        for attempt in 1...3 {
            do {
                try await FileFetcher(dest: dest, progress: progress).run(url)
                return
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                last = error
                if attempt < 3 { try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        throw last
    }
}

final class FileFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let progress: (Int64) -> Void
    private var cont: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private let lock = NSLock()

    init(dest: URL, progress: @escaping (Int64) -> Void) {
        self.dest = dest
        self.progress = progress
    }

    func run(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                cont = c
                lock.unlock()
                let cfg = URLSessionConfiguration.default
                cfg.waitsForConnectivity = true
                cfg.timeoutIntervalForRequest = 60
                cfg.timeoutIntervalForResource = 60 * 60 * 3
                let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
                lock.lock()
                session = s
                lock.unlock()
                s.downloadTask(with: url).resume()
            }
        } onCancel: {
            self.lock.lock()
            let s = self.session
            self.lock.unlock()
            s?.invalidateAndCancel()
        }
    }

    private func finish(_ r: Result<Void, Error>) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        guard let c else { return }
        switch r {
        case .success: c.resume()
        case .failure(let e): c.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let h = downloadTask.response as? HTTPURLResponse, h.statusCode != 200 {
            finish(.failure(LocalLLMError.http(h.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

// MARK: 本地模型管理与推理
@MainActor
final class LocalLLM: ObservableObject {
    static let shared = LocalLLM()

    // 默认模型：Qwen3-4B-Instruct-2507（非思考版，指令遵循、中文、工具调用都明显强于旧版 Qwen3 4B 与 Qwen2.5 3B）
    static let defaultID = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    static let models: [LocalModel] = [
        LocalModel(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", name: "Qwen3 4B 2507", gb: "2.3", note: "推荐：目前手机上最聪明的一档，中文与指令遵循最强"),
        LocalModel(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen2.5 3B", gb: "1.8", note: "速度与质量均衡，占内存较少"),
        LocalModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen2.5 1.5B", gb: "0.9", note: "轻量，速度快，占内存少"),
        LocalModel(id: "droyster/Qwen3.5-4B-Text-MLX-4bit", name: "Qwen3.5 4B（新）", gb: "2.4", note: "新一代 Qwen3.5，推理与工具调用更强；社区转换的纯文本版，若加载失败请换回默认"),
        LocalModel(id: "augible/qwen3.5-2b-4bit-text-mlx", name: "Qwen3.5 2B（新）", gb: "1.1", note: "新一代小模型，比 Qwen2.5 1.5B 聪明且更省内存；社区转换的纯文本版"),
        LocalModel(id: "mlx-community/Qwen3-4B-4bit", name: "Qwen3 4B（旧）", gb: "2.3", note: "旧版混合思考模型，不再推荐")
    ]

    enum State: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var installed: Set<String> = []

    private var container: ModelContainer?
    private var loadedID = ""
    private var task: Task<Void, Never>?
    private var loadTask: Task<ModelContainer, Error>?

    // 同一时刻只允许一个生成任务；App 离开前台就中止（后台不允许提交 GPU 任务，硬撑会直接崩溃）
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var aborted = false

    init() {
        refresh()
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                Diag.mark("内存警告：卸载本地模型，余量 \(Safety.availableBytes() >> 20) MB")
                self?.aborted = true
                self?.unload()
            }
        }
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.aborted = true }
        }
        // 进后台就把模型从内存里卸掉：后台占着 2GB 多的 App 是系统最先杀的，回来就是「闪退」。下次提问再载入
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.aborted = true
                self?.unload()
            }
        }
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    var selectedID: String {
        get { UserDefaults.standard.string(forKey: "localModelID") ?? Self.defaultID }
        set { UserDefaults.standard.set(newValue, forKey: "localModelID") }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "localOn") as? Bool ?? true }

    var selectedName: String { Self.models.first { $0.id == selectedID }?.name ?? selectedID }

    // 载入这个模型大约要多少字节：权重 ×1.15（缓存、激活）+ 450MB（分词器、界面和系统开销）
    static func needBytes(_ id: String) -> Int {
        let gb = Double(models.first { $0.id == id }?.gb ?? "2.5") ?? 2.5
        return Int(gb * 1.15 * 1_073_741_824) + 450 * 1_048_576
    }

    // 内存够不够：已经载入的不用再算；真机拿不到余量时（返回 0）不拦
    func memoryEnough(_ id: String) -> Bool {
        if container != nil && loadedID == id { return true }
        let avail = Safety.availableBytes()
        return avail == 0 || avail >= Self.needBytes(id)
    }

    // 不能用本地模型的原因（空串 = 可以用或没有启用），显示在设置页
    var blockReason: String {
        guard enabled, isInstalled(selectedID) else { return "" }
        if Safety.safeMode { return "安全模式下已暂停本地模型。" }
        if Safety.localOff { return "上次运行时被系统终止，已自动停用本地模型。回到对话页点上方的「恢复」可重新启用。" }
        if !memoryEnough(selectedID) {
            return L10n.f("手机当前可用内存约 {} MB，载入这个模型约需 {} MB，现在改用系统自带模型。关闭其他 App 后再试，或换一个更小的模型。",
                          "\(Safety.availableBytes() >> 20)", "\(Self.needBytes(selectedID) >> 20)")
        }
        return ""
    }

    // 已下载、已选、已开启、内存够、没有被安全机制停用：Agent 就用它回答
    var canUse: Bool { enabled && Safety.localAllowed && isInstalled(selectedID) && memoryEnough(selectedID) }

    func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: MirrorDownloader.marker(for: id).path)
    }

    func refresh() {
        installed = Set(Self.models.map { $0.id }.filter { isInstalled($0) })
    }

    func unload() {
        container = nil
        loadedID = ""
        loadTask = nil
        if case .ready = state { state = .idle }
        Safety.trimMLX()
    }

    func select(_ id: String) {
        guard id != selectedID else { return }
        selectedID = id
        unload()
    }

    func delete(_ id: String) {
        if id == loadedID { unload() }
        try? FileManager.default.removeItem(at: MirrorDownloader.dir(for: id))
        refresh()
        state = .idle
    }

    func cancelDownload() {
        task?.cancel()
    }

    // 下载并载入（首次需要联网）
    func download(_ id: String) {
        guard task == nil else { return }
        selectedID = id
        unload()
        state = .downloading(0)
        task = Task {
            do {
                let progress: @Sendable (Foundation.Progress) -> Void = { p in
                    let f = p.fractionCompleted
                    Task { @MainActor in LocalLLM.shared.state = .downloading(f) }
                }
                if memoryEnough(id) {
                    Safety.tuneMLX()
                    Safety.begin()
                    defer { Safety.end() }
                    let c = try await LLMModelFactory.shared.loadContainer(
                        from: MirrorDownloader(),
                        using: TransformersLoader(),
                        configuration: ModelConfiguration(id: id),
                        progressHandler: progress)
                    container = c
                    loadedID = id
                    state = .ready
                } else {
                    // 手机现在的可用内存不够载入这个模型：只下载文件，不载入，避免下载完成的瞬间被系统杀掉
                    Diag.mark("内存不足以载入 \(id)，只下载不载入")
                    _ = try await MirrorDownloader().download(id: id, revision: nil, matching: [], useLatest: false, progressHandler: progress)
                    state = .idle
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    state = .idle
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
            refresh()
            task = nil
        }
    }

    // 确保模型已载入内存
    func ensureLoaded() async throws -> ModelContainer {
        let id = selectedID
        if let c = container, loadedID == id { return c }
        guard isInstalled(id) else { throw LocalLLMError.notInstalled }
        if let t = loadTask { return try await t.value }
        guard Safety.localAllowed else { throw LocalLLMError.other(L10n.tr("本地模型已被安全机制暂停。")) }
        guard memoryEnough(id) else {
            let msg = L10n.f("可用内存约 {} MB，载入这个模型约需 {} MB，不够。", "\(Safety.availableBytes() >> 20)", "\(Self.needBytes(id) >> 20)")
            Diag.mark("拒绝载入本地模型：" + msg)
            throw LocalLLMError.other(msg)
        }
        Diag.mark("载入本地模型 \(id)，内存余量 \(Safety.availableBytes() >> 20) MB，约需 \(Self.needBytes(id) >> 20) MB")
        Safety.tuneMLX()
        state = .loading
        let t = Task { () -> ModelContainer in
            try await LLMModelFactory.shared.loadContainer(
                from: MirrorDownloader(),
                using: TransformersLoader(),
                configuration: ModelConfiguration(id: id))
        }
        loadTask = t
        do {
            let c = try await t.value
            container = c
            loadedID = id
            loadTask = nil
            state = .ready
            return c
        } catch {
            loadTask = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    var isLoaded: Bool { container != nil && loadedID == selectedID }

    // 把 (role, text) 整理成合法的多轮消息：必须从用户开头、角色交替、末尾是助理（下一条才是本次的用户消息）；总量限制在约 3000 字
    nonisolated static func chatHistory(_ h: [(role: String, text: String)]) -> [MLXLMCommon.Chat.Message] {
        var out: [MLXLMCommon.Chat.Message] = []
        for m in h {
            let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let isUser = m.role == "user"
            if out.isEmpty && !isUser { continue }
            let r: MLXLMCommon.Chat.Message.Role = isUser ? .user : .assistant
            if let last = out.last, last.role == r {
                out[out.count - 1].content += "\n" + t
            } else {
                out.append(isUser ? .user(t) : .assistant(t))
            }
        }
        if let last = out.last, last.role == .user { out.removeLast() }
        var total = out.reduce(0) { $0 + $1.content.count }
        while total > 3000, out.count >= 2 {
            total -= out[0].content.count + out[1].content.count
            out.removeFirst(2)
        }
        return out
    }

    // 流式生成：history 是此前的多轮对话，prompt 是本次的用户消息
    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int = 800,
        temperature: Float = 0.4,
        history: [(role: String, text: String)] = [],
        onText: @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        guard UIApplication.shared.applicationState == .active else {
            Diag.mark("本地模型：App 不在前台，不生成")
            throw CancellationError()
        }
        await acquire()
        defer { release() }
        // 排队期间用户可能已经离开
        guard UIApplication.shared.applicationState == .active, !Task.isCancelled else { throw CancellationError() }
        aborted = false
        Diag.mark("本地模型生成开始")
        Safety.begin()
        defer {
            Safety.end()
            Safety.trimMLX()
            Diag.mark("本地模型生成结束，内存余量 \(Safety.availableBytes() >> 20) MB")
        }
        let c = try await ensureLoaded()
        if aborted {
            unload()
            throw CancellationError()
        }
        var gp = GenerateParameters()
        gp.maxTokens = maxTokens
        gp.temperature = temperature
        gp.topP = 0.8 // 官方推荐的采样范围，减少胡话与重复
        let session = ChatSession(
            c,
            instructions: instructions,
            history: Self.chatHistory(history),
            generateParameters: gp,
            additionalContext: ["enable_thinking": false])
        var acc = ""
        for try await chunk in session.streamResponse(to: prompt) {
            if aborted || Task.isCancelled {
                Diag.mark("本地模型：离开前台，中止生成")
                break
            }
            acc += chunk
            onText(Self.clean(acc))
        }
        if aborted { throw CancellationError() }
        return Self.clean(acc)
    }

    // 去掉 Qwen3 的 <think>…</think> 思考过程
    nonisolated static func clean(_ s: String) -> String {
        var t = s
        while let a = t.range(of: "<think>") {
            if let b = t.range(of: "</think>", range: a.upperBound..<t.endIndex) {
                t.removeSubrange(a.lowerBound..<b.upperBound)
            } else {
                t.removeSubrange(a.lowerBound..<t.endIndex)
                break
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// 统一入口：本地大模型可用就用它，否则用系统自带模型的调用方自己回退
enum LLM {
    static func localAvailable() async -> Bool { await LocalLLM.shared.canUse }

    static func complete(instructions: String, prompt: String, maxTokens: Int = 600, temperature: Float = 0.3) async -> String? {
        guard await LocalLLM.shared.canUse else { return nil }
        return try? await LocalLLM.shared.generate(instructions: instructions, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
    }
}
