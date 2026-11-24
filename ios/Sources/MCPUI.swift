import SwiftUI

// MARK: MCP 服务：连接外部工具与数据，助理需要时自动调用

struct MCPHome: View {
    var body: some View {
        NavigationStack { MCPView() }
    }
}

struct MCPView: View {
    @State private var rows: [Row] = []
    @State private var cat = "hot"
    @State private var query = ""
    @State private var picked: MCPApp?
    @State private var info = ""

    private let cols = [GridItem(.adaptive(minimum: 76), spacing: 10, alignment: .top)]

    private func added(_ a: MCPApp) -> Bool { rows.contains { $0.s("url").hasPrefix(a.url) } }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var shown: [MCPApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? MCPCatalog.apps(in: cat) : MCPCatalog.all.filter { ($0.name + " " + $0.about + " " + $0.domain).lowercased().contains(q) }
        return base.filter { !added($0) }
    }

    private func section<C: View>(_ title: String, footer: String = "", @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fontSz(13, weight: .semibold).foregroundStyle(Brand.sub).textCase(.uppercase).padding(.horizontal, 4)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !footer.isEmpty {
                Text(footer).fontSz(12.5).foregroundStyle(Brand.sub).padding(.horizontal, 4)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("MCP 让助理连接外部工具和数据：查官方文档、读代码仓库、管理你的项目。添加后，助理会在需要时自动使用；会改变外部状态的工具，每次都会先问你。")
                    .font(.subheadline)
                    .foregroundStyle(Brand.sub)
                    .padding(.horizontal, 4)

                if !info.isEmpty {
                    Label { Text(verbatim: info) } icon: { Image(systemName: "info.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.mint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !searching {
                    section("已连接") {
                        if rows.isEmpty {
                            Text("还没有连接器。从下面挑一个，点一下就能添加。").font(.subheadline).foregroundStyle(Brand.sub)
                        } else {
                            LazyVGrid(columns: cols, spacing: 16) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                                    NavigationLink { MCPDetailView(id: r.i("id")) } label: {
                                        MCPTile(domain: MCPCatalog.domain(forURL: r.s("url")), name: r.s("name"), label: MCPCatalog.short(r.s("name")), status: dot(r))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if !searching {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MCPCatalog.categories, id: \.id) { c in
                                    Button { withAnimation(.snappy(duration: 0.2)) { cat = c.id } } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: c.icon).font(.caption)
                                            Text(c.title).font(.subheadline.weight(.medium))
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(cat == c.id ? Brand.mint : Brand.card)
                                        .foregroundStyle(cat == c.id ? Brand.onMint : Brand.ink)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                    section(searching ? "搜索结果" : "热门推荐", footer: "点图标查看介绍并添加。需要登录的会打开系统登录页，授权一次即可，令牌只保存在这台手机的钥匙串里。") {
                        if shown.isEmpty {
                            Text(searching ? "没有找到。可以在下面添加自定义服务器。" : "这一类都已添加。").font(.subheadline).foregroundStyle(Brand.sub)
                        } else {
                            LazyVGrid(columns: cols, spacing: 16) {
                                ForEach(shown) { a in
                                    Button { picked = a } label: {
                                        MCPTile(domain: a.domain, name: a.name, symbol: a.symbol, label: a.shortName, corner: a.auth == .none ? "plus" : "arrow.down.circle")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                section("自己的服务器", footer: "支持 Streamable HTTP（新旧版本协议自动适配）和 OAuth 网页登录；也可以手动填访问令牌。暂不支持旧式 SSE 地址。") {
                    NavigationLink { AddMCPView(onAdded: reload) } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Brand.sub.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "plus").foregroundStyle(Brand.sub))
                            Text("添加自定义服务器").foregroundStyle(Brand.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Brand.page)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("MCP 服务")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("搜索连接器"))
        .onAppear(perform: reload)
        .sheet(item: $picked) { app in
            MCPAppSheet(app: app) { msg in
                info = msg
                reload()
            }
        }
    }

    func dot(_ r: Row) -> Color {
        if r.i("enabled") != 1 { return Brand.sub.opacity(0.5) }
        return r.s("tools").isEmpty ? Color.orange : Brand.mint
    }

    func reload() { rows = MCP.servers() }
}

// MARK: 图标方块：图标 + 名称 + 状态点 / 角标
struct MCPTile: View {
    let domain: String
    let name: String
    var symbol = ""
    let label: String
    var status: Color?
    var corner = ""

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                BrandIcon(domain: domain, name: name, symbol: symbol, size: 56)
                if let status {
                    Circle().fill(status).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Brand.card, lineWidth: 2))
                        .offset(x: 4, y: -4)
                } else if !corner.isEmpty {
                    Image(systemName: corner).font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.onMint)
                        .frame(width: 18, height: 18).background(Brand.mint).clipShape(Circle())
                        .overlay(Circle().stroke(Brand.card, lineWidth: 2))
                        .offset(x: 5, y: -5)
                }
            }
            Text(verbatim: label).fontSz(12).foregroundStyle(Brand.ink).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: 单个连接器的介绍与添加
struct MCPAppSheet: View {
    let app: MCPApp
    var done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var busy = false
    @State private var error = ""

    private var buttonTitle: String {
        if busy { return app.auth == .oauth ? "等待登录…" : "正在连接…" }
        switch app.auth {
        case .none: return "添加"
        case .oauth: return "登录并添加"
        case .key: return "连接"
        }
    }

    private var authLine: String {
        switch app.auth {
        case .none: return "无需登录，添加后即可使用。"
        case .oauth: return "需要登录：会打开系统登录页，授权一次即可。令牌只保存在这台手机的钥匙串里。"
        case .key: return "需要你的密钥，只保存在这台手机上。"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    BrandIcon(domain: app.domain, name: app.name, symbol: app.symbol, size: 84).padding(.top, 8)
                    Text(verbatim: app.name).font(.title2.weight(.semibold))
                    Text(app.about).multilineTextAlignment(.center).foregroundStyle(Brand.sub)
                    Label { Text(authLine) } icon: { Image(systemName: app.auth == .none ? "checkmark.shield" : "lock.shield").foregroundStyle(Brand.mint) }
                        .font(.footnote)
                        .foregroundStyle(Brand.sub)
                        .multilineTextAlignment(.leading)

                    if app.auth == .key {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("粘贴密钥", text: $key)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12)
                                .background(Brand.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if !app.keyHint.isEmpty { Text(app.keyHint).font(.footnote).foregroundStyle(Brand.sub) }
                            if let u = URL(string: app.keyPage) {
                                Link(destination: u) { Label("去获取密钥", systemImage: "arrow.up.right.square").font(.footnote) }
                            }
                        }
                    }

                    if !error.isEmpty {
                        Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }

                    Button { connect() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(Brand.onMint) }
                            Text(buttonTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.mint)
                    .disabled(busy || (app.auth == .key && key.trimmingCharacters(in: .whitespaces).isEmpty))

                    Text(verbatim: URL(string: app.url)?.host ?? app.url).font(.caption).foregroundStyle(Brand.sub)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Brand.page)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
    }

    func connect() {
        error = ""
        busy = true
        var url = app.url
        var token = ""
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if app.auth == .key {
            if app.keyQuery.isEmpty {
                token = k
            } else {
                url += (url.contains("?") ? "&" : "?") + app.keyQuery + "=" + (k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k)
            }
        }
        let r = MCP.add(name: app.name, url: url, token: token, headers: "", auto: app.auth == .none)
        if r.id == 0 {
            error = L10n.tr(r.error)
            busy = false
            return
        }
        Task {
            if app.auth == .oauth, let u = URL(string: app.url) {
                let e = await MCPOAuth.login(r.id, url: u)
                if !e.isEmpty {
                    busy = false
                    dismiss()
                    done(L10n.f("{} 已添加，但登录未完成：{}", app.name, L10n.tr(e)))
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
            }
            let err = await MCP.refresh(r.id)
            if !err.isEmpty && app.auth == .key {
                // 密钥填错就不保留，改好再试
                MCP.remove(r.id)
                error = L10n.tr(err)
                busy = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            busy = false
            dismiss()
            done(err.isEmpty ? L10n.f("已连接 {}", app.name) : L10n.f("{} 已添加，但连接失败：{}", app.name, L10n.tr(err)))
            UINotificationFeedbackGenerator().notificationOccurred(err.isEmpty ? .success : .warning)
        }
    }
}

// MARK: 添加自定义服务器
struct AddMCPView: View {
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var headers = ""
    @State private var auto = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        Form {
            Section {
                TextField("名称（可选）", text: $name)
                TextField("服务器地址，如 https://example.com/mcp", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("服务器")
            } footer: {
                Text("必须是 https 开头的 Streamable HTTP 地址，通常以 /mcp 结尾。")
            }
            Section {
                SecureField("访问令牌（可选）", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("其他请求头，每行一个，如 X-Api-Key: …", text: $headers, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("授权")
            } footer: {
                Text("令牌会加上 Bearer 前缀作为 Authorization 发送，并保存在系统钥匙串里。")
            }
            Section {
                Toggle("自动允许所有工具", isOn: $auto).tint(Brand.mint)
            } footer: {
                Text("关闭时，会改变外部状态的工具每次调用前都会先问你；声明为只读的工具不需要确认。")
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
                .disabled(busy || url.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
                if !error.isEmpty {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("添加服务器")
        .navigationBarTitleDisplayMode(.inline)
    }

    func connect() {
        error = ""
        busy = true
        let r = MCP.add(name: name, url: url, token: token, headers: headers, auto: auto)
        if r.id == 0 {
            error = L10n.tr(r.error)
            busy = false
            return
        }
        Task {
            let err = await MCP.refresh(r.id)
            let ok = !(MCP.row(r.id)?.s("tools") ?? "").isEmpty
            busy = false
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAdded()
                dismiss()
            } else {
                // 没连上就不保留，改好再试
                MCP.remove(r.id)
                error = L10n.tr(err.isEmpty ? "没能获取工具列表。" : err)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: 服务器详情：启用、授权、工具列表
struct MCPDetailView: View {
    let id: Int
    @Environment(\.dismiss) private var dismiss
    @State private var row: Row?
    @State private var enabled = true
    @State private var auto = false
    @State private var token = ""
    @State private var headers = ""
    @State private var tools: [MCPTool] = []
    @State private var busy = false
    @State private var info = ""
    @State private var showDelete = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BrandIcon(domain: MCPCatalog.domain(forURL: row?.s("url") ?? ""), name: row?.s("name") ?? "", size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row?.s("name") ?? "").fontSz(18, weight: .semibold)
                        Text(verbatim: URL(string: row?.s("url") ?? "")?.host ?? "").font(.footnote).foregroundStyle(Brand.sub)
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
                Toggle("启用", isOn: Binding(get: { enabled }, set: { enabled = $0; MCP.setEnabled(id, $0) })).tint(Brand.mint)
                Toggle("自动允许所有工具", isOn: Binding(get: { auto }, set: { auto = $0; MCP.setAuto(id, $0) })).tint(Brand.mint)
            } footer: {
                Text("关闭「自动允许」时，会改变外部状态的工具每次调用前都会先问你；声明为只读的工具不需要确认。")
            }

            Section("连接") {
                Text(verbatim: row?.s("url") ?? "").font(.footnote).foregroundStyle(Brand.sub).textSelection(.enabled)
                Button {
                    refresh()
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Label(busy ? "正在连接…" : "重新连接并刷新工具", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(busy)
                if !info.isEmpty {
                    Label { Text(verbatim: info) } icon: { Image(systemName: "info.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.subheadline)
                }
            }

            Section("访问授权") {
                Button {
                    login()
                } label: {
                    Label(MCPOAuth.isAuthorized(id) ? "重新登录授权" : "网页登录授权", systemImage: "person.badge.key")
                }
                .disabled(busy)
                SecureField("访问令牌", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("其他请求头，每行一个", text: $headers, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存并重新连接") {
                    MCP.updateAuth(id, token: token, headers: headers)
                    refresh()
                }
                .disabled(busy)
            }

            Section(L10n.f("工具（{}）", "\(tools.count)")) {
                if tools.isEmpty { Text("还没有获取到工具").foregroundStyle(Brand.sub) }
                ForEach(Array(tools.enumerated()), id: \.offset) { i, elem in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: elem.name).fontSz(15, weight: .semibold, design: .monospaced).foregroundStyle(Brand.ink)
                            if elem.readOnly {
                                Text("只读")
                                    .fontSz(10.5, weight: .semibold)
                                    .foregroundStyle(Brand.mint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Brand.mint.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                        if !elem.desc.isEmpty {
                            Text(verbatim: String(elem.desc.prefix(240))).fontSz(12.5).foregroundStyle(Brand.sub)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button("删除这个服务器", role: .destructive) { showDelete = true }
            }
        }
        .navigationTitle(row?.s("name") ?? "MCP")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .confirmationDialog("删除这个服务器？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                MCP.remove(id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    func load() {
        row = MCP.row(id)
        enabled = row?.i("enabled") == 1
        auto = row?.i("auto") == 1
        token = MCP.token(id)
        headers = MCP.extraHeaders(id)
        tools = row.map { MCP.cachedTools($0) } ?? []
    }

    func refresh() {
        busy = true
        info = ""
        Task {
            let err = await MCP.refresh(id)
            busy = false
            load()
            info = err.isEmpty ? L10n.f("已连接，{} 个工具可用", "\(tools.count)") : L10n.tr(err)
        }
    }

    func login() {
        guard let u = URL(string: row?.s("url") ?? "") else { return }
        busy = true
        info = ""
        Task {
            let e = await MCPOAuth.login(id, url: u)
            if e.isEmpty {
                let err = await MCP.refresh(id)
                busy = false
                load()
                info = err.isEmpty ? L10n.f("已连接，{} 个工具可用", "\(tools.count)") : L10n.tr(err)
            } else {
                busy = false
                load()
                info = L10n.tr(e)
            }
        }
    }
}
