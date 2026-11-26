import SwiftUI

// MARK: OSVIA 账号（设置 → 隐私与数据）
struct AccountPage: View {
    @State private var signedIn = Account.signedIn

    var body: some View {
        Group {
            if signedIn {
                AccountHome { signedIn = false }
            } else {
                AccountSignIn { signedIn = true }
            }
        }
        .navigationTitle("OSVIA 账号")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func accountBadge(_ icon: String, _ color: Color) -> some View {
    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 29, height: 29).background(color)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
}

// MARK: 登录 / 注册
private struct AccountSignIn: View {
    var onDone: () -> Void
    @State private var register = false
    @State private var email = Account.email
    @State private var pass = ""
    @State private var pass2 = ""
    @State private var code = ""
    @State private var needCode = false
    @State private var busy = false
    @State private var error = ""
    @State private var server = Account.customBase

    private var valid: Bool {
        let e = Account.normEmail(email)
        guard e.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$", options: .regularExpression) != nil else { return false }
        return pass.count >= (register ? 8 : 1) && (!register || pass == pass2)
    }

    var body: some View {
        Form {
            if needCode {
                Section {
                    TextField("验证码", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button { run { try await Account.verify(email: email, code: code); onDone() } } label: {
                        HStack { if busy { ProgressView() }; Text("验证") }
                    }
                    .disabled(busy || code.count < 6)
                    if !error.isEmpty { Text(verbatim: error).font(.footnote).foregroundStyle(.orange) }
                } header: {
                    Text("验证邮箱")
                } footer: {
                    Text("我们给你的邮箱发了 6 位验证码，10 分钟内有效。")
                }
            } else {
                Section {
                    Picker("", selection: $register) {
                        Text("登录").tag(false)
                        Text("注册").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $pass)
                        .textContentType(register ? .newPassword : .password)
                    if register {
                        SecureField("确认密码", text: $pass2).textContentType(.newPassword)
                    }
                    Button {
                        run {
                            let step = register
                                ? try await Account.register(email: email, password: pass)
                                : try await Account.login(email: email, password: pass)
                            if step == .signedIn { onDone() } else { needCode = true }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() }
                            Text(register ? "注册" : "登录").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(busy || !valid)
                    if !error.isEmpty { Text(verbatim: error).font(.footnote).foregroundStyle(.orange) }
                } footer: {
                    Text("支持 Gmail、Outlook、iCloud、QQ、网易等任意邮箱。密码只在本机参与计算，服务器只保存校验值。登录后，提醒、笔记和云备份在网页版同样可用。")
                }
                Section {
                    if let u = Account.legalURL("privacy") { Link("隐私政策", destination: u) }
                    if let u = Account.legalURL("terms") { Link("服务条款", destination: u) }
                }
                Section {
                    DisclosureGroup("服务器") {
                        TextField(Account.defaultBase, text: $server)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: server) { _, v in Account.setBase(v) }
                        Text("自己部署了 OSVIA 网页版时才需要修改。").font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        error = ""
        busy = true
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: 已登录
private struct AccountHome: View {
    var onOut: () -> Void
    @State private var verified = true
    @State private var usage = Account.Usage()
    @State private var files: [Account.CloudFile] = []
    @State private var relay = Account.relayOn
    @State private var busy = false
    @State private var loading = true
    @State private var error = ""
    @State private var restoreURL: URL?
    @State private var confirmOut = false
    @State private var askDelete = false
    @State private var delPass = ""
    @State private var pendingDelete: Account.CloudFile?

    private func sizeText(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    accountBadge("person.crop.circle.fill", .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: Account.email).lineLimit(1)
                        Text(verified ? "已验证" : "未验证").font(.caption).foregroundStyle(Brand.sub)
                    }
                }
                if !loading {
                    Text(L10n.f("云端提醒 {} · 笔记 {} · 云备份 {}", "\(usage.reminders)", "\(usage.notes)", sizeText(usage.bytes)))
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
                if let u = URL(string: Account.base) {
                    Link(destination: u) {
                        HStack(spacing: 12) {
                            accountBadge("safari", Brand.mint)
                            Text("打开网页版").foregroundStyle(Brand.ink)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Brand.sub)
                        }
                    }
                }
            } header: {
                Text("账号")
            }

            Section {
                Toggle(isOn: Binding(get: { relay }, set: { toggleRelay($0) })) {
                    HStack(spacing: 12) {
                        accountBadge("bell.and.waves.left.and.right.fill", .orange)
                        Text("云端提醒中转")
                    }
                }
                .tint(Brand.mint)
                .disabled(busy)
                if !Bark.ready {
                    Text("需要先开启 Bark 提醒并填写设备密钥。").font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("提醒")
            } footer: {
                Text("开启后，排队中的 Bark 提醒会交给云端，到点由服务器推送。即使 App 被系统结束或手机没网，只要 Bark 能收到就会准时提醒。Bark 密钥会加密保存在服务器上。")
            }

            Section {
                Button { upload() } label: {
                    HStack(spacing: 12) {
                        if busy { ProgressView().frame(width: 29, height: 29) } else { accountBadge("icloud.and.arrow.up.fill", .blue) }
                        Text(busy ? "正在处理…" : "立即备份到云端").foregroundStyle(Brand.ink)
                    }
                }
                .disabled(busy)
                ForEach(files) { f in
                    Button { fetch(f) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: f.name).font(.footnote).lineLimit(1).truncationMode(.middle).foregroundStyle(Brand.ink)
                            Text(verbatim: f.created.formatted(date: .abbreviated, time: .shortened) + " · " + sizeText(f.size)
                                 + (f.device.isEmpty ? "" : " · " + f.device))
                                .font(.caption).foregroundStyle(Brand.sub)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = f } label: { Label("删除", systemImage: "trash") }
                    }
                }
                if !error.isEmpty { Text(verbatim: error).font(.footnote).foregroundStyle(.orange) }
            } header: {
                Text("云备份")
            } footer: {
                Text("只上传加密备份，口令由你保管，服务器无法读取内容。点一份即可下载并恢复，最多保留最近 10 份。")
            }

            Section {
                Button { confirmOut = true } label: {
                    HStack(spacing: 12) {
                        accountBadge("rectangle.portrait.and.arrow.right", .gray)
                        Text("退出登录").foregroundStyle(Brand.ink)
                    }
                }
                Button(role: .destructive) { delPass = ""; askDelete = true } label: {
                    HStack(spacing: 12) {
                        accountBadge("trash", .red)
                        Text("删除账号")
                    }
                }
            } footer: {
                Text("删除账号会清除云端的提醒、笔记和云备份，且无法恢复。本机数据不受影响。")
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: Binding(get: { restoreURL.map { IdentURL(url: $0) } }, set: { restoreURL = $0?.url })) { item in
            RestoreSheet(url: item.url) { }
        }
        .confirmationDialog("退出登录？", isPresented: $confirmOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await Account.logout(); onOut() }
            }
        }
        .confirmationDialog("删除这份云备份？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let f = pendingDelete { Task { try? await Account.deleteBackup(f); await reload() } }
                pendingDelete = nil
            }
        }
        .alert("删除账号", isPresented: $askDelete) {
            SecureField("输入密码确认", text: $delPass)
            Button("确定删除", role: .destructive) { deleteAccount() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("云端的提醒、笔记和云备份会被永久删除。")
        }
    }

    private func reload() async {
        if let m = try? await Account.me() { verified = m.verified; usage = m.usage }
        if let l = try? await Account.listBackups() { files = l }
        loading = false
        if !Account.signedIn { onOut() }
    }

    private func toggleRelay(_ on: Bool) {
        error = ""
        busy = true
        Task {
            do { try await Account.setRelay(on) } catch { self.error = error.localizedDescription }
            relay = Account.relayOn
            busy = false
        }
    }

    private func upload() {
        error = ""
        busy = true
        Task {
            do { try await Account.uploadBackup(); await reload() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func fetch(_ f: Account.CloudFile) {
        error = ""
        busy = true
        Task {
            do { restoreURL = try await Account.download(f) } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func deleteAccount() {
        let p = delPass
        delPass = ""
        error = ""
        busy = true
        Task {
            do { try await Account.deleteAccount(password: p); onOut() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
