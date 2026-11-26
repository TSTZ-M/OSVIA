import SwiftUI

// MARK: Bark 提醒设置：开关、服务器、设备密钥、推送内容、测试
struct BarkPage: View {
    @AppStorage("bark.on") private var on = false
    @AppStorage("bark.server") private var server = ""
    @AppStorage("bark.level") private var level = "timeSensitive"
    @AppStorage("bark.sound") private var sound = ""
    @AppStorage("bark.group") private var group = ""
    @State private var keys = ""
    @State private var enc = ""
    @State private var testing = false
    @State private var result = ""
    @State private var resultOK = false
    @State private var evs: [String: Bool] = [:]
    @State private var pending: [Row] = []
    @State private var loaded = false

    private func badge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 29, height: 29).background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $on) {
                    HStack(spacing: 12) {
                        badge("bell.badge.fill", .orange)
                        Text("开启 Bark 提醒").foregroundStyle(Brand.ink)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
            } footer: {
                Text("开启后，提醒、闹钟、定时任务和重要邮件除了本机通知，还会推送到你的 Bark，其他设备、手表上也能收到。")
            }

            Section {
                TextField("服务器（留空用官方 https://api.day.app）", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("设备密钥，可直接粘贴 Bark 里复制的推送地址", text: $keys, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("加密密钥（可选，16 / 24 / 32 个字符）", text: $enc)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("连接")
            } footer: {
                Text("打开 Bark，首页示例地址里 api.day.app/ 后面那串字母就是设备密钥；多台设备的密钥用换行分开。自建服务器需要 https 地址。填了加密密钥后，推送内容会用 AES-GCM 加密再发送，请在 Bark 的加密设置里选同样的密钥和 GCM 模式。")
            }

            Section {
                Button {
                    test()
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView() }
                        Label(testing ? "正在发送…" : "发送测试推送", systemImage: "paperplane")
                    }
                }
                .disabled(testing || keys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !result.isEmpty {
                    Label { Text(verbatim: result) } icon: {
                        Image(systemName: resultOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(resultOK ? Brand.mint : .orange)
                    }
                    .font(.subheadline)
                }
            }

            Section("推送哪些内容") {
                ForEach(Bark.Event.allCases) { e in
                    Toggle(isOn: Binding(get: { evs[e.rawValue] ?? Bark.on(e) }, set: { evs[e.rawValue] = $0; Bark.setOn(e, $0) })) {
                        HStack(spacing: 12) {
                            Image(systemName: e.icon).foregroundStyle(Brand.mint).frame(width: 24)
                            Text(e.title)
                        }
                    }
                    .tint(Brand.mint)
                }
            }

            Section {
                Picker("通知级别", selection: $level) {
                    ForEach(Bark.levels, id: \.0) { l in Text(l.1).tag(l.0) }
                }
                TextField("铃声名（可选，如 minuet）", text: $sound)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("分组（默认 OSVIA）", text: $group)
            } header: {
                Text("样式")
            } footer: {
                Text("「时效性通知」能突破专注模式；「重要警告」需要在 Bark 里允许紧急通知。")
            }

            if !pending.isEmpty {
                Section {
                    ForEach(Array(pending.prefix(6).enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(verbatim: r.s("body").isEmpty ? r.s("title") : r.s("body")).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: Sys.friendly(Date(timeIntervalSince1970: r.d("due")))).font(.footnote).foregroundStyle(Brand.sub)
                        }
                    }
                } header: {
                    Text("待推送")
                } footer: {
                    Text("到点推送在 OSVIA 打开时（前台每 15 秒检查）和系统给的后台刷新机会里发出；App 被完全关闭时系统不允许联网，推送可能延迟。本机通知始终准时。")
                }
            }
        }
        .pickerStyle(.menu)
        .navigationTitle("Bark 提醒")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            if !loaded {
                keys = SecretStore.get("bark.keys")
                enc = SecretStore.get("bark.enc")
                loaded = true
            }
            pending = Bark.pending()
        }
        .onChange(of: keys) { _, v in
            guard loaded else { return }
            let p = Bark.parse(v)
            if !p.server.isEmpty {
                server = p.server == Bark.defaultServer ? "" : p.server
                keys = p.key
                return
            }
            SecretStore.set("bark.keys", v)
        }
        .onChange(of: enc) { _, v in if loaded { SecretStore.set("bark.enc", v.trimmingCharacters(in: .whitespaces)) } }
        .onChange(of: on) { _, v in
            if v { Task { await Sys.ensureNotif(); Bark.scheduleBG() } }
        }
    }

    func test() {
        hideKeyboard()
        testing = true
        result = ""
        Task {
            let e = await Bark.send(nil, title: "OSVIA", body: L10n.tr("这是一条测试推送，收到说明 Bark 已连通。"), force: true)
            resultOK = e.isEmpty
            result = e.isEmpty ? L10n.tr("已发送，请到 Bark 查看。") : L10n.tr(e)
            testing = false
            UINotificationFeedbackGenerator().notificationOccurred(e.isEmpty ? .success : .warning)
        }
    }
}
