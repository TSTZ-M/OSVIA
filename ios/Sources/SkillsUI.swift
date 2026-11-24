import SwiftUI

// MARK: 脚本技能：列表、模板、一句话创建、导入导出
struct SkillsView: View {
    @State private var skills: [Row] = []
    @State private var last: [String: Skills.LastRun] = [:]
    @State private var spec = ""
    @State private var busy = false
    @State private var status = ""
    @State private var result: (name: String, ok: Bool, out: String)?
    @State private var showPack = false
    @State private var note = ""
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                Text("脚本技能是用 JavaScript 写的小工具：能联网取数据、读网页、调用大模型、保存数据、发通知（含 Bark），还能定时运行。它看不到屏幕，也不能操作别的 App；翻译截图请用「屏幕翻译」。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("用一句话创建") {
                TextField("例如：把输入的文字倒过来", text: $spec, axis: .vertical).lineLimit(2...4)
                Button { create() } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(busy ? status : "创建并运行").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || spec.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
                if let r = result {
                    if r.ok {
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(L10n.f("已创建「{}」并运行成功", r.name)) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            Text(verbatim: r.out).textSelection(.enabled)
                        }
                    } else {
                        Label { Text(L10n.f("没能生成可运行的脚本（{}），请换个描述再试一次", r.out)) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }
            }
            Section("我的技能") {
                if skills.isEmpty { Text("还没有技能，先在上面创建一个，或从下面的模板开始").foregroundStyle(.secondary) }
                ForEach(Array(skills.enumerated()), id: \.offset) { _, elem in
                    NavigationLink {
                        SkillRunView(name: elem.s("name"))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: elem.s("name")).font(.headline)
                            Text(verbatim: elem.s("desc")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            if let l = last[elem.s("name")] {
                                Label {
                                    Text(verbatim: Sys.friendly(l.date))
                                } icon: {
                                    Image(systemName: l.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(l.ok ? Color.green : Color.orange)
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in
                    for i in idx { Skills.remove(skills[i].s("name")) }
                    reload()
                }
            }
            Section("新建") {
                NavigationLink {
                    SkillEditor(name: nil)
                } label: { Label("新建空白脚本", systemImage: "plus.square") }
                ForEach(Skills.templates) { t in
                    NavigationLink {
                        SkillEditor(name: nil, template: t)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: t.icon).foregroundStyle(Brand.mint).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                Text(t.desc).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            Section {
                Button { showPack = true } label: { Label("导入技能包", systemImage: "square.and.arrow.down") }
                if let u = exportURL {
                    ShareLink(item: u) { Label("导出全部技能", systemImage: "square.and.arrow.up") }
                }
                if !note.isEmpty { Text(verbatim: note).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("技能包是一个 .json 文件，可以在设备之间分享，也可以用电脑写好再导入。")
            }
        }
        .navigationTitle("脚本技能")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
        .fileImporter(isPresented: $showPack, allowedContentTypes: [.json]) { r in
            if let u = try? r.get() {
                let n = Skills.importPack(u)
                note = n > 0 ? L10n.f("已导入 {} 个技能", "\(n)") : L10n.tr("没有读到可导入的技能，请确认文件格式。")
                reload()
            }
        }
        .onAppear(perform: reload)
    }

    func reload() {
        skills = Skills.list()
        var m: [String: Skills.LastRun] = [:]
        for s in skills { if let l = Skills.lastRun(s.s("name")) { m[s.s("name")] = l } }
        last = m
        exportURL = skills.isEmpty ? nil : Skills.exportPack(skills.map { $0.s("name") })
    }

    func create() {
        let s = spec
        hideKeyboard()
        busy = true
        result = nil
        status = L10n.tr("准备中…")
        Task {
            let r = await Skills.create(s) { msg in DispatchQueue.main.async { status = L10n.tr(msg) } }
            result = r
            busy = false
            if r.ok { spec = "" }
            reload()
        }
    }
}

// MARK: 运行页：输入、运行、日志、定时、导出
struct SkillRunView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var outcome: ScriptEngine.Outcome?
    @State private var running = false
    @State private var copied = false
    @State private var desc = ""
    @State private var last: Skills.LastRun?
    @State private var sched: [Row] = []
    @State private var when = Date().addingTimeInterval(3600)
    @State private var rep = 0
    @State private var exportURL: URL?
    @State private var storeCount = 0

    private struct Shown {
        var ok: Bool
        var out: String
        var logs: [String]
        var ms: Int
        var date: Date?
    }

    private var shown: Shown? {
        if let o = outcome { return Shown(ok: o.ok, out: o.output, logs: o.logs, ms: o.ms, date: nil) }
        if let l = last { return Shown(ok: l.ok, out: l.output, logs: l.logs, ms: l.ms, date: l.date) }
        return nil
    }

    // 名字像「屏幕翻译」的旧技能：脚本读不到屏幕，引导到新版
    private var looksLikeScreenTranslate: Bool {
        name.contains("翻译") && (name.contains("屏") || name.contains("截"))
    }

    private var link: String {
        let n = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return "osvia://run?name=\(n)&input="
    }

    private func repName(_ r: Int) -> String {
        r == 1 ? L10n.tr("每天") : (r == 7 ? L10n.tr("每周") : L10n.tr("仅一次"))
    }

    var body: some View {
        List {
            if !desc.isEmpty {
                Section("这个技能做什么") { Text(verbatim: desc) }
            }
            if looksLikeScreenTranslate {
                Section {
                    NavigationLink {
                        ScreenTranslateView()
                    } label: { Label("改用新版「屏幕翻译」", systemImage: "character.bubble") }
                    Text("脚本只能处理你输入的文字，看不到屏幕，所以这个技能运行不出结果。新版会识别截图里的文字，翻译后把译文贴回原位。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("输入内容") {
                TextField("要处理的文字（有的技能可以留空）", text: $input, axis: .vertical).lineLimit(1...5)
            }
            Section {
                Button { run() } label: {
                    HStack(spacing: 8) {
                        if running { ProgressView() }
                        Label(running ? "正在运行…" : "运行", systemImage: "play.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                .listRowBackground(Color.clear)
            }
            if let s = shown {
                Section {
                    Text(verbatim: s.out).textSelection(.enabled).foregroundStyle(s.ok ? Color.primary : Color.red)
                    if !s.logs.isEmpty {
                        DisclosureGroup {
                            ForEach(Array(s.logs.enumerated()), id: \.offset) { _, l in
                                Text(verbatim: l).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        } label: {
                            Text(L10n.f("运行日志（{} 条）", "\(s.logs.count)"))
                        }
                    }
                } header: {
                    Text(s.date == nil ? "运行结果" : "上次运行")
                } footer: {
                    Text(L10n.f("耗时 {} 毫秒", "\(s.ms)") + (s.date.map { " · " + Sys.friendly($0) } ?? ""))
                }
            }
            Section {
                ForEach(Array(sched.enumerated()), id: \.offset) { _, t in
                    HStack {
                        Label { Text(verbatim: Sys.friendly(Date(timeIntervalSince1970: t.d("due")))) } icon: { Image(systemName: "clock") }
                        Spacer()
                        Text(verbatim: repName(t.i("rep"))).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    for i in idx { Tasks.remove(sched[i].i("id")) }
                    sched = Skills.schedules(name)
                }
                DatePicker(selection: $when, in: Date()...) { Text("时间") }
                Picker("重复", selection: $rep) {
                    Text("仅一次").tag(0)
                    Text("每天").tag(1)
                    Text("每周").tag(7)
                }
                Button { addSchedule() } label: { Label("添加定时运行", systemImage: "calendar.badge.plus") }
            } header: {
                Text("定时运行")
            } footer: {
                Text("到点前 OSVIA 会先运行脚本，结果通过系统通知准时送达（开启 Bark 时同步推送）。脚本需要联网时，请隔一阵打开一次 OSVIA。上面「输入内容」会作为每次运行的输入。")
            }
            Section("怎么用") {
                Text("① 在上面「输入内容」里填要处理的文字，点「运行」。\n② 在对话里说：运行 \(name) 加上要处理的内容。\n③ 给快捷指令或其他 App 用：点下面「复制调用链接」，在链接末尾 input= 后面接上要处理的文字。\n注意：调用链接是给别的 App 用的，不要粘贴到上面的输入框里。")
                    .font(.subheadline)
            }
            Section("管理") {
                NavigationLink {
                    SkillEditor(name: name)
                } label: { Label("编辑脚本", systemImage: "pencil.and.scribble") }
                if let u = exportURL {
                    ShareLink(item: u) { Label("导出这个技能", systemImage: "square.and.arrow.up") }
                }
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: { Label(copied ? "已复制调用链接" : "复制调用链接", systemImage: "link") }
                if storeCount > 0 {
                    Button(role: .destructive) {
                        ScriptEngine.clearStore(name)
                        storeCount = 0
                    } label: { Label { Text(L10n.f("清空脚本保存的数据（{} 项）", "\(storeCount)")) } icon: { Image(systemName: "trash") } }
                }
            }
            Section {
                Button("删除这个技能", role: .destructive) {
                    Skills.remove(name)
                    dismiss()
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
        .onAppear(perform: reload)
    }

    func reload() {
        desc = Skills.get(name)?.s("desc") ?? ""
        last = Skills.lastRun(name)
        sched = Skills.schedules(name)
        storeCount = ScriptEngine.storeKeys(name).count
        exportURL = Skills.exportPack([name])
    }

    func addSchedule() {
        hideKeyboard()
        Skills.schedule(name, input: input, at: when, rep: rep)
        sched = Skills.schedules(name)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            await Tasks.refresh()
            sched = Skills.schedules(name)
        }
    }

    func run() {
        hideKeyboard()
        copied = false
        if input.hasPrefix("osvia://") {
            outcome = ScriptEngine.Outcome(ok: false, output: L10n.tr("这里要填的是要处理的文字，不是调用链接。调用链接是给快捷指令或其他 App 用的。请清空后重新输入。"), logs: [], ms: 0)
            return
        }
        running = true
        let text = input
        Task {
            var r = await Skills.runAsyncFull(name, text, timeout: 60)
            if !r.ok && r.output.contains("没有返回") {
                r.output = text.isEmpty
                    ? L10n.tr("这个技能需要输入内容：请先在上面「输入内容」里填写要处理的文字，再点运行。")
                    : L10n.tr("脚本运行了但没有产出结果，可能不适合这段输入。可以换一段文字试试，或编辑脚本。")
            }
            outcome = r
            running = false
            last = Skills.lastRun(name)
            storeCount = ScriptEngine.storeKeys(name).count
            UINotificationFeedbackGenerator().notificationOccurred(r.ok ? .success : .error)
        }
    }
}

// MARK: 脚本编辑器：新建、改代码、试运行
struct SkillEditor: View {
    let original: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var code: String
    @State private var sample: String
    @State private var testing = false
    @State private var outcome: ScriptEngine.Outcome?
    @State private var error = ""

    init(name: String?, template: Skills.Template? = nil) {
        original = name
        if let n = name, let r = Skills.get(n) {
            _name = State(initialValue: n)
            _desc = State(initialValue: r.s("desc"))
            _code = State(initialValue: r.s("code"))
            _sample = State(initialValue: "")
        } else if let t = template {
            _name = State(initialValue: L10n.tr(t.title))
            _desc = State(initialValue: L10n.tr(t.desc))
            _code = State(initialValue: t.code)
            _sample = State(initialValue: t.sample)
        } else {
            _name = State(initialValue: "")
            _desc = State(initialValue: "")
            _code = State(initialValue: "function(input) {\n  return input;\n}")
            _sample = State(initialValue: "")
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("基本信息") {
                if original == nil {
                    TextField("名称", text: $name)
                } else {
                    HStack {
                        Text("名称")
                        Spacer()
                        Text(verbatim: name).foregroundStyle(.secondary)
                    }
                }
                TextField("一句话说明用途", text: $desc)
            }
            Section {
                CodeEditor(text: $code).frame(minHeight: 220)
            } header: {
                Text("脚本代码")
            } footer: {
                Text("写成 function(input){ … return 结果; }，也可以直接写函数体。input 是传入的文字，返回字符串或对象。")
            }
            Section {
                TextField("测试输入（可选）", text: $sample, axis: .vertical).lineLimit(1...4)
                Button { test() } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView() }
                        Label(testing ? "正在运行…" : "试运行", systemImage: "play.fill")
                    }
                }
                .disabled(testing || !canSave)
                if let o = outcome {
                    Text(verbatim: o.output).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(o.ok ? Color.primary : Color.red)
                    if !o.logs.isEmpty {
                        DisclosureGroup {
                            ForEach(Array(o.logs.enumerated()), id: \.offset) { _, l in
                                Text(verbatim: l).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        } label: {
                            Text(L10n.f("运行日志（{} 条）", "\(o.logs.count)"))
                        }
                    }
                    Text(L10n.f("耗时 {} 毫秒", "\(o.ms)")).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("试运行")
            } footer: {
                Text("试运行时脚本保存的数据会在结束后清掉，不会影响正式运行。")
            }
            if !error.isEmpty {
                Section {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            Section {
                DisclosureGroup {
                    Text(verbatim: SkillsDoc.api).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                } label: {
                    Label("函数速查", systemImage: "book")
                }
            }
        }
        .navigationTitle(original ?? L10n.tr("新建脚本"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(!canSave)
            }
        }
    }

    func test() {
        hideKeyboard()
        testing = true
        let c = Skills.clean(code)
        let s = sample
        Task {
            let r = await Skills.testAsync(c, s, timeout: 60)
            outcome = r
            testing = false
            UINotificationFeedbackGenerator().notificationOccurred(r.ok ? .success : .error)
        }
    }

    func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = Skills.clean(code)
        guard !n.isEmpty, !c.isEmpty else { return }
        if n.contains("|") || n.hasPrefix("~") {
            error = L10n.tr("名称里不能有「|」，也不能以「~」开头。")
            return
        }
        if original == nil, Skills.exists(n) {
            error = L10n.tr("已经有同名技能了，换一个名字。")
            return
        }
        let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        Skills.save(n, d.isEmpty ? n : d, c)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

enum SkillsDoc {
    static let api = """
    联网（只能访问公开 https 地址，每次运行最多 20 次）
    httpGet(url, 请求头?) → {ok, status, body, headers}
    httpPost(url, 请求体, 请求头?)  httpPut  httpDelete
    fetchJSON(url) → 对象    fetchText(url) → 文本
    readPage(url) → 网页正文

    存储（每个脚本独立，最多 200 项，可存对象）
    store.get(键, 默认值)  store.set(键, 值)
    store.remove(键)  store.keys()

    通知（合计每次运行最多 3 条）
    notify(标题, 内容)  本机通知
    bark(标题, 内容)  推送到 Bark

    智能
    ask(提示, 系统指令?) → 文本（每次最多 3 次）
    kbSearch(关键词) → 字符串数组
    calc("1+2*3") → "7"

    工具
    md5  sha1  sha256  hmac(密钥, 文本)
    base64  unbase64  uuid()  secureRandom(n)
    formatDate(毫秒, "yyyy-MM-dd HH:mm")
    csvParse(文本)  csvStringify(二维数组)
    sleep(毫秒，最多 2000)  console.log(...)
    params：input 是 JSON 文本时自动解析成对象

    支持 async / await，但没有 setTimeout；上面的函数都是同步的，直接调用即可。
    """
}

// MARK: 代码输入框：等宽字体、关闭智能引号和自动更正，键盘上方有常用符号
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        v.adjustsFontForContentSizeCategory = true
        v.autocorrectionType = .no
        v.autocapitalizationType = .none
        v.smartQuotesType = .no
        v.smartDashesType = .no
        v.smartInsertDeleteType = .no
        v.spellCheckingType = .no
        v.backgroundColor = .clear
        v.isScrollEnabled = false
        v.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        v.text = text
        v.delegate = context.coordinator
        context.coordinator.view = v

        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        var items: [UIBarButtonItem] = []
        for s in ["{", "}", "(", ")", "[", "]", ";", "\"", "'", "=>", "."] {
            items.append(UIBarButtonItem(title: s, style: .plain, target: context.coordinator, action: #selector(Coordinator.insert(_:))))
            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        }
        items.append(UIBarButtonItem(title: L10n.tr("完成"), style: .done, target: v, action: #selector(UIResponder.resignFirstResponder)))
        bar.items = items
        v.inputAccessoryView = bar
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        if v.text != text { v.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 320
        let h = uiView.sizeThatFits(CGSize(width: w, height: CGFloat.greatestFiniteMagnitude)).height
        return CGSize(width: w, height: max(220, h))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var view: UITextView?

        init(_ p: CodeEditor) { parent = p }

        func textViewDidChange(_ v: UITextView) { parent.text = v.text }

        @objc func insert(_ b: UIBarButtonItem) {
            guard let v = view, let t = b.title else { return }
            v.insertText(t)
            parent.text = v.text
        }
    }
}
