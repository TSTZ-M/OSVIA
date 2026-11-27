import SwiftUI
import QuickLook
import UniformTypeIdentifiers

// MARK: 对话页（排版参照 Claude：顶部菜单与新对话，回答直接排在页面上，底部圆角输入卡片）
struct ChatView: View {
    @ObservedObject var agent = Agent.shared
    @ObservedObject var state = AppState.shared
    @StateObject private var voice = Voice()
    @AppStorage("autoSend") private var autoSend = false
    @State private var input = ""
    @State private var showPhoto = false
    @State private var showCamera = false
    @State private var showFile = false
    @State private var showShare = false
    @State private var showClock = false
    @State private var showTray = false
    @State private var showConnectors = false
    @State private var conns: [Row] = []
    @State private var activeConn = ""
    @State private var notice = ""
    @State private var preview: URL?
    @State private var memCount = 0
    @State private var mcpCount = 0
    @State private var editing: UUID?
    @State private var pos = ScrollPosition(edge: .bottom)
    @State private var follow = true      // 是否跟着新内容往下滚；用户往上翻看时不打扰
    @State private var atBottom = true
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var askConsent = false
    @FocusState private var focus: Bool

    private let ideas: [(String, String)] = [
        ("magnifyingglass", "今天有什么重要的科技新闻？"),
        ("function", "房贷 120 万，30 年，利率 3.1%，月供多少？"),
        ("alarm", "明早十点叫我起床"),
        ("wand.and.stars", "做一份本周学习计划，导出成 PDF"),
        ("envelope", "看看有什么要紧的邮件，该回的帮我起草")
    ]

    private func refreshCounts() {
        memCount = Memory.count()
        mcpCount = MCP.servers().filter { $0.i("enabled") == 1 }.count
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var title: String {
        if agent.msgs.isEmpty { return Brand.name }
        if !agent.title.isEmpty, agent.title != "新对话" { return agent.title }
        if let t = agent.msgs.first(where: { $0.role == "user" })?.text, !t.isEmpty { return String(t.prefix(14)) }
        return Brand.name
    }

    private var titleText: some View {
        Text(verbatim: title).fontSz(17, weight: .semibold, design: .serif).foregroundStyle(Brand.ink).lineLimit(1)
    }

    // 点标题：重命名、置顶、删除当前对话
    @ViewBuilder private var titleMenu: some View {
        if agent.msgs.isEmpty || agent.convId == 0 {
            titleText
        } else {
            Menu {
                Button {
                    renameText = title
                    showRename = true
                } label: { Label("重命名", systemImage: "pencil") }
                Button { agent.togglePin(agent.convId) } label: {
                    Label(agent.pinned ? "取消置顶" : "置顶", systemImage: agent.pinned ? "pin.slash" : "pin")
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
            } label: {
                HStack(spacing: 4) {
                    titleText
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.sub)
                }
                .frame(maxWidth: 210)
            }
        }
    }

    var body: some View {
        NavigationStack {
            conversation
                .background(Brand.bg)
                .safeAreaBar(edge: .bottom, spacing: 0) { inputBar }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            hideKeyboard()
                            state.drawer = true
                        } label: { Image(systemName: "line.3.horizontal").foregroundStyle(Brand.ink) }
                        .accessibilityLabel("菜单")
                    }
                    ToolbarItem(placement: .principal) { titleMenu }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showShare = true } label: { Image(systemName: "square.and.arrow.up").foregroundStyle(Brand.ink) }
                            .disabled(agent.msgs.isEmpty)
                            .accessibilityLabel("分享对话")
                        Button { agent.newChat() } label: { Image(systemName: "square.and.pencil").foregroundStyle(Brand.ink) }
                            .accessibilityLabel("新对话")
                    }
                }
                .sheet(isPresented: $showShare) { ShareView() }
                .sheet(isPresented: $showClock) { ClockSetupView().presentationBackground(Brand.bg) }
                .sheet(isPresented: $showConnectors, onDismiss: { conns = Connectors.all() }) {
                    ConnectorHub { activeConn = $0.s("name") }.presentationBackground(Brand.bg)
                }
                .sheet(isPresented: $showPhoto) {
                    GalleryPicker(onPick: { urls in
                        for u in urls { agent.attachments.append(Attach(url: u)) }
                    }, onError: { warn($0) })
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { u, err in
                        showCamera = false
                        if let u {
                            agent.attachments.append(Attach(url: u))
                        } else if let err {
                            warn(err)
                        }
                    }
                    .ignoresSafeArea()
                }
                .fileImporter(isPresented: $showFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
                    switch r {
                    case .success(let urls):
                        Task { @MainActor in
                            for u in urls {
                                let res = await Files.importFileAsync(u)
                                if let c = res.url { agent.attachments.append(Attach(url: c)) } else if let e = res.error { warn(e) }
                            }
                        }
                    case .failure(let e):
                        warn("无法打开文件：\(e.localizedDescription)")
                    }
                }
                .quickLookPreview($preview)
                .onChange(of: state.incomingError) { _, e in
                    guard !e.isEmpty else { return }
                    warn(e)
                    state.incomingError = ""
                }
                .alert(agent.confirm?.title ?? "", isPresented: Binding(
                    get: { agent.confirm != nil },
                    set: { if !$0 { agent.answerConfirm(false) } }
                )) {
                    Button("允许") { agent.answerConfirm(true) }
                    Button("拒绝", role: .cancel) { agent.answerConfirm(false) }
                } message: {
                    Text(verbatim: agent.confirm?.detail ?? "")
                }
                .onChange(of: focus) { _, f in if f { showTray = false } }
                .onChange(of: state.page) { _, p in if p == nil { refreshCounts() } }
                .onChange(of: state.voiceTick) { _, _ in voice.start() }
                .onChange(of: input) { _, v in UserDefaults.standard.set(v, forKey: "chat.draft") }
                .onChange(of: agent.convId) { _, _ in
                    editing = nil
                    follow = true
                    pos.scrollTo(edge: .bottom)
                }
                .onAppear {
                    refreshCounts()
                    conns = Connectors.all()
                    if input.isEmpty { input = UserDefaults.standard.string(forKey: "chat.draft") ?? "" }
                    voice.onText = { input = $0 }
                    voice.onFinished = { t in if autoSend && !t.isEmpty { send() } }
                }
        }
    }

    // 消息区 + 当前对话的重命名、删除弹窗（单独拆出来，避免 body 过大拖慢类型检查）
    private var conversation: some View {
        messageList
            .alert("重命名对话", isPresented: $showRename) {
                TextField("标题", text: $renameText)
                Button("保存") { agent.rename(agent.convId, renameText) }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("删除这段对话？此操作无法撤销", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { agent.deleteConv(agent.convId) }
            }
            // 第一次要把内容发给第三方 AI 之前，明确征求同意
            .alert(L10n.f("把内容发给 {}？", CloudLLM.providerName), isPresented: $askConsent) {
                Button("同意并发送") {
                    CloudLLM.setConsent(true)
                    send()
                }
                Button("只用本机回答") {
                    CloudLLM.setConsent(false)
                    send()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你的提问、对话历史、相关记忆和附件文字会直接从手机发给该服务商用于生成回答。可随时在 设置 → 云端大脑 里关闭。")
            }
    }

    // MARK: 消息列表
    @ViewBuilder var messageList: some View {
        if agent.msgs.isEmpty {
            ScrollView { emptyState.padding(.bottom, 12) }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { if showTray { showTray = false } })
        } else {
            chatList
        }
    }

    var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(agent.msgs) { m in
                    MessageView(m: m, isLast: m.id == agent.msgs.last?.id, preview: $preview,
                                onRegenerate: { agent.regenerate() },
                                onEdit: { beginEdit(m) },
                                onAsk: { agent.followUp(L10n.tr($0)) })
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollPosition($pos)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { if showTray { showTray = false } })
        .onScrollGeometryChange(for: Bool.self) { g in
            g.visibleRect.maxY >= g.contentSize.height - 40
        } action: { _, v in atBottom = v }
        .onScrollPhaseChange { old, new, ctx in
            if new == .interacting {
                follow = false
            } else if new == .idle && (old == .interacting || old == .decelerating) {
                follow = ctx.geometry.visibleRect.maxY >= ctx.geometry.contentSize.height - 40
            }
        }
        .onChange(of: agent.msgs.count) { _, _ in
            follow = true
            pos.scrollTo(edge: .bottom)
        }
        .onChange(of: agent.msgs.last?.text) { _, _ in stick() }
        .onChange(of: agent.msgs.last?.steps) { _, _ in stick() }
        .onChange(of: agent.msgs.last?.streaming) { _, _ in stick() }
        .onChange(of: focus) { _, f in
            guard f, follow else { return }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                stick()
            }
        }
        .overlay(alignment: .bottom) {
            if !follow && !atBottom {
                Button {
                    follow = true
                    withAnimation(.snappy) { pos.scrollTo(edge: .bottom) }
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(.bottom, 8)
                .accessibilityLabel("回到底部")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: follow)
    }

    private func stick() {
        if follow { pos.scrollTo(edge: .bottom) }
    }

    private func beginEdit(_ m: Msg) {
        guard !agent.busy else { return }
        editing = m.id
        input = m.text
        agent.attachments = m.files.map { Attach(url: $0) }
        focus = true
    }

    var editChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil").foregroundStyle(Brand.mint)
            Text("正在编辑：发送后替换这条及之后的内容").font(.footnote).foregroundStyle(Brand.sub)
            Spacer(minLength: 4)
            Button {
                editing = nil
                input = ""
                agent.attachments = []
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.sub).frame(minWidth: 32, minHeight: 32) }
                .accessibilityLabel("取消编辑")
        }
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoMark(size: 48).padding(.top, 36)
            Text("\(greeting)，我是\(Brand.name)")
                .fontSz(30, weight: .regular, design: .serif)
                .foregroundStyle(Brand.ink)
            Text("能联网查证、读网页、精确计算，记得你的偏好，还能连接 MCP 工具。")
                .font(Brand.serif)
                .foregroundStyle(Brand.sub)
            HStack(spacing: 10) {
                featureCard("brain.head.profile", "AI 记忆",
                            memCount > 0 ? L10n.f("已记住 {} 条", "\(memCount)") : L10n.tr("从其他 AI 带来你的记忆")) { state.page = .memory }
                featureCard("puzzlepiece.extension", "MCP 服务",
                            mcpCount > 0 ? L10n.f("已启用 {} 个", "\(mcpCount)") : L10n.tr("连接外部工具与数据")) { state.page = .mcp }
            }
            .padding(.top, 4)
            Text("试试这样说").fontSz(12.5, weight: .semibold).foregroundStyle(Brand.sub).padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(ideas, id: \.1) { idea in
                    Button {
                        input = L10n.tr(idea.1)
                        focus = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: idea.0).fontSz(15).foregroundStyle(Brand.mint).frame(width: 24)
                            Text(idea.1).fontSz(15.5).foregroundStyle(Brand.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Brand.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    func featureCard(_ icon: String, _ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.mint)
                    .frame(width: 34, height: 34)
                    .background(Brand.mint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).fontSz(15.5, weight: .semibold).foregroundStyle(Brand.ink)
                Text(verbatim: sub).fontSz(12.5).foregroundStyle(Brand.sub).multilineTextAlignment(.leading).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(Brand.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: 输入栏 = 输入卡片 + 展开的托盘（托盘在输入框下面，聊天内容自动上移，不遮挡）
    var inputBar: some View {
        VStack(spacing: 0) {
            inputCard
            if showTray && !voice.listening {
                AttachTray(
                    conns: conns, activeConn: activeConn,
                    onCamera: { closeTray { showCamera = true } },
                    onPhoto: { closeTray { showPhoto = true } },
                    onFile: { closeTray { showFile = true } },
                    onPaste: { closeTray { paste() } },
                    onTool: { k in closeTray { state.tool = ToolRequest(kind: k, files: agent.attachments.map { $0.url }) } },
                    onPage: { p in closeTray { state.page = p } },
                    onClock: { closeTray { showClock = true } },
                    onConn: { n in closeTray { activeConn = activeConn == n ? "" : n } },
                    onConnManage: { closeTray { showConnectors = true } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(showTray ? Brand.bg : Color.clear)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: showTray)
    }

    func closeTray(_ then: @escaping () -> Void) {
        showTray = false
        then()
    }

    var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !voice.error.isEmpty { Text(voice.error).font(.footnote).foregroundStyle(.red) }
            if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(.red) }
            if editing != nil { editChip }
            if !activeConn.isEmpty { connChip }
            if !agent.attachments.isEmpty { attachmentRow }
            if voice.listening {
                listeningBar
            } else {
                TextField(activeConn.isEmpty ? "发消息给 \(Brand.name)" : "发给「\(activeConn)」的内容", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focus)
                    .fontSz(17)
                    .foregroundStyle(Brand.ink)
                HStack(spacing: 8) {
                    plusButton
                    ModelPill()
                    Spacer(minLength: 4)
                    actionButton
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // 当前选中的连接器：之后发送的内容都会交给它，点 × 退出
    var connChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(Brand.ink)
            Text(activeConn).font(.subheadline.weight(.medium)).foregroundStyle(Brand.ink)
            let h = Connectors.hint(activeConn)
            if !h.isEmpty { Text(h).font(.footnote).foregroundStyle(Brand.sub).lineLimit(1) }
            Spacer()
            Button { activeConn = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.sub).frame(minWidth: 32, minHeight: 32) }
                .accessibilityLabel("退出连接器")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Brand.userBubble)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var plusButton: some View {
        Button {
            focus = false
            UISelectionFeedbackGenerator().selectionChanged()
            showTray.toggle()
        } label: {
            Image(systemName: activeConn.isEmpty ? "plus" : "link")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Brand.ink)
                .rotationEffect(.degrees(showTray && activeConn.isEmpty ? 45 : 0))
                .frame(width: 36, height: 36)
                .background(showTray ? Brand.userBubble : Color.clear)
                .clipShape(Circle())
                .overlay(Circle().stroke(Brand.line, lineWidth: 1))
        }
        .accessibilityLabel("添加")
    }

    // 空 → 语音；有内容 → 发送；生成中 → 停止
    var actionButton: some View {
        let empty = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.attachments.isEmpty
        return Button {
            if agent.busy {
                agent.stop()
            } else if empty {
                focus = false
                voice.start()
            } else {
                send()
            }
        } label: {
            Image(systemName: agent.busy ? "stop.fill" : (empty ? "mic.fill" : "arrow.up"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(empty && !agent.busy ? Brand.onAccent : Brand.onMint)
                .frame(width: 36, height: 36)
                .background(empty && !agent.busy ? Brand.accent : Brand.mint)
                .clipShape(Circle())
                .animation(.easeOut(duration: 0.15), value: empty)
        }
        .accessibilityLabel(agent.busy ? "停止" : (empty ? "语音输入" : "发送"))
    }

    var listeningBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { i in
                    Capsule().fill(Brand.ink)
                        .frame(width: 3, height: 8 + voice.level * 22 * CGFloat(abs(sin(Double(i) * 0.9))))
                }
            }
            .frame(height: 34)
            .animation(.easeOut(duration: 0.1), value: voice.level)
            Text(voice.live.isEmpty ? "正在聆听，说完点右边按钮" : voice.live)
                .foregroundStyle(Brand.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { voice.stop() } label: {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.onAccent)
                    .frame(width: 36, height: 36).background(Brand.accent).clipShape(Circle())
            }
            .accessibilityLabel("完成")
        }
    }

    var attachmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(agent.attachments) { a in
                        ZStack(alignment: .topTrailing) {
                            thumb(a.url).onTapGesture { preview = a.url }
                            Button { agent.attachments.removeAll { $0.id == a.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, Color.black.opacity(0.6))
                                    .padding(6).contentShape(Rectangle())
                            }
                            .accessibilityLabel("移除附件")
                            .offset(x: 10, y: -10)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            if !chipItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chipItems, id: \.1) { c in chip(c.0, c.1) }
                    }
                }
            }
        }
    }

    // 根据附件类型给出一键操作：不经过大模型，点了直接做
    var chipItems: [(String, String)] {
        let urls = agent.attachments.map { $0.url }
        guard let f = urls.first else { return [] }
        let e = f.pathExtension.lowercased()
        func conv(_ t: String) -> (String, String) {
            switch t {
            case "compress": return ("压缩", "conv:compress")
            case "mute": return ("去除声音", "conv:mute")
            case "m4a": return (Convert.vidExt.contains(e) ? "提取音频" : "转音频", "conv:m4a")
            default: return ("转" + (ConvertView.short[t] ?? t), "conv:" + t)
            }
        }
        if urls.allSatisfy({ Files.isImage($0) }) {
            return [("识别文字", "ocr"), ("表格识别", "table"), ("翻译图片", "trans"), ("去水印", "wm"), ("抠图", "cutout"), ("打码", "redact"), ("读二维码", "qr"), ("图片处理", "imgedit"), conv("pdf"), conv("docx")]
        }
        if Convert.vidExt.contains(e) {
            return [("转文字", "transcribe"), ("剪辑", "media"), conv("m4a"), conv("mute"), ("去水印", "wmv"), conv("compress"), conv("wav")]
        }
        var list = Convert.targets(for: e).prefix(4).map { conv($0) }
        if Convert.audExt.contains(e) {
            list.insert(("转文字", "transcribe"), at: 0)
            list.insert(("剪辑", "media"), at: 1)
        }
        if e == "pdf" {
            list.insert(("识别文字", "ocrpdf"), at: 0)
            list.insert(("表格识别", "table"), at: 1)
            list.insert(("PDF 工具", "pdftool"), at: 2)
        }
        list.append(("更多", "more"))
        return list
    }

    func thumb(_ u: URL) -> some View {
        Group {
            if Files.isImage(u), let ui = Files.thumb(u, max: 180) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if Files.isImage(u) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.red)
            } else {
                Image(systemName: "doc").font(.title2).foregroundStyle(Brand.ink)
            }
        }
        .frame(width: 60, height: 60)
        .background(Brand.userBubble)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func chip(_ t: String, _ key: String) -> some View {
        Button(t) { runChip(key, t) }
            .font(.subheadline)
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Brand.userBubble)
            .clipShape(Capsule())
    }

    func runChip(_ key: String, _ title: String) {
        let urls = agent.attachments.map { $0.url }
        guard !urls.isEmpty, !agent.busy else { return }
        focus = false
        showTray = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case "ocr":
            Task { await agent.recognize(urls) }
        case "ocrpdf":
            Task { await agent.quickConvert(urls, to: "txt", label: "识别文字") }
        case "trans":
            guard let u = urls.first(where: { Files.isImage($0) }), let d = Files.normalizedJPEG(from: u, maxPixel: 3000) else { return }
            agent.attachments = []
            ScreenTranslator.shared.request(data: d)
        case "table": state.tool = ToolRequest(kind: .table, files: urls)
        case "wm": state.tool = ToolRequest(kind: .wmImage, files: urls)
        case "wmv": state.tool = ToolRequest(kind: .wmVideo, files: urls)
        case "cutout": state.tool = ToolRequest(kind: .cutout, files: urls)
        case "redact": state.tool = ToolRequest(kind: .redact, files: urls)
        case "qr": state.tool = ToolRequest(kind: .qr, files: urls)
        case "imgedit": state.tool = ToolRequest(kind: .imageEdit, files: urls)
        case "pdftool": state.tool = ToolRequest(kind: .pdf, files: urls)
        case "transcribe": state.tool = ToolRequest(kind: .transcribe, files: urls)
        case "media": state.tool = ToolRequest(kind: .media, files: urls)
        case "more": state.tool = ToolRequest(kind: .convert, files: urls)
        default:
            if key.hasPrefix("conv:") {
                let t = String(key.dropFirst(5))
                Task { await agent.quickConvert(urls, to: t, label: title) }
            }
        }
    }

    // MARK: 发送：识别文字 → 当前连接器 → 「用 XX 查 YY」→ 普通对话
    func send() {
        if CloudLLM.needsConsent && (ModelPref.mode == .auto || ModelPref.mode == .cloud) {
            focus = false
            askConsent = true
            return
        }
        let t = input
        let files = agent.attachments.map { $0.url }
        input = ""
        focus = false
        showTray = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if voice.listening { voice.stop() }
        if let e = editing {
            editing = nil
            agent.rewind(e)
        }
        if t.trimmingCharacters(in: .whitespaces) == "识别文字", !files.isEmpty, files.allSatisfy({ Files.isImage($0) }) {
            Task { await agent.recognize(files) }
            return
        }
        if files.isEmpty, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !activeConn.isEmpty {
                let name = activeConn
                Task { await agent.runConnector(name, t) }
                return
            }
            if let m = Connectors.match(t) {
                let name = m.0.s("name")
                Task { await agent.runConnector(name, m.1, shown: t) }
                return
            }
        }
        agent.start(t)
    }

    func warn(_ s: String) {
        notice = s
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if notice == s { notice = "" }
        }
    }

    func paste() {
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            guard let d = Files.jpeg(from: img) else { warn("剪贴板里的图片无法读取"); return }
            let s = Files.save(d, name: "粘贴图片-\(Files.stampText()).jpg")
            if let u = s.url {
                agent.attachments.append(Attach(url: u))
            } else {
                warn("剪贴板里的图片保存失败（\(s.error)）")
            }
        } else if let s = pb.string, !s.isEmpty {
            input += s
            focus = true
        } else {
            warn("剪贴板是空的")
        }
    }
}
