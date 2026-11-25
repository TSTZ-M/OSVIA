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
    @State private var query = ""
    @State private var filter = 0          // 0 全部 1 未读 2 需处理 3 星标
    @State private var trashID: Int?
    @State private var actionError = ""
    @State private var notice = ""
    @State private var acct = 0            // 0 所有邮箱，否则只看这个邮箱
    @State private var vips: Set<String> = []
    @State private var selecting = false
    @State private var sel = Set<Int>()
    @State private var batchTrash = false
    @State private var showCompose = false
    @State private var showSenders = false
    @State private var snoozeRow: Row?

    private func todo(_ r: Row) -> Bool { ["urgent", "reply"].contains(r.s("cat")) }

    // 选了某个邮箱就只看它
    private var scoped: [Row] { acct == 0 ? items : items.filter { $0.i("acct") == acct } }
    private var unreadCount: Int { scoped.filter { $0.i("unread") == 1 && $0.s("cat") != "promo" }.count }
    private var todoCount: Int { scoped.filter(todo).count }
    private var starCount: Int { scoped.filter { $0.i("flagged") == 1 }.count }
    private var vipCount: Int { scoped.filter { vips.contains($0.s("from_addr").lowercased()) }.count }

    private let palette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .brown, .green]
    private func tint(_ id: Int) -> Color {
        let i = accounts.firstIndex { $0.i("id") == id } ?? 0
        return palette[i % palette.count]
    }

    private func label(_ a: Row) -> String {
        let e = a.s("email")
        return e.isEmpty ? a.s("name") : e
    }

    private func unread(in id: Int) -> Int {
        items.filter { $0.i("acct") == id && $0.i("unread") == 1 && $0.s("cat") != "promo" }.count
    }

    // 先按筛选，再按搜索词
    private var shown: [Row] {
        scoped.filter { r in
            switch filter {
            case 1: return r.i("unread") == 1
            case 2: return todo(r)
            case 3: return r.i("flagged") == 1
            case 4: return vips.contains(r.s("from_addr").lowercased())
            default: return true
            }
        }
        .filter { r in
            let q = query.trimmingCharacters(in: .whitespaces)
            if q.isEmpty { return true }
            return [r.s("from_name"), r.s("from_addr"), r.s("subject"), r.s("summary"), r.s("snippet")].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var flat: Bool { filter != 0 || !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var groups: [MailGroup] {
        let s = shown
        return [MailGroup(key: "todo", title: "需要你处理", icon: "exclamationmark.circle.fill", rows: s.filter(todo)),
                MailGroup(key: "info", title: "了解即可", icon: "tray", rows: s.filter { $0.s("cat") == "info" }),
                MailGroup(key: "notice", title: "通知", icon: "bell", rows: s.filter { $0.s("cat") == "notice" }),
                MailGroup(key: "promo", title: "订阅与营销", icon: "newspaper", rows: s.filter { $0.s("cat") == "promo" })]
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                List { intro }
            } else {
                List { inbox }
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("搜索发件人、主题、内容"))
            }
        }
        .navigationTitle("邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !accounts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    if selecting {
                        Button("完成") { selecting = false; sel = [] }
                    } else if busy {
                        ProgressView()
                    } else {
                        Button { Task { await sync() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新")
                    }
                }
                if !selecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showCompose = true } label: { Label("写邮件", systemImage: "square.and.pencil") }
                            Button { selecting = true; sel = [] } label: { Label("选择邮件", systemImage: "checkmark.circle") }
                            Button { markAllRead() } label: { Label("全部标为已读", systemImage: "envelope.open") }
                                .disabled(!shown.contains { $0.i("unread") == 1 })
                            Button { showSenders = true } label: { Label("重要联系人与屏蔽", systemImage: "person.crop.circle.badge.checkmark") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }.accessibilityLabel("更多")
                    }
                }
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(sel.count == shown.count && !shown.isEmpty ? "取消全选" : "全选") {
                            sel = sel.count == shown.count ? [] : Set(shown.map { $0.rid })
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { batch("read") } label: { Image(systemName: "envelope.open") }.accessibilityLabel("标为已读").disabled(sel.isEmpty)
                        Spacer()
                        Button { batch("archive") } label: { Image(systemName: "archivebox") }.accessibilityLabel("归档").disabled(sel.isEmpty)
                        Spacer()
                        Text(verbatim: L10n.f("已选 {} 封", "\(sel.count)")).font(.footnote).foregroundStyle(Brand.sub)
                        Spacer()
                        Button { batch("star") } label: { Image(systemName: "star") }.accessibilityLabel("加星标").disabled(sel.isEmpty)
                        Spacer()
                        Button { batchTrash = true } label: { Image(systemName: "trash") }.accessibilityLabel("删除").disabled(sel.isEmpty)
                    }
                }
            }
        }
        .refreshable { await sync() }
        .sheet(isPresented: $showCompose) {
            MailComposeView(row: Row(), original: "", mode: .new) { reload() }
        }
        .navigationDestination(isPresented: $showSenders) { MailSendersView() }
        .confirmationDialog("什么时候提醒你？", isPresented: Binding(get: { snoozeRow != nil }, set: { if !$0 { snoozeRow = nil } }), titleVisibility: .visible) {
            ForEach(Array(Mail.snoozeOptions().enumerated()), id: \.offset) { _, o in
                Button(o.title) {
                    if let r = snoozeRow {
                        Mail.remind(r, at: o.date)
                        Task { await Tasks.refresh() }
                        notice = L10n.f("好的，{} 提醒你。", o.title)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    snoozeRow = nil
                }
            }
            Button("取消", role: .cancel) { snoozeRow = nil }
        }
        .confirmationDialog("删除选中的邮件？", isPresented: $batchTrash, titleVisibility: .visible) {
            Button("删除", role: .destructive) { batch("trash") }
            Button("取消", role: .cancel) {}
        }
        .onAppear(perform: reload)
        .task {
            reload()
            if !accounts.isEmpty { await sync(maxAge: 120) }
        }
        .confirmationDialog("删除这封邮件？", isPresented: Binding(get: { trashID != nil }, set: { if !$0 { trashID = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let id = trashID { quick(id, "trash") }
                trashID = nil
            }
            Button("取消", role: .cancel) { trashID = nil }
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
                Text("内置 30 多种邮箱：Gmail、iCloud、QQ、网易、阿里、新浪、搜狐、189、Yahoo、AOL、GMX、Yandex、Zoho、Fastmail 等；企业邮箱和自己域名的邮箱会自动识别服务器，其他任何支持 IMAP 的邮箱也可以，可以同时连接多个。使用「应用专用密码 / 授权码」登录，不会接触你的登录密码。")
            }
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).fontSz(14).foregroundStyle(Brand.mint).frame(width: 20)
            Text(text).fontSz(14.5).foregroundStyle(Brand.sub)
        }
    }

    // MARK: 收件箱
    private var inbox: some View {
        Group {
            Section {
                ForEach(accounts, id: \.rid) { a in
                    let st = Mail.status(a.i("id"))
                    if !st.error.isEmpty {
                        Label { Text(verbatim: a.s("email") + "：" + L10n.tr(st.error)) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.footnote)
                    }
                    let w = Mail.warn(a.i("id"))
                    if !w.isEmpty {
                        Label { Text(verbatim: a.s("email") + "：" + L10n.tr(w)) } icon: { Image(systemName: "paperplane.circle.fill").foregroundStyle(.orange) }
                            .font(.footnote)
                    }
                }
                if !actionError.isEmpty {
                    Label { Text(verbatim: actionError) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .font(.footnote)
                }
                if !notice.isEmpty {
                    Label { Text(verbatim: notice) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.footnote)
                }
                if accounts.count > 1 {
                    accountChips
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                }
                chips
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listRowSeparator(.hidden)

            if shown.isEmpty && !busy {
                Section {
                    Text(items.isEmpty ? "收件箱里还没有同步到邮件。下拉刷新试试。" : "没有符合条件的邮件。").foregroundStyle(Brand.sub)
                }
            }

            if flat {
                if !shown.isEmpty {
                    Section {
                        ForEach(shown.prefix(80), id: \.rid) { r in link(r) }
                    } header: {
                        Text(verbatim: L10n.f("{} 封", "\(shown.count)"))
                    }
                }
            } else {
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
            }

            Section {
                ForEach(accounts, id: \.rid) { a in
                    let st = Mail.status(a.i("id"))
                    if !st.stat.isEmpty && st.error.isEmpty {
                        Text(verbatim: a.s("email") + " · " + st.stat).font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
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

    // MARK: 筛选
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(0, "全部", scoped.count)
                chip(1, "未读", unreadCount)
                chip(2, "需处理", todoCount)
                chip(3, "星标", starCount)
                if !vips.isEmpty { chip(4, "重要", vipCount) }
            }
        }
    }

    // 多个邮箱时：按邮箱筛选（每个邮箱一个颜色，列表里的邮件也带同色小圆点）
    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                accountChip(0, L10n.tr("所有邮箱"), items.filter { $0.i("unread") == 1 && $0.s("cat") != "promo" }.count, Brand.mint)
                ForEach(accounts, id: \.rid) { a in
                    accountChip(a.i("id"), label(a), unread(in: a.i("id")), tint(a.i("id")))
                }
            }
        }
    }

    private func accountChip(_ id: Int, _ title: String, _ n: Int, _ color: Color) -> some View {
        let on = acct == id
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { acct = id; sel = [] }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(verbatim: title).fontSz(13, weight: .medium).lineLimit(1).frame(maxWidth: 170)
                if n > 0 { Text(verbatim: "\(n)").fontSz(11.5, weight: .semibold, design: .rounded).opacity(0.7) }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Brand.ink)
            .background(on ? color.opacity(0.18) : Brand.card, in: Capsule())
            .overlay(Capsule().stroke(on ? color.opacity(0.6) : Brand.line.opacity(0.6), lineWidth: on ? 1 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ tag: Int, _ title: String, _ n: Int) -> some View {
        let on = filter == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = tag }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Text(title).fontSz(14, weight: .medium)
                if n > 0 { Text(verbatim: "\(n)").fontSz(12, weight: .semibold, design: .rounded).opacity(0.75) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Brand.onMint : (tag == 2 && n > 0 ? Color.orange : Brand.ink))
            .background(on ? Brand.mint : Brand.card, in: Capsule())
            .overlay(Capsule().stroke(Brand.line.opacity(on ? 0 : 0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func tag(_ r: Row) -> (name: String, color: Color)? {
        guard accounts.count > 1 else { return nil }
        let a = r.i("acct")
        let dom = accounts.first { $0.i("id") == a }?.s("email").split(separator: "@").last.map(String.init) ?? ""
        let first = dom.split(separator: ".").first.map(String.init) ?? dom
        return (first, tint(a))
    }

    @ViewBuilder
    private func link(_ r: Row) -> some View {
        let id = r.i("id")
        let unread = r.i("unread") == 1
        let starred = r.i("flagged") == 1
        let vip = vips.contains(r.s("from_addr").lowercased())
        if selecting {
            Button {
                if sel.contains(id) { sel.remove(id) } else { sel.insert(id) }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: sel.contains(id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(sel.contains(id) ? Brand.mint : Brand.sub)
                    MailRow(r: r, tag: tag(r), vip: vip)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                MailDetailView(id: id, onChange: reload)
            } label: {
                MailRow(r: r, tag: tag(r), vip: vip)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { quick(id, unread ? "read" : "unread") } label: {
                    Label { Text(verbatim: L10n.tr(unread ? "标为已读" : "标为未读")) } icon: { Image(systemName: unread ? "envelope.open" : "envelope.badge") }
                }
                .tint(Brand.mint)
                Button { quick(id, starred ? "unstar" : "star") } label: {
                    Label { Text(verbatim: L10n.tr(starred ? "取消星标" : "星标")) } icon: { Image(systemName: starred ? "star.slash" : "star") }
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { trashID = id } label: { Label("删除", systemImage: "trash") }
                    .tint(.red)
                Button { quick(id, "archive") } label: { Label("归档", systemImage: "archivebox") }
                    .tint(.indigo)
                Button { snoozeRow = r } label: { Label("稍后", systemImage: "clock") }
                    .tint(.teal)
            }
        }
    }

    // 批量整理：每个邮箱只连一次服务器
    private func batch(_ action: String) {
        let ids = Array(sel)
        guard !ids.isEmpty else { return }
        actionError = ""
        notice = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selecting = false
        sel = []
        busy = true
        Task {
            let e = await Mail.actBatch(ids, action)
            if !e.isEmpty { actionError = L10n.tr(e) }
            busy = false
            reload()
        }
    }

    private func markAllRead() {
        sel = Set(shown.filter { $0.i("unread") == 1 }.map { $0.rid })
        batch("read")
    }

    // 滑动操作：先改本地显示，再在后台同步到服务器；失败了提示并刷新回真实状态
    private func quick(_ id: Int, _ action: String) {
        actionError = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let e = await Mail.act(id, action)
            if !e.isEmpty { actionError = L10n.tr(e) }
            reload()
        }
    }

    func reload() {
        accounts = Mail.accounts()
        items = Mail.inbox()
        vips = Set(Mail.vips)
        if acct != 0, !accounts.contains(where: { $0.i("id") == acct }) { acct = 0 }
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
    var tag: (name: String, color: Color)?
    var vip = false

    var body: some View {
        let unread = r.i("unread") == 1
        let name = r.s("from_name")
        let addr = r.s("from_addr")
        let cat = r.s("cat")
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(name: name, addr: addr, size: 44, unread: unread)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(verbatim: name.isEmpty ? addr : name)
                        .fontSz(15.5, weight: unread ? .semibold : .regular)
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                    if vip {
                        Image(systemName: "person.crop.circle.badge.checkmark").fontSz(11).foregroundStyle(Brand.mint)
                    }
                    if r.i("flagged") == 1 {
                        Image(systemName: "star.fill").fontSz(11).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 6)
                    if let t = tag {
                        HStack(spacing: 3) {
                            Circle().fill(t.color).frame(width: 6, height: 6)
                            Text(verbatim: t.name).fontSz(11).foregroundStyle(Brand.sub).lineLimit(1)
                        }
                    }
                    Text(verbatim: Mail.shortStamp(r.d("ts")))
                        .fontSz(12.5)
                        .foregroundStyle(unread ? Brand.mint : Brand.sub)
                }
                Text(verbatim: r.s("subject").isEmpty ? L10n.tr("（无主题）") : r.s("subject"))
                    .fontSz(14.5, weight: unread ? .medium : .regular)
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                Text(verbatim: r.s("summary"))
                    .fontSz(13)
                    .foregroundStyle(Brand.sub)
                    .lineLimit(2)
                if cat == "urgent" || cat == "reply" || !r.s("act").isEmpty {
                    HStack(spacing: 6) {
                        if cat == "urgent" || cat == "reply" {
                            Text(verbatim: L10n.tr(Mail.catName(cat)))
                                .fontSz(11, weight: .semibold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(cat == "urgent" ? Color.orange : Brand.mint)
                                .background((cat == "urgent" ? Color.orange : Brand.mint).opacity(0.14), in: Capsule())
                        }
                        if !r.s("act").isEmpty {
                            Text(verbatim: r.s("act"))
                                .fontSz(11.5, weight: .medium)
                                .foregroundStyle(Brand.sub)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 3)
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
    @State private var notice = ""
    @State private var busy = false
    @State private var compose: MailComposeMode?
    @State private var showSnooze = false
    @State private var showBlock = false
    @State private var showTrash = false
    @State private var showUnsub = false
    @State private var showJunk = false

    private var unsub: Mail.UnsubTarget? { mail.flatMap { Mail.unsubTarget($0) } }
    private var isVIP: Bool { Mail.isVIP(row?.s("from_addr") ?? "") }

    private func toggleVIP() {
        Mail.setVIP(row?.s("from_addr") ?? "", !isVIP)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        row = Mail.row(id)
        onChange()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let r = row { header(r) }
                if let r = row, !r.s("summary").isEmpty { summary(r) }
                Divider()
                if loading {
                    HStack(spacing: 8) { ProgressView(); Text("正在读取邮件…").foregroundStyle(Brand.sub) }
                } else if let m = mail {
                    if !m.attachments.isEmpty { attachments(m.attachments) }
                    Text(verbatim: m.text.isEmpty ? L10n.tr("（这封邮件没有可显示的文字内容）") : m.text)
                        .fontSz(15.5)
                        .lineSpacing(3)
                        .foregroundStyle(Brand.ink)
                        .textSelection(.enabled)
                }
                if let u = unsub, !loading {
                    Button { showUnsub = true } label: {
                        Label { Text(verbatim: L10n.f("退订 {}", Mail.unsubName(row))) } icon: { Image(systemName: "bell.slash") }
                            .fontSz(14, weight: .medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.sub)
                    .accessibilityHint(Text(verbatim: u.https?.host ?? u.mail ?? ""))
                }
                if !notice.isEmpty {
                    Label { Text(verbatim: notice) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.subheadline)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { act(row?.i("flagged") == 1 ? "unstar" : "star", leave: false) } label: {
                        Label { Text(verbatim: L10n.tr(row?.i("flagged") == 1 ? "取消星标" : "星标")) } icon: { Image(systemName: row?.i("flagged") == 1 ? "star.slash" : "star") }
                    }
                    Button { showSnooze = true } label: { Label("稍后提醒我…", systemImage: "clock.badge") }
                    Button { toggleVIP() } label: {
                        Label { Text(verbatim: L10n.tr(isVIP ? "移出重要联系人" : "设为重要联系人")) } icon: { Image(systemName: isVIP ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.checkmark") }
                    }
                    Button { UIPasteboard.general.string = row?.s("from_addr") ?? "" } label: { Label("复制发件人地址", systemImage: "doc.on.doc") }
                    if unsub != nil { Button { showUnsub = true } label: { Label("退订", systemImage: "bell.slash") } }
                    Button(role: .destructive) { showBlock = true } label: { Label("屏蔽此发件人", systemImage: "nosign") }
                    Button(role: .destructive) { showJunk = true } label: { Label("标为垃圾邮件", systemImage: "xmark.bin") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }.accessibilityLabel("更多")
                .disabled(row == nil)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button { compose = .reply } label: { Label("回复", systemImage: "arrowshape.turn.up.left") }
                    Button { compose = .replyAll } label: { Label("回复全部", systemImage: "arrowshape.turn.up.left.2") }
                    Button { compose = .forward } label: { Label("转发", systemImage: "arrowshape.turn.right") }
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                } primaryAction: {
                    compose = .reply
                }
                .accessibilityLabel("回复")
                .disabled(row == nil)
                Spacer()
                Button { act("archive", leave: true) } label: { Image(systemName: "archivebox") }.accessibilityLabel("归档")
                Spacer()
                Button { act(row?.i("unread") == 1 ? "read" : "unread", leave: false) } label: {
                    Image(systemName: row?.i("unread") == 1 ? "envelope.open" : "envelope.badge")
                }.accessibilityLabel(row?.i("unread") == 1 ? "标为已读" : "标为未读")
                Spacer()
                Button { showTrash = true } label: { Image(systemName: "trash") }.accessibilityLabel("删除")
            }
        }
        .disabled(busy)
        .task { await load() }
        .sheet(item: $compose) { m in
            if let r = row {
                MailComposeView(row: r, original: mail?.text ?? "", mode: m) {
                    onChange()
                    dismiss()
                }
            }
        }
        .confirmationDialog("什么时候提醒你？", isPresented: $showSnooze, titleVisibility: .visible) {
            ForEach(Array(Mail.snoozeOptions().enumerated()), id: \.offset) { _, o in
                Button(o.title) {
                    if let r = row {
                        Mail.remind(r, at: o.date)
                        Task { await Tasks.refresh() }
                        notice = L10n.f("好的，{} 提醒你。", o.title)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("屏蔽这个发件人？", isPresented: $showBlock, titleVisibility: .visible) {
            Button("屏蔽", role: .destructive) {
                Mail.setBlocked(row?.s("from_addr") ?? "", true)
                onChange()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以后他的来信不会再显示在收件箱里（邮件仍留在邮箱服务器上）。可以随时在「重要联系人与屏蔽」里解除。")
        }
        .confirmationDialog("删除这封邮件？", isPresented: $showTrash, titleVisibility: .visible) {
            Button("删除", role: .destructive) { act("trash", leave: true) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("移到垃圾邮件？", isPresented: $showJunk, titleVisibility: .visible) {
            Button("移到垃圾邮件", role: .destructive) { act("junk", leave: true) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("退订这个发件人？", isPresented: $showUnsub, titleVisibility: .visible) {
            Button("退订") { unsubscribe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(verbatim: L10n.tr("会按邮件里的退订方式向发件人提出退订：") + (unsub?.https?.host ?? unsub?.mail ?? ""))
        }
    }

    // MARK: 头部：头像、发件人、时间
    private func header(_ r: Row) -> some View {
        let name = r.s("from_name")
        let addr = r.s("from_addr")
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: r.s("subject").isEmpty ? L10n.tr("（无主题）") : r.s("subject"))
                .fontSz(22, weight: .semibold)
                .foregroundStyle(Brand.ink)
            HStack(spacing: 12) {
                SenderAvatar(name: name, addr: addr, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: name.isEmpty ? addr : name)
                            .fontSz(16, weight: .semibold)
                            .foregroundStyle(Brand.ink)
                            .lineLimit(1)
                        if r.i("flagged") == 1 { Image(systemName: "star.fill").fontSz(12).foregroundStyle(.orange) }
                    }
                    Text(verbatim: addr)
                        .fontSz(12.5)
                        .foregroundStyle(Brand.sub)
                        .lineLimit(1)
                    Text(verbatim: Mail.stamp(r.d("ts")))
                        .fontSz(12.5)
                        .foregroundStyle(Brand.sub)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func summary(_ r: Row) -> some View {
        let cat = r.s("cat")
        let tint: Color = cat == "urgent" ? .orange : Brand.mint
        return VStack(alignment: .leading, spacing: 6) {
            Label { Text(verbatim: L10n.tr(Mail.catName(cat))) } icon: { Image(systemName: "sparkles") }
                .fontSz(12.5, weight: .semibold)
                .foregroundStyle(tint)
            Text(verbatim: r.s("summary")).fontSz(15).foregroundStyle(Brand.ink)
            if !r.s("act").isEmpty {
                Text(verbatim: L10n.tr("建议：") + r.s("act")).fontSz(13.5).foregroundStyle(Brand.sub)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func attachments(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(names.prefix(6).enumerated()), id: \.offset) { _, n in
                HStack(spacing: 8) {
                    Image(systemName: Self.fileIcon(n)).foregroundStyle(Brand.mint).frame(width: 20)
                    Text(verbatim: n).fontSz(13.5).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if names.count > 6 {
                Text(verbatim: L10n.f("还有 {} 个附件", "\(names.count - 6)")).fontSz(12.5).foregroundStyle(Brand.sub)
            }
        }
    }

    private static func fileIcon(_ n: String) -> String {
        switch (n as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "doc", "docx", "pages", "txt", "rtf": return "doc.text"
        case "xls", "xlsx", "csv", "numbers": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "zip", "rar", "7z", "gz": return "doc.zipper"
        case "ics": return "calendar"
        default: return "paperclip"
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
        error = ""
        Task {
            let e = await Mail.act(id, a)
            busy = false
            if e.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onChange()
                if leave { dismiss() } else { row = Mail.row(id) }
            } else {
                error = L10n.tr(e)
            }
        }
    }

    func unsubscribe() {
        busy = true
        error = ""
        notice = ""
        Task {
            let r = await Mail.unsubscribe(id, parsed: mail)
            busy = false
            if let u = r.open {
                notice = L10n.tr("请在打开的网页上确认退订。")
                _ = await UIApplication.shared.open(u)
            } else if r.ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                notice = L10n.tr(r.msg)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                error = L10n.tr(r.msg)
            }
        }
    }
}

// MARK: 写邮件 / 回复 / 回复全部 / 转发：AI 起草 → 你改 → 确认发送
enum MailComposeMode: String, Identifiable {
    case new, reply, replyAll, forward
    var id: String { rawValue }
}

struct MailComposeView: View {
    let row: Row
    let original: String
    var mode: MailComposeMode = .reply
    var onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [Row] = []
    @State private var acctID = 0
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var showCC = false
    @State private var subject = ""
    @State private var text = ""
    @State private var intent = ""
    @State private var quote = true
    @State private var drafting = false
    @State private var sending = false
    @State private var confirm = false
    @State private var error = ""
    @State private var ready = false

    private var isReply: Bool { mode == .reply || mode == .replyAll }

    private func parse(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",;，；")).map { MailMIME.address($0).addr }.filter { !$0.isEmpty }
    }

    private var recipients: [String] { parse(to) }
    private var ccList: [String] { parse(cc) }
    private var bccList: [String] { parse(bcc) }
    private var unknown: String? { (recipients + ccList).first { !Mail.isKnown($0) } }
    private var fromAccount: Row? { Mail.account(isReply ? row.i("acct") : acctID) }
    private var signature: String { Mail.signature(fromAccount?.i("id") ?? 0).trimmingCharacters(in: .whitespacesAndNewlines) }

    private var title: String {
        switch mode {
        case .new: return L10n.tr("写邮件")
        case .reply: return L10n.tr("回复")
        case .replyAll: return L10n.tr("回复全部")
        case .forward: return L10n.tr("转发")
        }
    }

    private var quoted: String {
        guard mode != .new else { return "" }
        let who = row.s("from_name").isEmpty ? row.s("from_addr") : row.s("from_name") + " <" + row.s("from_addr") + ">"
        let date = Mail.stamp(row.d("ts"))
        let body = String(original.prefix(mode == .forward ? 20_000 : 4_000))
        if mode == .forward {
            return "---------- " + L10n.tr("转发的邮件") + " ----------\n" + L10n.tr("发件人：") + who + "\n" + L10n.tr("日期：") + date + "\n"
                + L10n.tr("主题：") + row.s("subject") + "\n\n" + body
        }
        let lines = body.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        return L10n.f("{}，{} 写道：", date, who) + "\n" + lines
    }

    private var finalBody: String {
        var b = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !signature.isEmpty { b += (b.isEmpty ? "" : "\n\n") + "-- \n" + signature }
        if mode != .new, quote, !original.isEmpty { b += (b.isEmpty ? "" : "\n\n") + quoted }
        return b
    }

    private var canSend: Bool {
        !to.isEmpty && !subject.isEmpty && (mode == .forward || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !isReply && accounts.count > 1 {
                        Picker("发件邮箱", selection: $acctID) {
                            ForEach(accounts, id: \.rid) { a in Text(verbatim: a.s("email")).tag(a.i("id")) }
                        }
                    } else {
                        HStack {
                            Text("发件人").foregroundStyle(Brand.sub)
                            Spacer()
                            Text(verbatim: fromAccount?.s("email") ?? "").foregroundStyle(Brand.sub)
                        }
                        .font(.subheadline)
                    }
                    TextField("收件人，多个用逗号分隔", text: $to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    if showCC {
                        TextField("抄送", text: $cc)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                        TextField("密送", text: $bcc)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    } else {
                        Button { withAnimation { showCC = true } } label: { Label("添加抄送 / 密送", systemImage: "person.badge.plus").font(.subheadline) }
                    }
                    TextField("主题", text: $subject)
                }
                Section {
                    TextField(mode == .new || mode == .forward ? "想写什么？一句话，如「约张老师周四下午开会」" : "想怎么回？一句话，如「同意，周四下午可以」", text: $intent, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        draft()
                    } label: {
                        HStack(spacing: 8) {
                            if drafting { ProgressView() }
                            Label(drafting ? "正在起草…" : "AI 起草", systemImage: "sparkles")
                        }
                    }
                    .disabled(drafting || (!isReply && intent.trimmingCharacters(in: .whitespaces).isEmpty))
                } footer: {
                    Text("你写的描述和原邮件的内容会发给你设置的 AI 模型。起草的内容请先看一遍再发。")
                }
                Section("正文") {
                    TextEditor(text: $text).frame(minHeight: 200)
                    if mode != .new && !original.isEmpty {
                        Toggle(mode == .forward ? "附上原邮件" : "引用原邮件", isOn: $quote).tint(Brand.mint)
                    }
                    if !signature.isEmpty {
                        Text(verbatim: "-- \n" + signature).font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
                if mode == .forward {
                    Section {
                        Text("转发只包含原邮件的文字内容，不带附件。").font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
                if !error.isEmpty {
                    Section {
                        Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送") { check() }
                            .fontWeight(.semibold)
                            .disabled(!canSend)
                    }
                }
            }
            .confirmationDialog(L10n.f("发送给 {}？", recipients.joined(separator: ", ")), isPresented: $confirm, titleVisibility: .visible) {
                Button("发送") { send() }
                Button("取消", role: .cancel) {}
            } message: {
                if let u = unknown { Text(verbatim: L10n.f("{} 之前没有和你往来过，请确认地址无误。", u)) }
            }
            .onAppear(perform: setup)
        }
    }

    func setup() {
        guard !ready else { return }
        ready = true
        accounts = Mail.accounts()
        acctID = row.i("acct") != 0 ? row.i("acct") : (accounts.first?.i("id") ?? 0)
        switch mode {
        case .reply:
            to = row.s("reply_to").isEmpty ? row.s("from_addr") : row.s("reply_to")
            subject = Mail.replySubject(row.s("subject"))
        case .replyAll:
            let t = Mail.replyAllTargets(row)
            to = t.to
            cc = t.cc.joined(separator: ", ")
            showCC = !t.cc.isEmpty
            subject = Mail.replySubject(row.s("subject"))
        case .forward:
            subject = Mail.forwardSubject(row.s("subject"))
        case .new:
            break
        }
    }

    func draft() {
        drafting = true
        error = ""
        Task {
            let t = isReply
                ? await Mail.draftReply(row, original: original, intent: intent)
                : await Mail.draftNew(intent: intent, subject: subject)
            if let t {
                text = t.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                error = L10n.tr("没能起草。请检查 AI 模型设置后再试，或直接手写。")
            }
            drafting = false
        }
    }

    func check() {
        error = ""
        guard !recipients.isEmpty, (recipients + ccList + bccList).allSatisfy(Mail.validAddress) else {
            error = L10n.tr("收件人地址不正确。")
            return
        }
        guard fromAccount != nil else {
            error = L10n.tr("没有可用的发件邮箱。")
            return
        }
        confirm = true
    }

    func send() {
        guard let a = fromAccount else { return }
        sending = true
        let body = finalBody
        Task {
            let e = await Mail.send(account: a, to: recipients, cc: ccList, bcc: bccList, subject: subject, body: body,
                                    inReplyTo: isReply ? row.s("msgid") : "", refs: isReply ? row.s("refs") : "")
            sending = false
            if e.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if isReply { _ = await Mail.act(row.i("id"), "read") }
                dismiss()
                onSent()
            } else {
                error = e
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: 重要联系人与屏蔽名单
struct MailSendersView: View {
    @State private var vips: [String] = []
    @State private var blocked: [String] = []
    @State private var vipInput = ""
    @State private var blockInput = ""

    var body: some View {
        List {
            Section {
                ForEach(vips, id: \.self) { a in
                    Label { Text(verbatim: a) } icon: { Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Brand.mint) }
                }
                .onDelete { idx in
                    for i in idx { Mail.setVIP(vips[i], false) }
                    reload()
                }
                addRow("添加邮箱地址", $vipInput) { Mail.setVIP($0, true) }
            } header: {
                Text("重要联系人")
            } footer: {
                Text("他们的来信一律放进「需要你处理」，并出现在「重要」筛选里。也可以在读信页右上角菜单里直接设置。")
            }
            Section {
                ForEach(blocked, id: \.self) { a in
                    Label { Text(verbatim: a) } icon: { Image(systemName: "nosign").foregroundStyle(.red) }
                }
                .onDelete { idx in
                    for i in idx { Mail.setBlocked(blocked[i], false) }
                    reload()
                }
                addRow("添加邮箱地址", $blockInput) { Mail.setBlocked($0, true) }
            } header: {
                Text("屏蔽名单")
            } footer: {
                Text("屏蔽后，对方的来信不会再出现在收件箱里（邮件仍留在邮箱服务器上）。左滑可以解除。")
            }
        }
        .navigationTitle("重要联系人与屏蔽")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func addRow(_ prompt: String, _ text: Binding<String>, _ add: @escaping (String) -> Void) -> some View {
        HStack {
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
            Button("添加") {
                let t = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                guard Mail.validAddress(t) else { return }
                add(t)
                text.wrappedValue = ""
                reload()
            }
            .disabled(!Mail.validAddress(text.wrappedValue.trimmingCharacters(in: .whitespaces)))
        }
    }

    func reload() {
        vips = Mail.vips
        blocked = Mail.blockedList
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
    @AppStorage(SenderLogos.enabledKey) private var logos = true
    @State private var cleared = false

    var body: some View {
        List {
            ForEach(accounts, id: \.rid) { a in
                let id = a.i("id")
                Section {
                    Toggle("自动处理", isOn: Binding(get: { Mail.account(id)?.i("auto") == 1 }, set: { Mail.setAuto(id, $0); reload() })).tint(Brand.mint)
                    Toggle("暂停同步", isOn: Binding(get: { Mail.paused(id) }, set: { Mail.setPaused(id, $0); reload(); onChange() })).tint(Brand.mint)
                    MailAccountFields(id: id)
                    NavigationLink {
                        EditMailView(id: id, onDone: { reload(); onChange() })
                    } label: {
                        Label("修改密码与服务器", systemImage: "key")
                    }
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

            Section {
                Toggle("显示发件人图标", isOn: $logos).tint(Brand.mint)
                Button {
                    SenderLogos.shared.clear()
                    cleared = true
                } label: {
                    Label { Text(verbatim: L10n.tr(cleared ? "已清除" : "清除图标缓存")) } icon: { Image(systemName: "trash") }
                }
                .disabled(cleared)
            } footer: {
                Text("开启后，企业和品牌发件人会显示官网图标（只联网获取域名对应的图标，不会发送邮件内容）；个人邮箱和取不到图标时显示首字母头像。")
            }

            if !report.isEmpty {
                Section("诊断结果") {
                    Text(verbatim: report).fontSz(12, design: .monospaced).textSelection(.enabled)
                    Button { UIPasteboard.general.string = report } label: { Label("复制", systemImage: "doc.on.doc") }
                }
            }

            if !logs.isEmpty {
                Section("自动处理记录") {
                    ForEach(logs, id: \.rid) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: l.s("text")).fontSz(14).foregroundStyle(Brand.ink)
                            Text(verbatim: Mail.stamp(l.d("ts"))).fontSz(12).foregroundStyle(Brand.sub)
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

// MARK: 账号的显示名称与签名（输入即保存）
struct MailAccountFields: View {
    let id: Int
    @State private var name = ""
    @State private var sig = ""
    @State private var loaded = false

    var body: some View {
        Group {
            TextField("显示名称（写在发出的邮件上）", text: $name)
            TextField("签名（附在发出的邮件末尾）", text: $sig, axis: .vertical).lineLimit(1...4)
        }
        .onAppear {
            if !loaded {
                name = Mail.account(id)?.s("name") ?? ""
                sig = Mail.signature(id)
                loaded = true
            }
        }
        .onChange(of: name) { _, v in
            if loaded { DB.shared.run("UPDATE mail_account SET name=? WHERE id=?", [Mail.cleanName(v), id]) }
        }
        .onChange(of: sig) { _, v in
            if loaded { Mail.setSignature(id, v) }
        }
    }
}

// MARK: 修改已有邮箱的密码和服务器（先登录试一次，通了才保存）
struct EditMailView: View {
    let id: Int
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var pass = ""
    @State private var imap = ""
    @State private var smtp = ""
    @State private var smtpPort = "465"
    @State private var busy = false
    @State private var stepText = ""
    @State private var error = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Text(verbatim: email).foregroundStyle(Brand.sub)
            }
            Section {
                SecureField("新的密码 / 授权码（不改请留空）", text: $pass)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("授权码过期或在网页上重新生成后，在这里更新。只保存在这台设备的系统钥匙串里。")
            }
            Section {
                TextField("IMAP 服务器", text: $imap)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("SMTP 服务器", text: $smtp)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("SMTP 端口（465 或 587）", text: $smtpPort).keyboardType(.numberPad)
            } header: {
                Text("服务器")
            }
            Section {
                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text(verbatim: busy ? L10n.tr(stepText.isEmpty ? "正在连接…" : stepText) : L10n.tr("测试并保存")).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.mint)
                .disabled(busy || imap.isEmpty || smtp.isEmpty)
                .listRowBackground(Color.clear)
                if !error.isEmpty {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("修改密码与服务器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let a = Mail.account(id) else { return }
            loaded = true
            email = a.s("email")
            imap = a.s("imap_host")
            smtp = a.s("smtp_host")
            smtpPort = "\(a.i("smtp_port") == 0 ? 465 : a.i("smtp_port"))"
        }
    }

    func save() {
        guard let a = Mail.account(id) else { return }
        error = ""
        busy = true
        stepText = ""
        let secret = pass.isEmpty ? Mail.password(id) : pass.filter { !$0.isWhitespace }
        Task {
            let r = await Mail.add(email: a.s("email"), name: a.s("name"), user: a.s("user"), pass: secret,
                                   imap: imap.trimmingCharacters(in: .whitespaces), imapPort: max(a.i("imap_port"), 993),
                                   smtp: smtp.trimmingCharacters(in: .whitespaces), smtpPort: Int(smtpPort) ?? 465,
                                   provider: a.s("provider"), step: { stepText = $0 })
            busy = false
            if r.id == 0 {
                error = L10n.tr(r.error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
            dismiss()
            Task { await Mail.refresh(r.id) }
        }
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
    @State private var stepText = ""
    @State private var error = ""
    @State private var detecting = false
    @State private var detected: MailServers?
    @State private var manual = false
    @State private var detectTask: Task<Void, Never>?

    private var trimmed: String { email.trimmingCharacters(in: .whitespaces).lowercased() }
    private var domain: String { trimmed.split(separator: "@").last.map(String.init) ?? "" }
    private var hasDomain: Bool { trimmed.contains("@") && domain.contains(".") && !domain.hasSuffix(".") }
    private var preset: MailProvider? { Mail.provider(for: trimmed) }
    private var provider: MailProvider? { preset ?? detected.flatMap { Mail.providerByID($0.providerID) } }
    // 识别失败、或用户要自己改时才显示服务器输入框
    private var showServers: Bool { hasDomain && (manual || (preset == nil && detected == nil && !detecting)) }

    var body: some View {
        Form {
            Section {
                TextField("邮箱地址", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                TextField("显示名称（可选，写在发出的邮件上）", text: $name)
            }

            if hasDomain { statusSection }

            Section {
                SecureField(provider.map { L10n.tr($0.secret) } ?? L10n.tr("密码 / 授权码"), text: $pass)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("只保存在这台设备的系统钥匙串里，只用来连接你的邮箱服务器。")
            }

            if showServers {
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
                        Text(verbatim: busy ? L10n.tr(stepText.isEmpty ? "正在连接…" : stepText) : L10n.tr("连接并保存")).frame(maxWidth: .infinity)
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

    // MARK: 识别结果与授权码说明
    private var statusSection: some View {
        Section {
            if let p = provider {
                Text(verbatim: L10n.tr(p.help)).font(.subheadline).foregroundStyle(Brand.sub)
                if let u = URL(string: p.url), !p.url.isEmpty {
                    Link(destination: u) { Label(L10n.f("打开 {} 的设置页", p.name), systemImage: "arrow.up.right.square") }
                }
            }
            if detecting {
                HStack(spacing: 8) { ProgressView(); Text("正在识别邮箱服务器…").font(.subheadline).foregroundStyle(Brand.sub) }
            } else if let d = detected {
                Label { Text(verbatim: L10n.f("已识别（{}）：{}", L10n.tr(d.source), d.imap)) } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.mint) }
                    .font(.subheadline)
            } else if preset == nil {
                Text("没能自动识别这个邮箱的服务器。请在下面填写（在邮箱网页的设置里能找到 IMAP / SMTP 服务器地址）。")
                    .font(.subheadline).foregroundStyle(Brand.sub)
            }
            if preset != nil || detected != nil {
                Button { withAnimation { manual.toggle() } } label: {
                    Label { Text(verbatim: L10n.tr(manual ? "收起服务器设置" : "修改服务器设置")) } icon: { Image(systemName: "slider.horizontal.3") }
                        .font(.subheadline)
                }
            }
        } header: {
            if let p = provider { Text(verbatim: p.name) }
        }
    }

    // 内置预设直接填；没有预设的先按域名猜一个，同时联网识别（域名自带配置 → Mozilla 配置库 → MX 托管方）
    func fill(_ v: String) {
        detectTask?.cancel()
        detected = nil
        detecting = false
        manual = false
        error = ""
        let t = v.trimmingCharacters(in: .whitespaces).lowercased()
        if let p = Mail.provider(for: t) {
            imap = p.imap
            smtp = p.smtp
            smtpPort = "\(p.smtpPort)"
            return
        }
        guard t.contains("@"), let d = t.split(separator: "@").last.map(String.init), d.contains("."), !d.hasSuffix(".") else {
            imap = ""
            smtp = ""
            return
        }
        imap = "imap." + d
        smtp = "smtp." + d
        smtpPort = "465"
        detecting = true
        detectTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            let r = await MailAutoconfig.detect(d)
            if Task.isCancelled { return }
            detecting = false
            if let r {
                detected = r
                imap = r.imap
                smtp = r.smtp
                smtpPort = "\(r.smtpPort)"
            }
        }
    }

    func connect() {
        error = ""
        let em = trimmed
        guard Mail.validAddress(em) else {
            error = L10n.tr("邮箱地址不正确。")
            return
        }
        busy = true
        stepText = ""
        let secret = provider == nil ? pass.trimmingCharacters(in: .whitespacesAndNewlines) : pass.filter { !$0.isWhitespace }
        Task {
            let r = await Mail.add(email: em, name: Mail.cleanName(name), user: em, pass: secret,
                                   imap: imap.trimmingCharacters(in: .whitespaces), imapPort: detected?.imapPort ?? 993,
                                   smtp: smtp.trimmingCharacters(in: .whitespaces), smtpPort: Int(smtpPort) ?? 465,
                                   provider: provider?.id ?? "custom", step: { stepText = $0 })
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
