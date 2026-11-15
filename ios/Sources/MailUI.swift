import SwiftUI

// MARK: 邮箱：AI 分拣收件箱、读信、起草回复、账号与自动处理

struct MailGroup {
    let key: String
    let title: String
    let icon: String
    let rows: [Row]
}

extension Dictionary where Key == String, Value == Any {
    var rid: Int { i("id") }
}

struct MailHome: View {
    var body: some View {
        NavigationStack { MailView() }
    }
}

struct MailView: View {
    @State private var accounts: [Row] = []
    @State private var items: [Row] = []
    @State private var busy = false
    @State private var info = ""
    @State private var open: Set<String> = []

    private var groups: [MailGroup] {
        [MailGroup(key: "todo", title: "需要你处理", icon: "exclamationmark.circle.fill", rows: items.filter { ["urgent", "reply"].contains($0.s("cat")) }),
         MailGroup(key: "info", title: "了解即可", icon: "tray", rows: items.filter { $0.s("cat") == "info" }),
         MailGroup(key: "notice", title: "通知", icon: "bell", rows: items.filter { $0.s("cat") == "notice" }),
         MailGroup(key: "promo", title: "订阅与营销", icon: "newspaper", rows: items.filter { $0.s("cat") == "promo" })]
    }

    var body: some View {
        List {
            if accounts.isEmpty { intro } else { inbox }
        }
        .navigationTitle("邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !accounts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    if busy {
                        ProgressView()
                    } else {
                        Button { Task { await sync() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
        .refreshable { await sync() }
        .onAppear(perform: reload)
        .task {
            reload()
            if !accounts.isEmpty { await sync(maxAge: 120) }
        }
    }

    // MARK: 还没有账号
    private var intro: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Brand.mint)
                        .frame(width: 48, height: 48)
                        .background(Brand.mint.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("连接你的邮箱，助理帮你盯收件箱：")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                    VStack(alignment: .leading, spacing: 6) {
                        point("tray.full", "按紧急程度分拣，每封一句话摘要")
                        point("arrowshape.turn.up.left", "按你的意思起草回复，确认后才发送")
                        point("archivebox", "订阅和营销邮件自动归档（可选）")
                        point("bubble.left.and.text.bubble.right", "直接在对话里说：「看看有什么要紧邮件」")
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                NavigationLink {
                    AddMailView(onAdded: reload)
                } label: {
                    Label("添加邮箱", systemImage: "plus.circle.fill").foregroundStyle(Brand.mint)
                }
            } footer: {
                Text("支持 Gmail、iCloud、QQ、网易 163 / 126 / yeah、阿里、新浪、139、Yahoo、Zoho、Fastmail，以及任何支持 IMAP 的邮箱。使用「应用专用密码 / 授权码」登录，不会接触你的登录密码。")
            }
        }
    }

    private func point(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.mint).frame(width: 20)
            Text(text).font(.system(size: 14.5)).foregroundStyle(Brand.sub)
        }
    }

    // MARK: 收件箱
    private var inbox: some View {
        Group {
            let todo = groups[0].rows.count
            let unread = items.filter { $0.i("unread") == 1 && $0.s("cat") != "promo" }.count
            Section {
                HStack(spacing: 14) {
                    stat("\(todo)", "需要处理", todo > 0 ? .orange : Brand.sub)
                    stat("\(unread)", "未读", Brand.mint)
                    stat("\(items.count)", "已分拣", Brand.sub)
                }
                .padding(.vertical, 4)
                ForEach(accounts, id: \.rid) { a in
                    let st = Mail.status(a.i("id"))
                    if !st.error.isEmpty {
                        Label { Text(verbatim: a.s("email") + "：" + L10n.tr(st.error)) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.footnote)
                    } else if !st.stat.isEmpty {
                        Text(verbatim: st.stat).font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
            }

            if items.isEmpty && !busy {
                Section { Text("收件箱里还没有同步到邮件。下拉刷新试试。").foregroundStyle(Brand.sub) }
            }

            ForEach(groups, id: \.key) { g in
                if !g.rows.isEmpty {
                    if g.key == "todo" || g.key == "info" {
                        Section {
                            ForEach(g.rows.prefix(40), id: \.rid) { r in link(r) }
                        } header: {
                            Label { Text(verbatim: L10n.tr(g.title) + " · \(g.rows.count)") } icon: { Image(systemName: g.icon) }
                        }
                    } else {
                        Section {
                            DisclosureGroup(isExpanded: Binding(get: { open.contains(g.key) }, set: { if $0 { open.insert(g.key) } else { open.remove(g.key) } })) {
                                ForEach(g.rows.prefix(40), id: \.rid) { r in link(r) }
                            } label: {
                                Label { Text(verbatim: L10n.tr(g.title) + " · \(g.rows.count)") } icon: { Image(systemName: g.icon).foregroundStyle(Brand.sub) }
                                    .foregroundStyle(Brand.ink)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    MailAccountsView(onChange: reload)
                } label: {
                    Label("邮箱账号与自动处理", systemImage: "gearshape")
                }
            } footer: {
                Text("分拣和摘要会把每封邮件开头的内容发给你设置的 AI 模型；想完全留在本机，请在设置里使用本机模型。")
            }
        }
    }

    private func stat(_ n: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: n).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(Brand.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private func link(_ r: Row) -> some View {
        NavigationLink {
            MailDetailView(id: r.i("id"), onChange: reload)
        } label: {
            MailRow(r: r)
        }
    }

    func reload() {
        accounts = Mail.accounts()
        items = Mail.inbox()
    }

    func sync(maxAge: Double = 0) async {
        busy = true
        info = await Mail.refreshAll(maxAge: maxAge)
        reload()
        busy = false
    }
}

struct MailRow: View {
    let r: Row

    var body: some View {
        let unread = r.i("unread") == 1
        let who = r.s("from_name").isEmpty ? r.s("from_addr") : r.s("from_name")
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(unread ? Brand.mint : Color.clear).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: who).font(.system(size: 15.5, weight: unread ? .semibold : .regular)).foregroundStyle(Brand.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(verbatim: Mail.stamp(r.d("ts"))).font(.system(size: 12)).foregroundStyle(Brand.sub)
                }
                Text(verbatim: r.s("subject").isEmpty ? L10n.tr("（无主题）") : r.s("subject")).font(.system(size: 14.5)).foregroundStyle(Brand.ink).lineLimit(1)
                Text(verbatim: r.s("summary")).font(.system(size: 13)).foregroundStyle(Brand.sub).lineLimit(2)
                if !r.s("act").isEmpty {
                    Text(verbatim: r.s("act"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(r.s("cat") == "urgent" ? Color.orange : Brand.mint)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: 读信
struct MailDetailView: View {
    let id: Int
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var row: Row?
    @State private var mail: ParsedMail?
    @State private var loading = true
    @State private var error = ""
    @State private var busy = false
    @State private var reply = false
    @State private var showTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = row {
                    Text(verbatim: r.s("subject").isEmpty ? L10n.tr("（无主题）") : r.s("subject"))
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: r.s("from_name").isEmpty ? r.s("from_addr") : r.s("from_name")).font(.system(size: 15, weight: .medium)).foregroundStyle(Brand.ink)
                        Text(verbatim: r.s("from_addr") + " · " + Mail.stamp(r.d("ts"))).font(.system(size: 12.5)).foregroundStyle(Brand.sub)
                    }
                    if !r.s("summary").isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(verbatim: L10n.tr(Mail.catName(r.s("cat")))) } icon: { Image(systemName: "sparkles") }
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Brand.mint)
                            Text(verbatim: r.s("summary")).font(.system(size: 15)).foregroundStyle(Brand.ink)
                            if !r.s("act").isEmpty {
                                Text(verbatim: L10n.tr("建议：") + r.s("act")).font(.system(size: 13.5)).foregroundStyle(Brand.sub)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.mint.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Divider()
                if loading {
                    HStack(spacing: 8) { ProgressView(); Text("正在读取邮件…").foregroundStyle(Brand.sub) }
                } else if let m = mail {
                    if !m.attachments.isEmpty {
                        Label { Text(verbatim: m.attachments.prefix(6).joined(separator: "、")) } icon: { Image(systemName: "paperclip") }
                            .font(.system(size: 13)).foregroundStyle(Brand.sub)
                    }
                    Text(verbatim: m.text.isEmpty ? L10n.tr("（这封邮件没有可显示的文字内容）") : m.text)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Brand.ink)
                        .textSelection(.enabled)
                }
                if !error.isEmpty {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .font(.subheadline)
                }
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { reply = true } label: { Image(systemName: "arrowshape.turn.up.left") }
                    .disabled(row == nil)
                Spacer()
                Button { act("archive", leave: true) } label: { Image(systemName: "archivebox") }
                Spacer()
                Button { act(row?.i("unread") == 1 ? "read" : "unread", leave: false) } label: {
                    Image(systemName: row?.i("unread") == 1 ? "envelope.open" : "envelope.badge")
                }
                Spacer()
                Button { showTrash = true } label: { Image(systemName: "trash") }
            }
        }
        .disabled(busy)
        .task { await load() }
        .sheet(isPresented: $reply) {
            if let r = row {
                MailComposeView(row: r, original: mail?.text ?? "") {
                    onChange()
                    dismiss()
                }
            }
        }
        .confirmationDialog("删除这封邮件？", isPresented: $showTrash, titleVisibility: .visible) {
            Button("删除", role: .destructive) { act("trash", leave: true) }
            Button("取消", role: .cancel) {}
        }
    }

    func load() async {
        row = Mail.row(id)
        let r = await Mail.fullBody(id)
        mail = r.mail
        error = r.error
        loading = false
        // 打开读了，就标为已读
        if r.mail != nil, row?.i("unread") == 1 {
            _ = await Mail.act(id, "read")
            row = Mail.row(id)
            onChange()
        }
    }

    func act(_ a: String, leave: Bool) {
        busy = true
        Task {
            let e = await Mail.act(id, a)
            busy = false
            if e.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onChange()
                if leave { dismiss() } else { row = Mail.row(id) }
            } else {
                error = e
            }
        }
    }
}

// MARK: 回复：AI 起草 → 你改 → 确认发送
struct MailComposeView: View {
    let row: Row
    let original: String
    var onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var intent = ""
    @State private var drafting = false
    @State private var sending = false
    @State private var confirm = false
    @State private var error = ""

    private var recipients: [String] {
        to.components(separatedBy: CharacterSet(charactersIn: ",;，；")).map { MailMIME.address($0).addr }.filter { !$0.isEmpty }
    }

    private var unknown: String? { recipients.first { !Mail.isKnown($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("收件人") {
                    TextField("name@example.com", text: $to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
                Section("主题") { TextField("主题", text: $subject) }
                Section {
                    TextField("想怎么回？一句话，如「同意，周四下午可以」", text: $intent, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        draft()
                    } label: {
                        HStack(spacing: 8) {
                            if drafting { ProgressView() }
                            Label(drafting ? "正在起草…" : "AI 起草回复", systemImage: "sparkles")
                        }
                    }
                    .disabled(drafting)
                } footer: {
                    Text("原邮件的内容会发给你设置的 AI 模型。起草的内容请先看一遍再发。")
                }
                Section("正文") {
                    TextEditor(text: $text).frame(minHeight: 200)
                }
                if !error.isEmpty {
                    Section {
                        Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送") { check() }
                            .fontWeight(.semibold)
                            .disabled(to.isEmpty || subject.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .confirmationDialog(L10n.f("发送给 {}？", recipients.joined(separator: ", ")), isPresented: $confirm, titleVisibility: .visible) {
                Button("发送") { send() }
                Button("取消", role: .cancel) {}
            } message: {
                if let u = unknown { Text(verbatim: L10n.f("{} 之前没有和你往来过，请确认地址无误。", u)) }
            }
            .onAppear {
                if to.isEmpty {
                    to = row.s("reply_to").isEmpty ? row.s("from_addr") : row.s("reply_to")
                    subject = Mail.replySubject(row.s("subject"))
                }
            }
        }
    }

    func draft() {
        drafting = true
        error = ""
        Task {
            if let t = await Mail.draftReply(row, original: original, intent: intent) {
                text = t.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                error = L10n.tr("没能起草。请检查 AI 模型设置后再试，或直接手写。")
            }
            drafting = false
        }
    }

    func check() {
        error = ""
        guard !recipients.isEmpty, recipients.allSatisfy(Mail.validAddress) else {
            error = L10n.tr("收件人地址不正确。")
            return
        }
        confirm = true
    }

    func send() {
        guard let a = Mail.account(row.i("acct")) else { return }
        sending = true
        Task {
            let e = await Mail.send(account: a, to: recipients, subject: subject, body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                    inReplyTo: row.s("msgid"), refs: row.s("refs"))
            sending = false
            if e.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                _ = await Mail.act(row.i("id"), "read")
                dismiss()
                onSent()
            } else {
                error = e
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: 账号与自动处理
struct MailAccountsView: View {
    var onChange: () -> Void
    @State private var accounts: [Row] = []
    @State private var logs: [Row] = []
    @State private var removing: Int?
    @State private var diagnosing: Int?
    @State private var report = ""

    var body: some View {
        List {
            ForEach(accounts, id: \.rid) { a in
                let id = a.i("id")
                Section {
                    Toggle("自动处理", isOn: Binding(get: { Mail.account(id)?.i("auto") == 1 }, set: { Mail.setAuto(id, $0); reload() })).tint(Brand.mint)
                    HStack {
                        Text("上次同步").foregroundStyle(Brand.sub)
                        Spacer()
                        Text(verbatim: a.d("last_run") > 0 ? Mail.stamp(a.d("last_run")) : L10n.tr("还没有")).foregroundStyle(Brand.sub)
                    }
                    .font(.subheadline)
                    Button {
                        diagnosing = id
                        report = ""
                        Task {
                            report = await Mail.diagnose(id)
                            diagnosing = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if diagnosing == id { ProgressView() }
                            Label(diagnosing == id ? "正在诊断…" : "诊断连接", systemImage: "stethoscope")
                        }
                    }
                    .disabled(diagnosing != nil)
                    Button("移除这个邮箱", role: .destructive) { removing = id }
                } header: {
                    Text(verbatim: a.s("email"))
                }
            }

            Section {
                NavigationLink {
                    AddMailView(onAdded: { reload(); onChange() })
                } label: {
                    Label("添加邮箱", systemImage: "plus.circle")
                }
            } footer: {
                Text("开启「自动处理」后，每次打开 OSVIA（系统允许时也会在后台）会：把订阅与营销邮件标为已读并归到「OSVIA-Newsletters」文件夹；紧急和待回复的邮件发通知。不会自动回复、删除或发送任何邮件。iOS 不允许应用一直在后台运行，所以后台处理只是尽力而为。")
            }

            if !report.isEmpty {
                Section("诊断结果") {
                    Text(verbatim: report).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Button { UIPasteboard.general.string = report } label: { Label("复制", systemImage: "doc.on.doc") }
                }
            }

            if !logs.isEmpty {
                Section("自动处理记录") {
                    ForEach(logs, id: \.rid) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: l.s("text")).font(.system(size: 14)).foregroundStyle(Brand.ink)
                            Text(verbatim: Mail.stamp(l.d("ts"))).font(.system(size: 12)).foregroundStyle(Brand.sub)
                        }
                    }
                }
            }
        }
        .navigationTitle("邮箱账号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog("移除这个邮箱？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                if let id = removing { Mail.remove(id) }
                removing = nil
                reload()
                onChange()
            }
            Button("取消", role: .cancel) { removing = nil }
        } message: {
            Text("只会删除这台设备上保存的账号和缓存，邮箱里的邮件不受影响。")
        }
    }

    func reload() {
        accounts = Mail.accounts()
        logs = Mail.logs()
    }
}

// MARK: 添加邮箱
struct AddMailView: View {
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var name = ""
    @State private var pass = ""
    @State private var imap = ""
    @State private var smtp = ""
    @State private var smtpPort = "465"
    @State private var busy = false
    @State private var error = ""

    private var provider: MailProvider? { Mail.provider(for: email.trimmingCharacters(in: .whitespaces)) }
    private var hasDomain: Bool { email.contains("@") && (email.split(separator: "@").last?.contains(".") ?? false) }

    var body: some View {
        Form {
            Section {
                TextField("邮箱地址", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                TextField("显示名称（可选，写在发出的邮件上）", text: $name)
            }

            if let p = provider {
                Section {
                    Text(verbatim: L10n.tr(p.help)).font(.subheadline).foregroundStyle(Brand.sub)
                    if let u = URL(string: p.url), !p.url.isEmpty {
                        Link(destination: u) { Label(L10n.f("打开 {} 的设置页", p.name), systemImage: "arrow.up.right.square") }
                    }
                } header: {
                    Text(verbatim: p.name)
                }
            } else if hasDomain {
                Section {
                    Text("没有这个邮箱的预设，请在下面手动填写服务器（在邮箱网页的设置里能找到 IMAP / SMTP 服务器地址）。")
                        .font(.subheadline).foregroundStyle(Brand.sub)
                }
            }

            Section {
                SecureField(provider.map { L10n.tr($0.secret) } ?? L10n.tr("密码 / 授权码"), text: $pass)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("只保存在这台设备的系统钥匙串里，只用来连接你的邮箱服务器。")
            }

            if provider == nil && hasDomain {
                Section {
                    TextField("IMAP 服务器，如 imap.example.com", text: $imap)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("SMTP 服务器，如 smtp.example.com", text: $smtp)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("SMTP 端口（465 或 587）", text: $smtpPort).keyboardType(.numberPad)
                } header: {
                    Text("服务器")
                } footer: {
                    Text("IMAP 使用 993 端口（SSL）。SMTP 465 为 SSL，587 为 STARTTLS。")
                }
            }

            Section {
                Button {
                    connect()
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(busy ? "正在连接…" : "连接并保存").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.mint)
                .disabled(busy || !hasDomain || pass.isEmpty || imap.isEmpty || smtp.isEmpty)
                .listRowBackground(Color.clear)
                if !error.isEmpty {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("添加邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: email) { _, v in fill(v) }
    }

    // 识别出服务商就自动填好服务器；识别不出就按域名猜一个
    func fill(_ v: String) {
        let t = v.trimmingCharacters(in: .whitespaces)
        if let p = Mail.provider(for: t) {
            imap = p.imap
            smtp = p.smtp
            smtpPort = "\(p.smtpPort)"
        } else if t.contains("@"), let d = t.split(separator: "@").last, d.contains(".") {
            imap = "imap." + d
            smtp = "smtp." + d
            smtpPort = "465"
        } else {
            imap = ""
            smtp = ""
        }
    }

    func connect() {
        error = ""
        let em = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard Mail.validAddress(em) else {
            error = L10n.tr("邮箱地址不正确。")
            return
        }
        busy = true
        let secret = provider == nil ? pass.trimmingCharacters(in: .whitespacesAndNewlines) : pass.filter { !$0.isWhitespace }
        Task {
            let r = await Mail.add(email: em, name: Mail.cleanName(name), user: em, pass: secret,
                                   imap: imap.trimmingCharacters(in: .whitespaces), imapPort: 993,
                                   smtp: smtp.trimmingCharacters(in: .whitespaces), smtpPort: Int(smtpPort) ?? 465,
                                   provider: provider?.id ?? "custom")
            busy = false
            if r.id == 0 {
                error = L10n.tr(r.error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onAdded()
            dismiss()
            // 第一次同步放后台做，进来就能看到分拣结果
            Task { await Mail.refresh(r.id) }
        }
    }
}
