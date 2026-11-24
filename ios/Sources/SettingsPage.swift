import SwiftUI
import FoundationModels

// 设置：主题只保留「跟随系统 / 浅色 / 深色」，默认跟随系统；语言默认跟随系统，可切换到主流语言
struct AppSettingsView: View {
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("style") private var style = 0
    @AppStorage("autoSend") private var autoSend = false
    @AppStorage("liveOn") private var liveOn = true
    @AppStorage("bark.on") private var barkOn = false
    @AppStorage("cloudOn") private var cloudOn = true
    @AppStorage("modelMode") private var modeRaw = "auto"
    @AppStorage("transTarget") private var transTarget = "auto"
    @ObservedObject private var local = LocalLLM.shared
    @ObservedObject private var state = AppState.shared
    @State private var exportURL: URL?
    @State private var confirmChats = false
    @State private var confirmKB = false
    @State private var showClock = false
    @State private var copied = false

    private let themes: [(Int, String)] = [(0, "跟随系统"), (1, "浅色"), (2, "深色")]
    private let transLangs: [(String, String)] = [("auto", "自动"), ("zh-Hans", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"),
                                                  ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"), ("ru", "Русский")]

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    // 系统设置风格的图标行
    private func badge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 29, height: 29).background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func row(_ icon: String, _ color: Color, _ title: String, value: String = "") -> some View {
        HStack(spacing: 12) {
            badge(icon, color)
            Text(title).foregroundStyle(Brand.ink)
            if !value.isEmpty {
                Spacer(minLength: 8)
                Text(verbatim: value).foregroundStyle(Brand.sub).lineLimit(1)
            }
        }
    }

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
                // 顶部：应用信息
                Section {
                    HStack(spacing: 14) {
                        LogoMark(size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Brand.name).font(.title3.weight(.semibold))
                            Text(L10n.tr(Brand.tagline)).font(.subheadline).foregroundStyle(Brand.sub)
                            Text(L10n.tr("版本") + " " + version).font(.caption).foregroundStyle(Brand.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                // 模型：选用哪个、各自怎么配置，放在一起
                Section {
                    Picker(selection: $modeRaw) {
                        ForEach(ModelMode.allCases) { m in Text(m.title).tag(m.rawValue) }
                    } label: { row("cpu", .indigo, "回答使用的模型") }
                    NavigationLink { CloudPage() } label: { row("cloud", .blue, "云端大脑", value: cloudSummary) }
                    NavigationLink { LocalModelPage() } label: { row("externaldrive", .teal, "本地大模型", value: localSummary) }
                    row("apple.logo", .gray, "系统自带模型", value: L10n.tr(modelStatus))
                } header: {
                    Text("AI 模型")
                } footer: {
                    Text(L10n.tr("当前实际使用：") + ModelPref.label + "。" + L10n.tr("聊天输入框里的模型按钮也能随时切换。"))
                }

                Section("对话") {
                    Picker(selection: $style) {
                        Text("简洁").tag(0)
                        Text("详细").tag(1)
                    } label: { row("text.alignleft", .orange, "回答风格") }
                    Toggle(isOn: $saveHistory) { row("clock.arrow.circlepath", .green, "保存对话记录") }
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    Toggle(isOn: $autoSend) { row("mic", .red, "语音说完后自动发送") }
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                }

                Section {
                    Button { state.page = .tools } label: { row("wrench.and.screwdriver", Brand.mint, "工具箱：网页提取、识别、转换、去水印") }
                    Picker(selection: $transTarget) {
                        ForEach(transLangs, id: \.0) { l in Text(l.1).tag(l.0) }
                    } label: { row("character.bubble", .purple, "翻译目标语言") }
                    Button { showClock = true } label: { row("alarm", .orange, "系统时钟闹钟与自检") }
                    Toggle(isOn: $liveOn) { row("capsule.portrait", .black, "灵动岛与实时活动") }
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    Toggle(isOn: $barkOn) { row("bell.badge.fill", .orange, "Bark 提醒") }
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .onChange(of: barkOn) { _, v in if v { Task { await Sys.ensureNotif(); Bark.scheduleBG() } } }
                    NavigationLink { BarkPage() } label: {
                        row("slider.horizontal.3", .gray, "Bark 设置", value: Bark.keys.isEmpty ? L10n.tr("未填写密钥") : L10n.tr(barkOn ? "已开启" : "已配置"))
                    }
                } header: {
                    Text("工具与提醒")
                } footer: {
                    Text("灵动岛显示思考、闹钟与任务倒计时。翻译目标语言选「自动」时，外语译成系统语言，系统语言译成英文。")
                }

                Section("外观与语言") {
                    Picker(selection: $appearance) {
                        ForEach(themes, id: \.0) { t in Text(t.1).tag(t.0) }
                    } label: { row("circle.lefthalf.filled", .gray, "外观") }
                    .onChange(of: appearance) { _, v in AppTheme.apply(v) }
                    NavigationLink { LanguagePage() } label: { row("globe", .blue, "应用语言", value: L10n.currentName) }
                }

                Section("隐私与数据") {
                    Button { openSettings() } label: { row("hand.raised", .blue, "通知、照片、相机、麦克风等权限") }
                    NavigationLink { BackupPage() } label: {
                        row("externaldrive.badge.timemachine", .teal, "数据备份与恢复", value: Backup.lastTime.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                    }
                    NavigationLink { StoragePage() } label: { row("internaldrive", .gray, "存储空间与清理") }
                    if let u = exportURL {
                        ShareLink(item: u) { row("square.and.arrow.up", .green, "导出全部对话") }
                    }
                    Button(role: .destructive) { confirmChats = true } label: { row("trash", .red, "清空所有对话") }
                    Button(role: .destructive) { confirmKB = true } label: { row("books.vertical", .red, "清空知识库") }
                }

                Section("支持") {
                    NavigationLink { DiagView() } label: {
                        HStack(spacing: 12) {
                            badge("stethoscope", .pink)
                            Text("诊断与崩溃线索").foregroundStyle(Brand.ink)
                            if !Diag.lastAbnormal.isEmpty { Spacer(); Text("有记录").font(.footnote).foregroundStyle(.orange) }
                        }
                    }
                    HStack(spacing: 12) {
                        badge("message", .green)
                        Text("开发者微信").foregroundStyle(Brand.ink)
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
            .pickerStyle(.menu)
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
