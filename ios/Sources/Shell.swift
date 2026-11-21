import SwiftUI
import Translation

enum AppPage: String, Identifiable {
    case kb, tools, tasks, digest, evolve, settings, translate, memory, mcp, mail
    var id: String { rawValue }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var drawer = false
    @Published var page: AppPage?
    @Published var tool: ToolRequest?   // 从「+」托盘或聊天快捷操作打开的工具（网页文字、识别文字、去水印……）
    @Published var voiceTick = 0   // 小组件「语音」：数值变化时对话页开始听写
}

// 根界面：参照 Claude，没有底部标签栏。从左边缘右滑或点左上角菜单打开侧栏。
// 语言切换时用 .id(版本号) 让整个界面重新绘制，系统翻译任务挂在这里（需要下载语言包时由系统弹窗）。
struct RootView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var l10n = L10nState.shared

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.84, 330)
            ZStack(alignment: .leading) {
                DrawerView(width: w)
                    .frame(width: w)
                    .id(l10n.version)
                // 注意顺序：点击遮罩必须在 offset 之前加，才会跟着对话页一起右移；
                // 否则它会盖在侧栏上，把侧栏里所有点击都当成「收起侧栏」。
                ChatView()
                    .id(l10n.version)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Brand.bg)
                    .clipShape(RoundedRectangle(cornerRadius: state.drawer ? 24 : 0, style: .continuous))
                    .shadow(color: .black.opacity(state.drawer ? 0.18 : 0), radius: 12)
                    .overlay {
                        if state.drawer {
                            Color.clear.contentShape(Rectangle()).onTapGesture { state.drawer = false }
                        }
                    }
                    .offset(x: state.drawer ? w : 0)
            }
            .background(Brand.bg)
            .animation(.easeOut(duration: 0.25), value: state.drawer)
            .gesture(
                DragGesture(minimumDistance: 24).onEnded { v in
                    let dx = v.translation.width
                    let dy = v.translation.height
                    guard abs(dx) > abs(dy) * 2 else { return }
                    if dx > 60 && v.startLocation.x < 60 {
                        hideKeyboard()
                        state.drawer = true
                    } else if dx < -60 && state.drawer {
                        state.drawer = false
                    }
                }
            )
        }
        .overlay(alignment: .top) { SafetyBanner() }
        .environment(\.locale, L10n.locale)
        .environment(\.layoutDirection, L10n.rtl ? .rightToLeft : .leftToRight)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .translationTask(l10n.config) { session in await l10n.run(session) }
        .onAppear {
            l10n.ensureTranslation()
            StorageInfo.cleanTempAsync()
        }
        .sheet(item: $state.page) { PageSheet(page: $0).id(l10n.version) }
        .sheet(item: $state.tool) { ToolSheet(req: $0).id(l10n.version) }
    }
}

// 侧栏：新对话、搜索、功能入口、历史对话、设置
struct DrawerView: View {
    let width: CGFloat
    @ObservedObject var agent = Agent.shared
    @ObservedObject var state = AppState.shared
    @State private var rows: [Row] = []
    @State private var q = ""
    @State private var renameId = 0
    @State private var renameText = ""
    @State private var showRename = false

    private var shown: [Row] {
        let k = q.trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? rows : rows.filter { $0.s("title").localizedCaseInsensitiveContains(k) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                Text(Brand.name).fontSz(20, weight: .semibold, design: .serif).foregroundStyle(Brand.ink)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.sub)
                TextField("搜索对话", text: $q).foregroundStyle(Brand.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Brand.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    item("square.and.pencil", "新对话") {
                        agent.newChat()
                        state.drawer = false
                    }
                    item("brain.head.profile", "AI 记忆") { open(.memory) }
                    item("envelope", "邮箱") { open(.mail) }
                    item("puzzlepiece.extension", "MCP 服务") { open(.mcp) }
                    item("books.vertical", "知识库") { open(.kb) }
                    item("square.grid.2x2", "工具箱") { open(.tools) }
                    item("clock.badge.checkmark", "任务") { open(.tasks) }
                    item("sun.max", "今日回顾") { open(.digest) }
                    item("leaf", "进化") { open(.evolve) }
                    Text("最近").font(.footnote.weight(.medium)).foregroundStyle(Brand.sub)
                        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
                    if shown.isEmpty {
                        Text(q.isEmpty ? "还没有对话" : "没有匹配的对话").font(.subheadline).foregroundStyle(Brand.sub).padding(.horizontal, 18)
                    }
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, elem in conv(elem) }
                }
                .padding(.horizontal, 6)
            }

            Divider().overlay(Brand.line)
            item("gearshape", "设置") { open(.settings) }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.bg)
        .onChange(of: state.drawer) { _, on in if on { rows = agent.convs() } }
        .onAppear { rows = agent.convs() }
        .alert("重命名对话", isPresented: $showRename) {
            TextField("标题", text: $renameText)
            Button("保存") {
                agent.rename(renameId, renameText)
                rows = agent.convs()
            }
            Button("取消", role: .cancel) {}
        }
    }

    func open(_ p: AppPage) {
        state.drawer = false
        state.page = p
    }

    func item(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).fontSz(18).frame(width: 26).foregroundStyle(Brand.ink)
                Text(title).fontSz(17).foregroundStyle(Brand.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
    }

    func conv(_ r: Row) -> some View {
        let id = r.i("id")
        return Button {
            agent.open(id)
            state.drawer = false
        } label: {
            Text(r.s("title").isEmpty ? "新对话" : r.s("title"))
                .fontSz(16)
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(id == agent.convId ? Brand.userBubble : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                renameId = id
                renameText = r.s("title")
                showRename = true
            } label: { Label("重命名", systemImage: "pencil") }
            Button(role: .destructive) {
                agent.deleteConv(id)
                rows = agent.convs()
            } label: { Label("删除", systemImage: "trash") }
        }
    }
}

// 从侧栏打开的功能页：关闭按钮由 PageChrome.swift 里的 NavigationStack 放在导航栏左侧，不再叠在系统返回键上。
// 底色用系统「分组背景」，列表与表单直接使用系统样式；弹出后再把当前深浅色写一遍，保证和主界面一致。
struct PageSheet: View {
    let page: AppPage
    @AppStorage("appearance") private var appearance = 0

    var body: some View {
        Group {
            switch page {
            case .kb: KBView()
            case .tools: ToolboxView()
            case .tasks: TasksView()
            case .digest: DigestView()
            case .evolve: EvolveHome()
            case .settings: AppSettingsView()
            case .translate: NavigationStack { ScreenTranslateView() }
            case .memory: MemoryHome()
            case .mcp: MCPHome()
            case .mail: MailHome()
            }
        }
        .environment(\.isPageRoot, true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .background(Brand.page.ignoresSafeArea())
        .presentationBackground(Brand.page)
        .onAppear { DispatchQueue.main.async { AppTheme.apply(appearance) } }
    }
}
