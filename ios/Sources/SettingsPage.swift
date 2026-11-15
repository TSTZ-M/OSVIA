import SwiftUI
import FoundationModels

// 设置：主题只保留「跟随系统 / 浅色 / 深色」，默认跟随系统；语言默认跟随系统，可切换到主流语言
struct AppSettingsView: View {
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("style") private var style = 0
    @AppStorage("autoSend") private var autoSend = false
    @AppStorage("liveOn") private var liveOn = true
    @AppStorage("cloudOn") private var cloudOn = true
    @ObservedObject private var local = LocalLLM.shared
    @State private var exportURL: URL?
    @State private var confirmChats = false
    @State private var confirmKB = false
    @State private var showClock = false
    @State private var copied = false

    private let themes: [(Int, String)] = [(0, "跟随系统"), (1, "浅色"), (2, "深色")]

    private var modelStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "可用"
        case .unavailable(let r): return Agent.unavailableText("\(r)")
        @unknown default: return "未知"
        }
    }

    private var localSummary: String {
        local.canUse ? L10n.f("已启用：{}", local.selectedName) : L10n.tr("未启用")
    }

    private var cloudSummary: String {
        cloudOn ? L10n.tr(CloudLLM.summary) : L10n.tr("已关闭")
    }

    var body: some View {
        NavigationStack {
            Form {
                // 三个选项做成系统风格的勾选行：点哪个就立刻切换，勾选状态始终和当前主题一致
                Section("外观") {
                    ForEach(themes, id: \.0) { item in
                        Button {
                            appearance = item.0
                            AppTheme.apply(item.0)
                        } label: {
                            HStack {
                                Text(item.1).foregroundStyle(Brand.ink)
                                Spacer()
                                if appearance == item.0 { Image(systemName: "checkmark").foregroundStyle(Brand.ink) }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                Section("语言") {
                    NavigationLink {
                        LanguagePage()
                    } label: {
                        HStack {
                            Text("应用语言")
                            Spacer()
                            Text(L10n.currentName).foregroundStyle(Brand.sub)
                        }
                    }
                }
                Section("对话") {
                    NavigationLink {
                        CloudPage()
                    } label: {
                        HStack {
                            Text("云端大脑")
                            Spacer()
                            Text(cloudSummary).foregroundStyle(Brand.sub)
                        }
                    }
                    NavigationLink {
                        LocalModelPage()
                    } label: {
                        HStack {
                            Text("本地大模型")
                            Spacer()
                            Text(localSummary).foregroundStyle(Brand.sub)
                        }
                    }
                    Toggle("保存对话记录", isOn: $saveHistory).toggleStyle(SwitchToggleStyle(tint: .green))
                    Picker("回答风格", selection: $style) {
                        Text("简洁").tag(0)
                        Text("详细").tag(1)
                    }
                    Toggle("语音说完后自动发送", isOn: $autoSend).toggleStyle(SwitchToggleStyle(tint: .green))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机模型")
                        Text(modelStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("闹钟与连接") {
                    Button { showClock = true } label: { Label("系统时钟闹钟与自检", systemImage: "alarm") }
                }
                Section("灵动岛与实时活动") {
                    Toggle("在灵动岛显示思考、闹钟与任务倒计时", isOn: $liveOn).toggleStyle(SwitchToggleStyle(tint: .green))
                }
                Section("权限") {
                    Button { openSettings() } label: { Label("通知、闹钟、照片、相机、麦克风等权限", systemImage: "gearshape") }
                }
                Section("诊断") {
                    NavigationLink {
                        DiagView()
                    } label: {
                        HStack {
                            Label("诊断与崩溃线索", systemImage: "stethoscope")
                            if !Diag.lastAbnormal.isEmpty { Spacer(); Text("有记录").font(.footnote).foregroundStyle(.orange) }
                        }
                    }
                }
                Section("数据") {
                    if let u = exportURL {
                        ShareLink(item: u) { Label("导出全部对话", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmChats = true } label: { Label("清空所有对话", systemImage: "trash") }
                    Button(role: .destructive) { confirmKB = true } label: { Label("清空知识库", systemImage: "trash") }
                }
                Section("关于") {
                    HStack(spacing: 12) {
                        LogoMark(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Brand.name).font(.headline)
                            Text(L10n.tr(Brand.tagline) + " · " + L10n.tr("版本") + " 1.0").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("开发者微信")
                        Spacer()
                        Text("TSTZ-M").foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = "TSTZ-M"
                            copied = true
                        } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { exportURL = exportAll() }
            .sheet(isPresented: $showClock) { ClockSetupView().presentationBackground(Brand.page) }
            .confirmationDialog("清空所有对话？此操作无法撤销", isPresented: $confirmChats, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Agent.shared.clearAll() }
            }
            .confirmationDialog("清空知识库？此操作无法撤销", isPresented: $confirmKB, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    DB.shared.run("DELETE FROM chunk")
                    DB.shared.run("DELETE FROM doc")
                }
            }
        }
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    func exportAll() -> URL? {
        var s = "# " + Brand.name + " " + L10n.tr("对话记录") + "\n\n"
        for c in DB.shared.rows("SELECT id,title,ts FROM conv ORDER BY ts") {
            s += "## " + L10n.tr(c.s("title")) + "（" + Sys.fmt(Date(timeIntervalSince1970: c.d("ts"))) + "）\n\n"
            for m in DB.shared.rows("SELECT role,text FROM msg WHERE conv=? ORDER BY id", [c.i("id")]) {
                s += "**" + (m.s("role") == "user" ? L10n.tr("我") : Brand.name) + "**" + L10n.colon + m.s("text") + "\n\n"
            }
        }
        let u = Store.dir("Outputs").appendingPathComponent(Brand.name + " " + L10n.tr("对话记录") + ".md")
        try? s.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}
