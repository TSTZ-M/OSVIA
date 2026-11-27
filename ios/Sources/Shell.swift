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
    @Published var incomingError = ""   // 从其他 App「用 OSVIA 打开」文件失败时的提示，由对话页显示
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

struct ConvItem: Identifiable {
    let id: Int
    let title: String
    let ts: Double
    let pinned: Bool
}

// 侧栏：新对话、搜索（标题和聊天内容）、功能入口网格、置顶与按时间分组的历史对话、设置
struct DrawerView: View {
    let width: CGFloat
    @ObservedObject var agent = Agent.shared
    @ObservedObject var state = AppState.shared
    @Environment(\.dynamicTypeSize) private var dts
    @State private var rows: [ConvItem] = []
    @State private var hits: [Int: String] = [:]
    @State private var q = ""
    @State private var renameId = 0
    @State private var renameText = ""
    @State private var showRename = false

    private let features: [(String, String, AppPage)] = [
        ("brain.head.profile", "AI 记忆", .memory), ("envelope", "邮箱", .mail),
        ("puzzlepiece.extension", "MCP 服务", .mcp), ("books.vertical", "知识库", .kb),
        ("square.grid.2x2", "工具箱", .tools), ("clock.badge.checkmark", "任务", .tasks),
        ("sun.max", "今日回顾", .digest), ("leaf", "进化", .evolve)
    ]

    private var key: String { q.trimmingCharacters(in: .whitespaces) }

    private var shown: [ConvItem] {
        key.isEmpty ? rows : rows.filter { hits[$0.id] != nil || $0.title.localizedCaseInsensitiveContains(key) }
    }

    private var groups: [(name: String, items: [ConvItem])] {
        var out: [(name: String, items: [ConvItem])] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for c in shown {
            let d = Date(timeIntervalSince1970: c.ts)
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: today).day ?? 0
            let name = c.pinned ? "置顶" : (days <= 0 ? "今天" : (days == 1 ? "昨天" : (days < 7 ? "过去 7 天" : (days < 30 ? "过去 30 天" : "更早"))))
            if out.last?.name == name {
                out[out.count - 1].items.append(c)
            } else {
                out.append((name, [c]))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                Text(Brand.name).fontSz(20, weight: .semibold, design: .serif).foregroundStyle(Brand.ink)
                Spacer()
                Button {
                    agent.newChat()
                    state.drawer = false
                } label: {
                    Image(systemName: "square.and.pencil").fontSz(19).foregroundStyle(Brand.ink)
                        .frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .accessibilityLabel("新对话")
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.sub)
                TextField("搜索标题和聊天内容", text: $q).foregroundStyle(Brand.ink).submitLabel(.search)
                if !q.isEmpty {
                    Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.sub) }
                        .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Brand.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if key.isEmpty { featureGrid }
                    if shown.isEmpty {
                        Text(key.isEmpty ? "还没有对话" : "没有匹配的对话").font(.subheadline).foregroundStyle(Brand.sub)
                            .padding(.horizontal, 12).padding(.top, 14)
                    }
                    ForEach(groups, id: \.name) { g in
                        Text(g.name).font(.footnote.weight(.medium)).foregroundStyle(Brand.sub)
                            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                        ForEach(g.items) { c in conv(c) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.immediately)

            Divider().overlay(Brand.line)
            Button { open(.settings) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape").fontSz(18).frame(width: 26)
                    Text("设置").fontSz(17)
                    Spacer()
                }
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.bg)
        .onChange(of: state.drawer) { _, on in if on { reload() } else { hideKeyboard() } }
        .onChange(of: q) { _, _ in hits = key.isEmpty ? [:] : agent.search(key) }
        .onChange(of: agent.title) { _, _ in reload() }
        .onAppear { reload() }
        .alert("重命名对话", isPresented: $showRename) {
            TextField("标题", text: $renameText)
            Button("保存") {
                agent.rename(renameId, renameText)
                reload()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var featureGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: dts.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(features, id: \.2) { f in
                Button { open(f.2) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: f.0).fontSz(18).foregroundStyle(Brand.ink).frame(height: 24)
                        Text(f.1).fontSz(11.5).foregroundStyle(Brand.sub)
                            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Brand.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func reload() {
        rows = agent.convs().map { ConvItem(id: $0.i("id"), title: $0.s("title"), ts: $0.d("ts"), pinned: $0.i("pin") == 1) }
        hits = key.isEmpty ? [:] : agent.search(key)
    }

    func open(_ p: AppPage) {
        state.drawer = false
        state.page = p
    }

    func conv(_ c: ConvItem) -> some View {
        Button {
            agent.open(c.id)
            state.drawer = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: c.title.isEmpty || c.title == "新对话" ? L10n.tr("新对话") : c.title)
                    .fontSz(16)
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                if !key.isEmpty, let hit = hits[c.id] {
                    Text(verbatim: hit).fontSz(12.5).foregroundStyle(Brand.sub).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(c.id == agent.convId ? Brand.userBubble : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .contextMenu {
            Button {
                agent.togglePin(c.id)
                reload()
            } label: { Label(c.pinned ? "取消置顶" : "置顶", systemImage: c.pinned ? "pin.slash" : "pin") }
            Button {
                renameId = c.id
                renameText = c.title
                showRename = true
            } label: { Label("重命名", systemImage: "pencil") }
            Button(role: .destructive) {
                agent.deleteConv(c.id)
                reload()
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
