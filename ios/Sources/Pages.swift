import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit

// MARK: 知识库
struct KBView: View {
    @ObservedObject var folders = Folders.shared
    @State private var docs: [Row] = []
    @State private var chunks = 0
    @State private var q = ""
    @State private var hits: [String] = []
    @State private var showPicker = false
    @State private var folderMode = false
    @State private var info = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        stat("文档", "\(docs.count)")
                        Divider()
                        stat("知识片段", "\(chunks)")
                    }
                    .frame(height: 56)
                }
                Section("搜索") {
                    TextField("描述你要找的内容", text: $q)
                        .submitLabel(.search)
                        .onSubmit { hits = KB.shared.search(q, k: 5) }
                    ForEach(hits, id: \.self) { Text($0).font(.subheadline).padding(.vertical, 2) }
                }
                Section("我的文档") {
                    if docs.isEmpty { Text("还没有文档，点右上角「导入」").foregroundStyle(.secondary) }
                    ForEach(docs.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Image(systemName: icon(docs[i].s("name"))).foregroundStyle(Color.accentColor).frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(docs[i].s("name"))).lineLimit(1)
                                Text("\(docs[i].i("n")) 个片段").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { idx in
                        for i in idx { KB.shared.delete(docs[i].i("id")) }
                        reload()
                    }
                    if !info.isEmpty { Text(info).foregroundStyle(Color.accentColor) }
                }
                Section("已授权的文件夹（助理可查找、读取）") {
                    ForEach(Array(folders.names.enumerated()), id: \.offset) { _, n in
                        Label(n, systemImage: "folder")
                    }
                    .onDelete { idx in for i in idx { folders.remove(at: i) } }
                    Button {
                        folderMode = true
                        showPicker = true
                    } label: { Label("授权文件夹", systemImage: "folder.badge.plus") }
                }
            }
            .navigationTitle("知识库")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        folderMode = false
                        showPicker = true
                    } label: { Label("导入", systemImage: "plus") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: folderMode ? [.folder] : [.item], allowsMultipleSelection: true) { r in
                let urls = (try? r.get()) ?? []
                if folderMode {
                    for u in urls { folders.add(u) }
                    info = urls.isEmpty ? "" : "已授权 \(urls.count) 个文件夹"
                } else {
                    var n = 0
                    for u in urls { n += KB.shared.ingest(u) > 0 ? 1 : 0 }
                    info = "已导入 \(n) 个文档"
                }
                reload()
            }
            .onAppear(perform: reload)
        }
    }

    func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title2.bold())
            Text(t).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func title(_ n: String) -> String {
        if n == "记忆" { return "我的记忆" }
        if n == "进化提炼" { return "进化提炼的记忆" }
        if n.hasPrefix("技能:") { return "脚本技能 · " + n.dropFirst(3) }
        return n
    }

    func icon(_ n: String) -> String {
        if n == "记忆" || n == "进化提炼" { return "brain" }
        if n.hasPrefix("技能:") { return "wand.and.stars" }
        let e = (n as NSString).pathExtension.lowercased()
        if e == "pdf" { return "doc.richtext" }
        if ["csv", "tsv", "json"].contains(e) { return "tablecells" }
        return "doc.text"
    }

    func reload() {
        docs = KB.shared.docs()
        chunks = DB.shared.rows("SELECT COUNT(*) AS n FROM chunk").first?.i("n") ?? 0
    }
}

// MARK: 工具箱
struct ToolboxView: View {
    @State private var showClock = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                    card("屏幕翻译", "截图一键翻译整屏，译文贴回原位", "character.bubble") { ScreenTranslateView() }
                    card("文件转换", "图片、PDF、表格、视频互相转换", "arrow.triangle.2.circlepath") { ConvertView() }
                    card("脚本技能", "一句话生成处理文字的小脚本", "wand.and.stars") { SkillsView() }
                    card("连接器", "连接快捷指令、Scriptable 和各种接口", "link") { ConnectorsView() }
                    card("快捷指令", "把本 App 的动作加入系统快捷指令", "square.stack.3d.up.fill") { ShortcutsView() }
                    Button { showClock = true } label: { cardBody("系统时钟闹钟", "把闹钟写进「时钟」，并自检内置闹钟", "alarm") }
                }
                .padding(16)
            }
            .background(Brand.page)
            .navigationTitle("工具箱")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showClock) { ClockSetupView().presentationBackground(Brand.page) }
        }
    }

    func cardBody(_ t: String, _ s: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(Brand.ink)
                .frame(width: 46, height: 46).background(Brand.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(t).font(.headline).foregroundStyle(Brand.ink)
            Text(s).font(.subheadline).foregroundStyle(Brand.sub).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func card<D: View>(_ t: String, _ s: String, _ icon: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            cardBody(t, s, icon)
        }
    }
}

// 「文件转换」页面在 ConvertUI.swift（支持从相册选照片和视频）

// MARK: 脚本技能
struct SkillsView: View {
    @State private var skills: [Row] = []
    @State private var spec = ""
    @State private var busy = false
    @State private var status = ""
    @State private var result: (name: String, ok: Bool, out: String)?
    @State private var showPack = false

    var body: some View {
        List {
            Section {
                Text("脚本技能是处理文字的小脚本：整理文案、提取要点、批量改写、格式转换等。它看不到屏幕，也不能操作别的 App；翻译截图请用「屏幕翻译」。")
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
                            Label("已创建「\(r.name)」并运行成功", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("运行结果：" + r.out).textSelection(.enabled)
                        }
                    } else {
                        Label("没能生成可运行的脚本（\(r.out)），请换个描述再试一次", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Section("我的技能") {
                if skills.isEmpty { Text("还没有技能，先在上面创建一个").foregroundStyle(.secondary) }
                ForEach(skills.indices, id: \.self) { i in
                    NavigationLink {
                        SkillRunView(name: skills[i].s("name"))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skills[i].s("name")).font(.headline)
                            Text(skills[i].s("desc")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in
                    for i in idx { Skills.remove(skills[i].s("name")) }
                    reload()
                }
            }
            Section {
                Button { showPack = true } label: { Label("导入技能包", systemImage: "square.and.arrow.down") }
            }
        }
        .navigationTitle("脚本技能")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
        .fileImporter(isPresented: $showPack, allowedContentTypes: [.json]) { r in
            if let u = try? r.get() { Skills.importPack(u); reload() }
        }
        .onAppear(perform: reload)
    }

    func reload() { skills = Skills.list() }

    func create() {
        let s = spec
        hideKeyboard()
        busy = true
        result = nil
        status = "准备中…"
        Task {
            let r = await Skills.create(s) { msg in DispatchQueue.main.async { status = msg } }
            result = r
            busy = false
            if r.ok { spec = "" }
            reload()
        }
    }
}

struct SkillRunView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var out = ""
    @State private var ok = true
    @State private var copied = false
    @State private var desc = ""

    // 名字像「屏幕翻译」的旧技能：脚本读不到屏幕，引导到新版
    private var looksLikeScreenTranslate: Bool {
        name.contains("翻译") && (name.contains("屏") || name.contains("截"))
    }

    private var link: String {
        let n = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return "osvia://run?name=\(n)&input="
    }

    var body: some View {
        List {
            if !desc.isEmpty {
                Section("这个技能做什么") { Text(desc) }
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
                Button { run() } label: { Label("运行", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
            }
            if !out.isEmpty {
                Section("运行结果") {
                    Text(out).textSelection(.enabled).foregroundStyle(ok ? Color.primary : Color.red)
                }
            }
            Section("怎么用") {
                Text("① 在上面「输入内容」里填要处理的文字，点「运行」。\n② 在对话里说：运行 \(name) 加上要处理的内容。\n③ 给快捷指令或其他 App 用：点下面「复制调用链接」，在链接末尾 input= 后面接上要处理的文字。\n注意：调用链接是给别的 App 用的，不要粘贴到上面的输入框里。")
                    .font(.subheadline)
            }
            Section("给其他应用调用") {
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: { Label(copied ? "已复制调用链接" : "复制调用链接", systemImage: "link") }
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
        .onAppear { desc = Skills.list().first { $0.s("name") == name }?.s("desc") ?? "" }
    }

    func run() {
        hideKeyboard()
        copied = false
        if input.hasPrefix("osvia://") {
            ok = false
            out = "这里要填的是要处理的文字，不是调用链接。调用链接是给快捷指令或其他 App 用的。请清空后重新输入。"
            return
        }
        let r = Skills.run(name, input)
        ok = r.0
        if !r.0 && r.1.contains("没有返回") {
            out = input.isEmpty
                ? "这个技能需要输入内容：请先在上面「输入内容」里填写要处理的文字，再点运行。"
                : "脚本运行了但没有产出结果，可能不适合这段输入。可以换一段文字试试，或删除后用一句话重新创建。"
        } else {
            out = r.1
        }
    }
}

// MARK: 连接器
struct ConnectorsView: View {
    @State private var rows: [Row] = []
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                Text("连接本机已有的应用或网络接口，让助理在对话里直接调用，例如说「用快捷指令 XX 处理这段话」。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("已连接") {
                if rows.isEmpty { Text("还没有连接器，点右上角添加").foregroundStyle(.secondary) }
                ForEach(rows.indices, id: \.self) { i in
                    NavigationLink {
                        ConnectorRunView(name: rows[i].s("name"))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rows[i].s("name")).font(.headline)
                            Text(Connectors.kindName(rows[i].s("kind"))).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { idx in
                    for i in idx { Connectors.remove(rows[i].i("id")) }
                    reload()
                }
            }
        }
        .navigationTitle("连接器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd, onDismiss: reload) { AddConnectorView() }
        .onAppear(perform: reload)
    }

    func reload() { rows = Connectors.all() }
}

struct AddConnectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "shortcut"
    @State private var name = ""
    @State private var target = ""
    @State private var method = "GET"
    @State private var headers = ""
    @State private var bodyText = ""

    var hint: String {
        switch kind {
        case "shortcut": return "快捷指令的名称"
        case "scriptable": return "Scriptable 脚本的名称"
        case "url": return "目标应用的网址，用 [内容] 代表传入的文字"
        default: return "接口地址，用 [内容] 代表传入的文字"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $kind) {
                        Text("快捷指令").tag("shortcut")
                        Text("Scriptable 脚本").tag("scriptable")
                        Text("其他 App").tag("url")
                        Text("网络接口").tag("http")
                    }
                    .pickerStyle(.menu)
                }
                Section("名称（对话里用它来调用）") { TextField("例如：整理文字", text: $name) }
                Section(hint) { TextField("请输入", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if kind == "http" {
                    Section("请求方式") {
                        Picker("方式", selection: $method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("请求头（每行一项，写成 名称: 值）") { TextEditor(text: $headers).frame(minHeight: 70) }
                    if method == "POST" { Section("发送内容（用 [内容] 代表传入的文字）") { TextEditor(text: $bodyText).frame(minHeight: 90) } }
                }
            }
            .navigationTitle("添加连接器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Connectors.add(
                            name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                            url: target.replacingOccurrences(of: "[内容]", with: "{{input}}"),
                            method: method, headers: headers,
                            body: bodyText.replacingOccurrences(of: "[内容]", with: "{{input}}")
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationBackground(Brand.page)
    }
}

struct ConnectorRunView: View {
    let name: String
    @State private var input = ""
    @State private var out = ""
    @State private var busy = false

    var body: some View {
        List {
            Section("传入内容") { TextField("可以留空", text: $input, axis: .vertical).lineLimit(1...5) }
            Section {
                Button {
                    hideKeyboard()
                    busy = true
                    Task {
                        out = await Connectors.run(name, input)
                        busy = false
                    }
                } label: {
                    HStack { if busy { ProgressView() }; Text(busy ? "调用中…" : "调用").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .listRowBackground(Color.clear)
            }
            if !out.isEmpty { Section("返回结果") { Text(out).textSelection(.enabled) } }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { hideKeyboard() } } }
    }
}

// MARK: 快捷指令
struct ShortcutsView: View {
    @State private var copied = ""

    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "shortcuts://")!) { Label("打开快捷指令", systemImage: "square.stack.3d.up") }
                Link(destination: URL(string: "shortcuts://create-shortcut")!) { Label("新建快捷指令", systemImage: "plus.square") }
            }
            Section("本 App 提供的动作") {
                action("sparkles", "询问助理", "把一句话交给助理，拿到回答")
                action("character.bubble", "翻译屏幕", "接收「截屏」的结果，翻译后把译文贴回原图")
                action("magnifyingglass", "检索知识库", "按语义查找知识库内容")
                action("tray.and.arrow.down", "加入知识库", "把文字存进知识库")
                action("wand.and.stars", "运行脚本技能", "运行你创建的脚本并返回结果")
                action("bell", "N 分钟后提醒", "几分钟后发送通知提醒")
            }
            Section("怎么用") {
                Text("1. 打开快捷指令，点右上角加号新建\n2. 点「添加操作」，搜索 \(Brand.name)\n3. 选择上面的动作，再接上你想要的步骤\n4. 在「自动化」里设置时间，就能定时自动运行")
                    .font(.subheadline)
            }
            Section("让其他应用调用本 App") {
                Button { copy("osvia://ask?q=", "提问") } label: { Label(copied == "提问" ? "已复制提问链接" : "复制「提问」链接", systemImage: "link") }
                Button { copy("osvia://run?name=", "运行") } label: { Label(copied == "运行" ? "已复制运行链接" : "复制「运行脚本」链接", systemImage: "link") }
            }
        }
        .navigationTitle("快捷指令")
        .navigationBarTitleDisplayMode(.inline)
    }

    func copy(_ s: String, _ k: String) {
        UIPasteboard.general.string = s
        copied = k
    }

    func action(_ icon: String, _ t: String, _ d: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t)
                Text(d).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
