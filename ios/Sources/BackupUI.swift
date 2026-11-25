import SwiftUI
import UniformTypeIdentifiers

// MARK: 数据备份与恢复
struct BackupPage: View {
    @AppStorage("backup.auto") private var auto = false
    @AppStorage("backup.keep") private var keep = 7
    @AppStorage("backup.secrets") private var withSecrets = false
    @State private var pass = ""
    @State private var showPass = false
    @State private var busy = false
    @State private var files: [Backup.FileInfo] = []
    @State private var made: URL?
    @State private var error = ""
    @State private var importing = false
    @State private var restoreURL: URL?
    @State private var loaded = false

    private func badge(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 29, height: 29).background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    private func sizeText(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
    private func dateText(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    var body: some View {
        Form {
            Section {
                Button {
                    make()
                } label: {
                    HStack(spacing: 12) {
                        if busy { ProgressView().frame(width: 29, height: 29) } else { badge("externaldrive.fill.badge.plus", Brand.mint) }
                        Text(busy ? "正在备份…" : "立即备份").foregroundStyle(Brand.ink)
                    }
                }
                .disabled(busy)
                if let made {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: made.lastPathComponent).font(.footnote).lineLimit(1).truncationMode(.middle)
                            Text("已保存在本机，可分享或存到「文件」").font(.caption).foregroundStyle(Brand.sub)
                        }
                        Spacer(minLength: 8)
                        ShareLink(item: made) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享")
                    }
                }
                if !error.isEmpty { Text(verbatim: error).font(.footnote).foregroundStyle(.orange) }
            } header: {
                Text("备份")
            } footer: {
                Text("备份包含对话、记忆、知识库、脚本、定时任务、连接器、邮箱账号和偏好设置，不含下载的本地模型和生成的文件。")
            }

            Section {
                HStack {
                    Group {
                        if showPass { TextField("备份口令（可选）", text: $pass) } else { SecureField("备份口令（可选）", text: $pass) }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { showPass.toggle() } label: { Image(systemName: showPass ? "eye.slash" : "eye").foregroundStyle(Brand.sub) }.accessibilityLabel(showPass ? "隐藏口令" : "显示口令")
                        .buttonStyle(.plain)
                }
                Toggle("包含密钥与密码", isOn: $withSecrets)
                    .tint(Brand.mint)
                    .disabled(pass.isEmpty)
            } header: {
                Text("加密")
            } footer: {
                Text("设置口令后，备份文件用 AES-256 加密，口令只保存在本机钥匙串里，忘记后无法找回。勾选「包含密钥与密码」会把云端模型密钥、邮箱密码、MCP 令牌一起加密带走，换手机恢复后不用重新登录。")
            }

            Section {
                Toggle("每天自动备份", isOn: $auto).tint(Brand.mint)
                if auto {
                    Stepper(value: $keep, in: 1...30) {
                        Text(L10n.f("保留最近 {} 份", "\(keep)"))
                    }
                }
                if let t = Backup.lastTime {
                    HStack {
                        Text("上次备份").foregroundStyle(Brand.sub)
                        Spacer()
                        Text(verbatim: dateText(t)).foregroundStyle(Brand.sub)
                    }
                    .font(.footnote)
                }
            } header: {
                Text("自动备份")
            } footer: {
                Text("每天第一次打开 OSVIA 时备份一次。")
            }

            Section {
                if files.isEmpty {
                    Text("还没有备份").foregroundStyle(Brand.sub)
                }
                ForEach(files) { f in
                    Button { restoreURL = f.url } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: f.name).font(.subheadline).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                                Text(verbatim: dateText(f.date) + " · " + sizeText(f.size)).font(.caption).foregroundStyle(Brand.sub)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? FileManager.default.removeItem(at: f.url)
                            files = Backup.list()
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
                Button { importing = true } label: {
                    Label("从文件恢复…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("本机备份")
            } footer: {
                Text("备份文件在「文件」App → 我的 iPhone → OSVIA → Backups 里，可以拷到 iCloud Drive 或电脑上保管。点一份备份可以恢复。")
            }
        }
        .navigationTitle("数据备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            if !loaded { pass = Backup.passphrase; loaded = true }
            files = Backup.list()
        }
        .onChange(of: pass) { _, v in
            guard loaded else { return }
            Backup.passphrase = v
            if v.isEmpty { withSecrets = false }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in
            if case .success(let urls) = r, let u = urls.first { restoreURL = u }
        }
        .sheet(item: Binding(get: { restoreURL.map { IdentURL(url: $0) } }, set: { restoreURL = $0?.url })) { item in
            RestoreSheet(url: item.url) { files = Backup.list() }
        }
    }

    func make() {
        hideKeyboard()
        busy = true
        error = ""
        let p = pass
        let s = withSecrets
        Task {
            do {
                made = try await Backup.create(kind: "备份", secrets: s, pass: p)
                files = Backup.list()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = L10n.tr("备份失败：") + error.localizedDescription
            }
            busy = false
        }
    }
}

struct IdentURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: 恢复：解密 → 预览各类内容数量 → 勾选要恢复的 → 覆盖
struct RestoreSheet: View {
    let url: URL
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pass = Backup.passphrase
    @State private var data: Data?
    @State private var snap: [String: Any]?
    @State private var info: Backup.Info?
    @State private var err = ""
    @State private var needPass = false
    @State private var opening = true
    @State private var picked: Set<String> = []
    @State private var restoreSecrets = false
    @State private var busy = false
    @State private var done = ""
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Form {
                if opening {
                    Section { HStack { ProgressView(); Text("正在读取备份…").foregroundStyle(Brand.sub) } }
                }
                if needPass {
                    Section {
                        SecureField("备份口令", text: $pass).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("解锁") { open() }.disabled(pass.isEmpty)
                    } header: {
                        Text("这份备份已加密")
                    }
                }
                if !err.isEmpty {
                    Section { Label { Text(verbatim: err) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
                }
                if let info, done.isEmpty {
                    Section {
                        HStack { Text("备份时间").foregroundStyle(Brand.sub); Spacer(); Text(verbatim: info.created.formatted(date: .abbreviated, time: .shortened)) }
                        HStack { Text("来自版本").foregroundStyle(Brand.sub); Spacer(); Text(verbatim: info.version) }
                    }
                    Section {
                        ForEach(Backup.categories) { c in
                            let n = info.counts[c.id] ?? 0
                            Toggle(isOn: Binding(get: { picked.contains(c.id) }, set: { if $0 { picked.insert(c.id) } else { picked.remove(c.id) } })) {
                                HStack(spacing: 12) {
                                    Image(systemName: c.icon).foregroundStyle(Brand.mint).frame(width: 24)
                                    Text(c.title)
                                    Spacer(minLength: 4)
                                    Text(verbatim: "\(n)").font(.footnote).foregroundStyle(Brand.sub)
                                }
                            }
                            .tint(Brand.mint)
                            .disabled(n == 0)
                        }
                        if info.secretCount > 0 {
                            Toggle(isOn: $restoreSecrets) {
                                HStack(spacing: 12) {
                                    Image(systemName: "key.fill").foregroundStyle(Brand.mint).frame(width: 24)
                                    Text("密钥与密码")
                                    Spacer(minLength: 4)
                                    Text(verbatim: "\(info.secretCount)").font(.footnote).foregroundStyle(Brand.sub)
                                }
                            }
                            .tint(Brand.mint)
                        }
                    } header: {
                        Text("选择要恢复的内容")
                    } footer: {
                        Text("勾选的类别会被备份里的内容覆盖。恢复前会先自动备份当前数据，随时可以回退。")
                    }
                    Section {
                        Button(role: .destructive) { confirm = true } label: {
                            HStack { if busy { ProgressView() }; Text(busy ? "正在恢复…" : "恢复所选内容") }
                        }
                        .disabled(busy || (picked.isEmpty && !restoreSecrets))
                    }
                }
                if !done.isEmpty {
                    Section {
                        Label { Text(verbatim: done) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint) }
                    } footer: {
                        Text("请把 OSVIA 从后台划掉再重新打开，让所有设置完全生效。恢复了邮箱账号的话，若备份里没有密码，需要在邮箱里重新输入。")
                    }
                    Section { Button("完成") { onDone(); dismiss() } }
                }
            }
            .navigationTitle("恢复备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { onDone(); dismiss() } } }
            .confirmationDialog("覆盖当前数据？", isPresented: $confirm, titleVisibility: .visible) {
                Button("恢复", role: .destructive) { run() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所选类别里现有的内容会被替换，恢复前已自动备份。")
            }
        }
        .interactiveDismissDisabled(busy)
        .task { load() }
    }

    func load() {
        opening = true
        let u = url
        Task {
            let d: Data? = await Task.detached { () -> Data? in
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: u)
            }.value
            guard let d else { err = L10n.tr("无法读取这个文件。"); opening = false; return }
            data = d
            open()
        }
    }

    func open() {
        guard let d = data else { return }
        opening = true
        err = ""
        let p = pass
        Task {
            do {
                let enc = Backup.isEncrypted(d)
                let s = try await Task.detached { try Backup.unpack(d, pass: p) }.value
                snap = s
                let i = Backup.info(s, encrypted: enc)
                info = i
                picked = Set(Backup.categories.map { $0.id }.filter { (i.counts[$0] ?? 0) > 0 })
                restoreSecrets = i.secretCount > 0
                needPass = false
            } catch {
                if Backup.needsPassphrase(error) {
                    needPass = true
                    if !p.isEmpty { err = error.localizedDescription }
                } else {
                    needPass = false
                    err = error.localizedDescription
                }
            }
            opening = false
        }
    }

    func run() {
        guard let s = snap else { return }
        busy = true
        let ids = picked
        let sec = restoreSecrets
        Task {
            _ = try? await Backup.create(kind: "恢复前", secrets: false, pass: "")
            done = await Backup.restore(s, categories: ids, secrets: sec)
            busy = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
