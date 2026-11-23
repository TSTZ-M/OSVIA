import SwiftUI
import EventKit
import Photos
import PhotosUI
import FoundationModels

// 今日回顾：iOS 不允许 App 读取「屏幕使用时间」和其他 App 的通知，所以这里只汇总本机允许读取的数据，
// 再加上用户导入的屏幕使用时间 / 通知截图（端侧文字识别），由本机模型写成当天总结。
// 所有显示的数据行和总结都用应用当前语言；本地大模型可用时优先用它。
@MainActor
enum Digest {
    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // 括号里的列表（为空则不显示）
    private static func paren(_ items: [String]) -> String {
        items.isEmpty ? "" : L10n.f("（{}）", L10n.list(items))
    }

    // 读取今天本机能读到的数据；没有授权的项目直接略过
    static func collect() async -> [String] {
        var out: [String] = []
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let store = EKEventStore()

        if let ok = try? await store.requestFullAccessToEvents(), ok {
            let evs = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                .sorted { $0.startDate < $1.startDate }
            if evs.isEmpty {
                out.append(L10n.tr("日历") + L10n.colon + L10n.tr("今天没有日程"))
            } else {
                let list = evs.prefix(10).map { (($0.isAllDay ? L10n.tr("全天") : hm($0.startDate)) + " " + ($0.title ?? "")) }
                out.append(L10n.f("日历：共 {} 项：{}", "\(evs.count)", L10n.list(list)))
            }
        }

        if let ok = try? await store.requestFullAccessToReminders(), ok {
            let pred = store.predicateForReminders(in: nil)
            let all: [EKReminder] = await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
                store.fetchReminders(matching: pred) { @Sendable r in c.resume(returning: r ?? []) }
            }
            let todo = all.filter { r in
                guard !r.isCompleted, let comps = r.dueDateComponents, let d = cal.date(from: comps) else { return false }
                return d < end
            }
            let done = all.filter { r in
                guard r.isCompleted, let d = r.completionDate else { return false }
                return d >= start
            }
            out.append(L10n.f("提醒事项：今天及逾期未完成 {} 项{}；今天已完成 {} 项{}",
                              "\(todo.count)", paren(todo.prefix(8).map { $0.title ?? "" }),
                              "\(done.count)", paren(done.prefix(8).map { $0.title ?? "" })))
        }

        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .authorized || st == .limited {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let r = PHAsset.fetchAssets(with: o)
            if r.count > 0 {
                var photos = 0
                var videos = 0
                r.enumerateObjects { a, i, stop in
                    if a.mediaType == .video { videos += 1 } else { photos += 1 }
                    if i >= 999 { stop.pointee = true }
                }
                let vid = videos > 0 ? L10n.f("、{} 段视频", "\(videos)") : ""
                var span = ""
                if let f = r.firstObject?.creationDate, let l = r.lastObject?.creationDate { span = L10n.f("，时间 {} 到 {}", hm(f), hm(l)) }
                out.append(L10n.f("相册：今天拍了 {} 张照片{}{}", "\(photos)", vid, span))
            } else {
                out.append(L10n.tr("相册：今天没有新照片"))
            }
        }

        let ts = start.timeIntervalSince1970
        let asked = DB.shared.rows("SELECT COUNT(*) AS n FROM msg WHERE role='user' AND ts>=?", [ts]).first?.i("n") ?? 0
        out.append(L10n.f("助理：今天和助理对话 {} 次", "\(asked)"))

        let tasks = Tasks.list().filter { $0.d("due") >= ts && $0.d("due") < ts + 86400 }
        if !tasks.isEmpty {
            out.append(L10n.f("定时任务：今天有 {} 个：{}", "\(tasks.count)", L10n.list(tasks.prefix(6).map { L10n.tr($0.s("title")) })))
        }
        let alarms = Tasks.alarms().filter { $0.d("due") >= ts && $0.d("due") < ts + 86400 }
        if !alarms.isEmpty {
            out.append(L10n.f("闹钟：今天有 {} 个：{}", "\(alarms.count)", L10n.list(alarms.prefix(6).map { L10n.tr(Sys.plainLabel($0.s("label"))) + " " + hm(Date(timeIntervalSince1970: $0.d("due"))) })))
        }
        return out
    }

    // 截图 → 文字（端侧识别，不联网）
    static func readShot(_ data: Data) async -> String {
        let s = Files.save(data, name: "回顾截图-\(UUID().uuidString.prefix(6)).jpg")
        guard let u = s.url else { return "" }
        let text = await Task.detached { OCR.text(u) }.value
        try? FileManager.default.removeItem(at: u)
        return String(text.prefix(1500))
    }

    static func summarize(facts: [String], screens: [String], onUpdate: @escaping (String) -> Void) async -> String {
        var prompt = "Today is " + Sys.fmtFull(Date()) + ". Data for today:\n" + facts.joined(separator: "\n")
        if !screens.isEmpty {
            let joined = screens.joined(separator: "\n---\n")
            prompt += "\n\nText recognized from the user’s Screen Time / notification screenshots (may contain OCR errors):\n" + String(joined.prefix(1500))
        }
        let ins = "You are the user’s personal assistant. Write a daily recap from the data given: first one sentence summarizing the day, then three short sections — what was done, where the time went (only if screenshot data exists), and what to watch tomorrow — at most three items each. Use only the data provided and never invent anything. Keep it under 300 characters/words. " + L10n.replyDirective

        // 本地大模型优先
        if LocalLLM.shared.canUse {
            do {
                let out = try await LocalLLM.shared.generate(instructions: ins, prompt: prompt, maxTokens: 500, temperature: 0.3) { text in onUpdate(text) }
                return out.isEmpty ? L10n.tr("模型没有返回内容，请再试一次。") : out
            } catch {
                return L10n.f("本地模型出错：{}", String(error.localizedDescription.prefix(120)))
            }
        }

        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(let r): return L10n.tr(Agent.unavailableText("\(r)"))
        @unknown default: break
        }
        let session = LanguageModelSession(instructions: ins)
        var last = ""
        do {
            for try await snap in session.streamResponse(to: prompt) {
                last = snap.content
                onUpdate(last)
            }
        } catch {
            return last.isEmpty ? L10n.f("这次没能生成（{}），请再试一次。", String("\(error)".prefix(80))) : last
        }
        return last.isEmpty ? L10n.tr("模型没有返回内容，请再试一次。") : last
    }
}

struct DigestView: View {
    @State private var facts: [String] = []
    @State private var loadingFacts = false
    @State private var showPicker = false
    @State private var items: [PhotosPickerItem] = []
    @State private var screens: [String] = []
    @State private var reading = false
    @State private var result = ""
    @State private var busy = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("汇总今天本机允许读取的日历、提醒事项、相册、任务和对话，再由本机模型写成一份总结。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
                Section("今天自动读取到的") {
                    if loadingFacts { HStack(spacing: 8) { ProgressView(); Text("正在读取…").foregroundStyle(Brand.sub) } }
                    ForEach(facts, id: \.self) { Text($0).font(.subheadline) }
                    Button { Task { await refresh() } } label: { Label("重新读取", systemImage: "arrow.clockwise") }.disabled(loadingFacts)
                }
                Section("屏幕使用时间与通知") {
                    Text("iOS 不允许任何 App 直接读取屏幕使用时间和其他 App 的通知。办法：在「设置 → 屏幕使用时间 → 查看所有活动」截图，或截一张通知中心，在这里导入，由本机识别文字后一起总结。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                    Button { showPicker = true } label: { Label("导入截图", systemImage: "photo.badge.plus") }.disabled(reading)
                    if reading { HStack(spacing: 8) { ProgressView(); Text("正在识别文字…").foregroundStyle(Brand.sub) } }
                    if !screens.isEmpty {
                        HStack {
                            Text("已识别 \(screens.count) 张截图").font(.subheadline)
                            Spacer()
                            Button("清除") { screens = [] }.buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    Button { generate() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() }
                            Text(busy ? "正在总结…" : "生成今日总结").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || loadingFacts)
                    .listRowBackground(Color.clear)
                }
                if !result.isEmpty {
                    Section("今日回顾") {
                        Text(result).textSelection(.enabled)
                        ShareLink(item: result) { Label("分享", systemImage: "square.and.arrow.up") }
                        Button { save() } label: { Label(saved ? "已存入知识库" : "存入知识库", systemImage: "books.vertical") }.disabled(saved || busy)
                    }
                }
            }
            .navigationTitle("今日回顾")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented: $showPicker, selection: $items, maxSelectionCount: 6, matching: .images)
            .onChange(of: items) { _, new in
                guard !new.isEmpty else { return }
                let picked = new
                items = []
                Task { await importShots(picked) }
            }
            .task { await refresh() }
        }
    }

    func refresh() async {
        loadingFacts = true
        facts = await Digest.collect()
        loadingFacts = false
    }

    func importShots(_ picked: [PhotosPickerItem]) async {
        reading = true
        for it in picked {
            if let d = try? await it.loadTransferable(type: Data.self), let j = Files.jpegData(fromImageData: d) {
                let t = await Digest.readShot(j)
                if !t.isEmpty { screens.append(t) }
            }
        }
        reading = false
    }

    func generate() {
        busy = true
        result = ""
        saved = false
        Task {
            if facts.isEmpty { facts = await Digest.collect() }
            result = await Digest.summarize(facts: facts, screens: screens) { result = $0 }
            busy = false
        }
    }

    func save() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        KB.shared.upsert(L10n.tr("今日回顾") + " " + f.string(from: Date()), result)
        saved = true
    }
}
