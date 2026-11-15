import SwiftUI
import UniformTypeIdentifiers

// MARK: AI 记忆中心：从任何 AI 带来记忆（一键跳转 + 粘贴/文件导入），管理、整理、带去其他 AI

struct MemoryHome: View {
    var body: some View {
        NavigationStack { MemoryHubView() }
    }
}

struct ImportJob: Identifiable {
    let id = UUID()
    var raw: String
    var chat: [String]
    var source: String
}

struct MemEdit: Identifiable {
    let id = UUID()
    var rowId: Int          // 0 表示新增
    var text: String
    var cat: String
    var pin: Bool
}

struct JumpJob: Identifiable {
    let id = UUID()
    var title: String
    var hint: String
    var prompt: String
    var remember = false    // 记住去过哪个 AI，导入时自动填来源
}

struct MemoryHubView: View {
    @State private var count = 0
    @State private var exportText = ""
    @State private var backup = false
    @State private var jump: JumpJob?
    @State private var job: ImportJob?
    @State private var edit: MemEdit?
    @State private var showFile = false
    @State private var showClear = false
    @State private var busy = false
    @State private var info = ""

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if !info.isEmpty {
                Section {
                    Label { Text(verbatim: info) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.subheadline)
                }
            }

            Section {
                stepRow(1, "复制导出提示词，跳转到其他 AI", "ChatGPT、Claude、Gemini、豆包、Kimi 等 30 个主流 AI，也能填任意网址") {
                    jump = JumpJob(title: "选择要导出记忆的 AI",
                                   hint: "点一个 AI：导出提示词会自动复制并打开它。在那边发送，等它输出一个代码块，复制回复，再回来点「粘贴并导入」。",
                                   prompt: Memory.exportPrompt, remember: true)
                }
                stepRow(2, "粘贴那个 AI 的回复并导入", "自动识别列表、Markdown、JSON，导入前可逐条确认") { pasteImport() }
            } header: {
                Text("从其他 AI 带来记忆")
            } footer: {
                Text("也适用于任何没有预设的 AI：复制提示词，去那里发送，再把回复粘贴回来。")
            }

            Section {
                Button { job = ImportJob(raw: "", chat: [], source: "手动") } label: { Label("粘贴或输入文字", systemImage: "text.cursor") }
                Button { showFile = true } label: { Label("选择文件", systemImage: "doc.badge.plus") }
                Button { edit = MemEdit(rowId: 0, text: "", cat: "其他", pin: false) } label: { Label("手动添加一条", systemImage: "plus") }
            } header: {
                Text("手动导入")
            } footer: {
                Text("支持 txt、md、json，也支持 ChatGPT、Claude 的对话记录导出（conversations.json，ChatGPT 导出的 zip 需先解压）。")
            }

            Section("管理") {
                NavigationLink {
                    MemoryListView()
                } label: {
                    HStack {
                        Label("全部记忆", systemImage: "list.bullet")
                        Spacer()
                        Text(verbatim: "\(count)").foregroundStyle(Brand.sub)
                    }
                }
                Button {
                    jump = JumpJob(title: "带着记忆去其他 AI",
                                   hint: "把你的背景与偏好整理成一段介绍，复制并打开选中的 AI，粘贴发送后它就了解你了。",
                                   prompt: Memory.pack())
                } label: { Label("带去其他 AI", systemImage: "arrow.up.forward.app") }
                    .disabled(count == 0)
                ShareLink(item: exportText) { Label("导出为文本", systemImage: "square.and.arrow.up") }
                    .disabled(count == 0)
                Button {
                    busy = true
                    info = ""
                    Task {
                        let msg = await Memory.consolidate()
                        info = L10n.tr(msg)
                        busy = false
                        reload()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Label(busy ? "正在整理…" : "AI 整理（合并重复、修正分类）", systemImage: "wand.and.stars")
                    }
                }
                .disabled(busy || count < 6)
                if backup {
                    Button {
                        info = Memory.undoConsolidate() ? L10n.tr("已撤销上次整理") : L10n.tr("没有可撤销的整理")
                        reload()
                    } label: { Label("撤销上次整理", systemImage: "arrow.uturn.backward") }
                }
                Button(role: .destructive) { showClear = true } label: { Label("清空所有记忆", systemImage: "trash") }
                    .disabled(count == 0)
            }

            Section {
                NavigationLink { EvolvePage() } label: { Label("进化记录", systemImage: "leaf") }
            } footer: {
                Text("记忆只保存在这台手机上。使用云端大脑时，与当前问题相关的记忆会随对话一起发给你配置的服务。")
            }
        }
        .navigationTitle("AI 记忆")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $jump) { j in
            JumpSheet(job: j).presentationBackground(Brand.page)
        }
        .sheet(item: $job, onDismiss: reload) { j in
            ImportSheet(job: j) { added, skipped in
                var s = L10n.f("已导入 {} 条", "\(added)")
                if skipped > 0 { s += L10n.f("，{} 条已存在，已跳过", "\(skipped)") }
                info = s
            }
            .presentationBackground(Brand.page)
        }
        .sheet(item: $edit, onDismiss: reload) { e in
            MemoryEditSheet(edit: e).presentationBackground(Brand.page)
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.item]) { r in
            switch r {
            case .success(let u):
                info = L10n.tr("正在读取…")
                Task {
                    let res = await Task.detached { MemoryImport.read(u) }.value
                    let name = u.deletingPathExtension().lastPathComponent
                    if !res.chat.isEmpty {
                        info = ""
                        job = ImportJob(raw: "", chat: res.chat, source: name)
                    } else if res.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        info = L10n.tr("这个文件里没有可识别的文字")
                    } else {
                        info = ""
                        job = ImportJob(raw: res.raw, chat: [], source: name)
                    }
                }
            case .failure(let e):
                info = L10n.f("无法打开文件：{}", e.localizedDescription)
            }
        }
        .confirmationDialog("清空所有记忆？此操作无法撤销。", isPresented: $showClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Memory.clear()
                info = L10n.tr("已清空")
                reload()
            }
            Button("取消", role: .cancel) {}
        }
    }

    var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Brand.mint)
                .frame(width: 58, height: 58)
                .background(Brand.mint.opacity(0.14))
                .clipShape(Circle())
            Text(verbatim: "\(count)")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.ink)
                .contentTransition(.numericText())
            Text("条记忆，每次对话都会自然地用上")
                .font(.subheadline)
                .foregroundStyle(Brand.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    func stepRow(_ n: Int, _ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: "\(n)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Brand.onMint)
                    .frame(width: 24, height: 24)
                    .background(Brand.mint)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.ink)
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(Brand.sub).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.sub.opacity(0.6))
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
    }

    func pasteImport() {
        let pb = UIPasteboard.general
        guard pb.hasStrings, let s = pb.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            info = L10n.tr("剪贴板是空的：先去那个 AI 复制它的回复")
            return
        }
        info = ""
        job = ImportJob(raw: s, chat: [], source: DB.shared.kv("memory.lastAI") ?? "其他 AI")
    }

    func reload() {
        count = Memory.count()
        backup = Memory.hasBackup
        exportText = count > 0 ? Memory.exportText() : ""
    }
}

// MARK: 选择一个 AI 跳转：提示词先复制，能预填的直接预填
struct JumpSheet: View {
    let job: JumpJob
    @Environment(\.dismiss) private var dismiss
    @State private var group = "全部"
    @State private var custom = ""
    @State private var note = ""
    @State private var showPrompt = false

    private var list: [AIService] {
        group == "全部" ? Jump.services : Jump.services.filter { $0.group == group }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(job.hint).font(.subheadline).foregroundStyle(Brand.sub)
                    Picker("", selection: $group) {
                        ForEach(Jump.groups, id: \.self) { g in Text(g).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(list) { s in cell(s) }
                    }
                    customRow
                    if !note.isEmpty {
                        Label { Text(verbatim: note) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint) }
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.mint.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    DisclosureGroup(isExpanded: $showPrompt) {
                        Text(verbatim: job.prompt)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Brand.sub)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    } label: {
                        Text("查看将发送的内容").font(.subheadline).foregroundStyle(Brand.ink)
                    }
                    Button {
                        UIPasteboard.general.string = job.prompt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        note = L10n.tr("已复制，可以粘贴到任何地方")
                    } label: {
                        Label("只复制，不跳转", systemImage: "doc.on.doc").font(.subheadline)
                    }
                }
                .padding(16)
            }
            .background(Brand.page)
            .navigationTitle(job.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    var customRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").foregroundStyle(Brand.sub)
            TextField("其他 AI 的网址，例如 chat.example.com", text: $custom)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit(openCustom)
            Button("打开", action: openCustom)
                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func openCustom() {
        if Jump.openCustom(custom, prompt: job.prompt) {
            if job.remember { DB.shared.setKV("memory.lastAI", custom.trimmingCharacters(in: .whitespaces)) }
            note = L10n.tr("已复制提示词并打开。到输入框长按粘贴并发送")
        } else {
            note = L10n.tr("网址不正确")
        }
    }

    func cell(_ s: AIService) -> some View {
        Button {
            let pre = Jump.open(s, prompt: job.prompt)
            if job.remember { DB.shared.setKV("memory.lastAI", s.name) }
            note = pre
                ? L10n.f("已打开 {}，提示词已填好，直接发送即可", s.name)
                : L10n.f("已复制提示词。打开 {} 后，在输入框长按粘贴并发送", s.name)
        } label: {
            HStack(spacing: 10) {
                AIIcon(service: s, size: 34)
                Text(verbatim: s.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: 导入：粘贴/文件 → 解析或 AI 提炼 → 逐条确认 → 写入
struct ImportSheet: View {
    let job: ImportJob
    var onDone: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var raw: String
    @State private var source: String
    @State private var items: [MemItem] = []
    @State private var picked: Set<UUID> = []
    @State private var preview = false
    @State private var busy = false
    @State private var progress = ""
    @State private var note = ""
    @State private var work: Task<Void, Never>?

    init(job: ImportJob, onDone: @escaping (Int, Int) -> Void) {
        self.job = job
        self.onDone = onDone
        _raw = State(initialValue: job.raw)
        _source = State(initialValue: job.source)
    }

    private var isChat: Bool { !job.chat.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if preview { previewList } else { inputForm }
            }
            .navigationTitle(preview ? "确认导入" : "导入记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        work?.cancel()
                        dismiss()
                    }
                }
                if preview {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.f("导入 {} 条", "\(picked.count)")) { commit() }
                            .fontWeight(.semibold)
                            .disabled(picked.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    // 第一步：输入内容
    var inputForm: some View {
        Form {
            Section {
                HStack {
                    Text("来源")
                    TextField("例如 ChatGPT", text: $source).multilineTextAlignment(.trailing)
                }
            }
            if isChat {
                Section {
                    Text(L10n.f("检测到对话记录：找到你发出的 {} 条消息。会用 AI 从中提炼关于你的长期信息，再让你逐条确认。", "\(job.chat.count)"))
                        .font(.subheadline)
                }
            } else {
                Section {
                    TextEditor(text: $raw)
                        .frame(minHeight: 220)
                        .font(.system(size: 15))
                        .overlay(alignment: .topLeading) {
                            if raw.isEmpty {
                                Text("粘贴其他 AI 导出的记忆，或直接写：每条一行").foregroundStyle(Brand.sub.opacity(0.7)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                } footer: {
                    Text("每行一条，可带 [类别] 前缀；Markdown 列表、JSON 也行。")
                }
            }
            Section {
                if !isChat {
                    Button { parseDirect() } label: { Label("直接解析", systemImage: "list.bullet.rectangle") }
                        .disabled(busy || raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button { distill() } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Label(busy ? (progress.isEmpty ? L10n.tr("正在提炼…") : progress) : "AI 提炼（去重、去闲聊、归类）", systemImage: "sparkles")
                    }
                }
                .disabled(busy || (isChat ? false : raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                if busy {
                    Button("停止", role: .destructive) { work?.cancel() }
                }
            } footer: {
                if !note.isEmpty { Text(verbatim: note).foregroundStyle(.orange) }
            }
        }
    }

    // 第二步：逐条确认，可改文字、改分类
    var previewList: some View {
        List {
            Section {
                ForEach($items) { $it in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            if picked.contains(it.id) { picked.remove(it.id) } else { picked.insert(it.id) }
                        } label: {
                            Image(systemName: picked.contains(it.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21))
                                .foregroundStyle(picked.contains(it.id) ? Brand.mint : Brand.sub.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("", text: $it.text, axis: .vertical).font(.system(size: 15.5))
                            Picker("", selection: $it.cat) {
                                ForEach(Memory.cats, id: \.self) { c in Text(c).tag(c) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .controlSize(.small)
                            .tint(Brand.sub)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text(L10n.f("识别出 {} 条，已选 {} 条", "\(items.count)", "\(picked.count)"))
                    Spacer()
                    Button(picked.count == items.count ? "全不选" : "全选") {
                        picked = picked.count == items.count ? [] : Set(items.map { $0.id })
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            } footer: {
                Text("已存在的相似记忆会自动跳过。")
            }
        }
    }

    func parseDirect() {
        let r = MemoryImport.parse(raw)
        if r.isEmpty {
            note = L10n.tr("没有识别出可导入的内容，可以试试「AI 提炼」")
            return
        }
        show(r)
    }

    func distill() {
        note = ""
        busy = true
        progress = ""
        let text = isChat ? job.chat.joined(separator: "\n") : raw
        work = Task {
            let r = await MemoryImport.distill(text) { progress = $0 }
            busy = false
            if Task.isCancelled { return }
            guard let r else {
                note = L10n.tr("需要先在设置里配置云端大脑或下载本地模型，才能 AI 提炼")
                return
            }
            if r.isEmpty {
                note = L10n.tr("没有提炼出可保留的内容")
                return
            }
            show(r)
        }
    }

    func show(_ r: [MemItem]) {
        items = r
        picked = Set(r.map { $0.id })
        withAnimation { preview = true }
    }

    func commit() {
        let chosen = items.filter { picked.contains($0.id) }
        let label = source.trimmingCharacters(in: .whitespaces).isEmpty ? L10n.tr("其他 AI") : source.trimmingCharacters(in: .whitespaces)
        let added = Memory.addMany(chosen, src: label)
        Evolve.logImport(source: label, added: added, sample: chosen.map { $0.text })
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone(added, chosen.count - added)
        dismiss()
    }
}

// MARK: 全部记忆：搜索、分类筛选、置顶、编辑、删除
struct MemoryListView: View {
    @State private var rows: [Row] = []
    @State private var q = ""
    @State private var cat = "全部"
    @State private var edit: MemEdit?

    private var shown: [Row] {
        let k = q.trimmingCharacters(in: .whitespaces)
        return rows.filter { r in
            (cat == "全部" || r.s("cat") == cat) && (k.isEmpty || r.s("text").localizedCaseInsensitiveContains(k))
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["全部"] + Memory.cats, id: \.self) { c in
                            Button { withAnimation(.snappy(duration: 0.2)) { cat = c } } label: {
                                Text(c)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(cat == c ? Brand.onMint : Brand.ink)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(cat == c ? Brand.mint : Brand.userBubble)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                if shown.isEmpty {
                    Text(rows.isEmpty ? "还没有记忆。去「AI 记忆」导入，或在对话里说「记住……」。" : "没有匹配的记忆")
                        .foregroundStyle(Brand.sub)
                }
                ForEach(shown.indices, id: \.self) { i in row(shown[i]) }
            }
        }
        .navigationTitle("全部记忆")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $q, prompt: Text("搜索记忆"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { edit = MemEdit(rowId: 0, text: "", cat: cat == "全部" ? "其他" : cat, pin: false) } label: { Image(systemName: "plus") }
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $edit, onDismiss: reload) { e in
            MemoryEditSheet(edit: e).presentationBackground(Brand.page)
        }
    }

    func row(_ r: Row) -> some View {
        let id = r.i("id")
        let pinned = r.i("pin") == 1
        return Button {
            edit = MemEdit(rowId: id, text: r.s("text"), cat: r.s("cat"), pin: pinned)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Memory.icon(r.s("cat")))
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.mint)
                    .frame(width: 28, height: 28)
                    .background(Brand.mint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: r.s("text")).font(.system(size: 15.5)).foregroundStyle(Brand.ink).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Brand.mint) }
                        Text(verbatim: r.s("cat") + " · " + r.s("src") + " · " + Sys.friendly(Date(timeIntervalSince1970: r.d("ts"))))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Brand.sub)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Memory.remove(id)
                reload()
            } label: { Label("删除", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                Memory.setPin(id, !pinned)
                reload()
            } label: { Label(pinned ? "取消置顶" : "置顶", systemImage: pinned ? "pin.slash" : "pin") }
                .tint(Brand.mint)
        }
    }

    func reload() { rows = Memory.all() }
}

// MARK: 新增 / 编辑一条记忆
struct MemoryEditSheet: View {
    let edit: MemEdit
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var cat: String
    @State private var pin: Bool

    init(edit: MemEdit) {
        self.edit = edit
        _text = State(initialValue: edit.text)
        _cat = State(initialValue: Memory.cats.contains(edit.cat) ? edit.cat : "其他")
        _pin = State(initialValue: edit.pin)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：我是 iOS 工程师，常用 SwiftUI", text: $text, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Picker("类别", selection: $cat) {
                        ForEach(Memory.cats, id: \.self) { c in Label(c, systemImage: Memory.icon(c)).tag(c) }
                    }
                    Toggle("置顶（每次对话都会带上）", isOn: $pin).tint(Brand.mint)
                }
                if edit.rowId != 0 {
                    Section {
                        Button("删除这条记忆", role: .destructive) {
                            Memory.remove(edit.rowId)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(edit.rowId == 0 ? "添加记忆" : "编辑记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
    }

    func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if edit.rowId == 0 {
            Memory.add(t, cat: cat, src: "手动", pin: pin)
        } else {
            Memory.update(edit.rowId, text: t, cat: cat)
            Memory.setPin(edit.rowId, pin)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}
