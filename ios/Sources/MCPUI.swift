import SwiftUI

// MARK: MCP 服务：连接外部工具与数据，助理需要时自动调用

struct MCPHome: View {
    var body: some View {
        NavigationStack { MCPView() }
    }
}

struct MCPView: View {
    @State private var rows: [Row] = []
    @State private var adding = ""
    @State private var info = ""

    private var presets: [MCPPreset] {
        let have = Set(rows.map { $0.s("url") })
        return MCP.presets.filter { !have.contains($0.url) }
    }

    private var oauthPresets: [MCPPreset] {
        let have = Set(rows.map { $0.s("url") })
        return MCP.oauthPresets.filter { !have.contains($0.url) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Brand.mint)
                        .frame(width: 48, height: 48)
                        .background(Brand.mint.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("MCP 让助理连接外部工具和数据：查官方文档、读代码仓库、调用你自己的服务。添加后，助理会在需要时自动使用；会改变外部状态的工具，每次都会先问你。")
                        .font(.subheadline)
                        .foregroundStyle(Brand.sub)
                }
                .padding(.vertical, 4)
            }

            if !info.isEmpty {
                Section {
                    Label { Text(verbatim: info) } icon: { Image(systemName: "info.circle.fill").foregroundStyle(Brand.mint) }
                        .font(.subheadline)
                }
            }

            Section("已添加") {
                if rows.isEmpty { Text("还没有服务器。从下面挑一个，或添加自己的。").foregroundStyle(Brand.sub) }
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    NavigationLink {
                        MCPDetailView(id: r.i("id"))
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(dot(r)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: r.s("name")).font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.ink)
                                Text(verbatim: sub(r)).font(.system(size: 12.5)).foregroundStyle(Brand.sub).lineLimit(1)
                            }
                        }
                    }
                }
            }

            if !presets.isEmpty {
                Section {
                    ForEach(presets) { p in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: p.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.ink)
                                Text(p.about).font(.system(size: 12.5)).foregroundStyle(Brand.sub)
                            }
                            Spacer(minLength: 8)
                            if adding == p.name {
                                ProgressView()
                            } else {
                                Button("添加") { addPreset(p) }
                                    .buttonStyle(.bordered)
                                    .tint(Brand.mint)
                                    .disabled(!adding.isEmpty)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("推荐（无需登录）")
                } footer: {
                    Text("都是只读的文档与检索服务，添加后即可使用。")
                }
            }

            if !oauthPresets.isEmpty {
                Section {
                    ForEach(oauthPresets) { p in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: p.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Brand.ink)
                                Text(p.about).font(.system(size: 12.5)).foregroundStyle(Brand.sub)
                            }
                            Spacer(minLength: 8)
                            if adding == p.name {
                                ProgressView()
                            } else {
                                Button("登录") { addPreset(p) }
                                    .buttonStyle(.bordered)
                                    .tint(Brand.mint)
                                    .disabled(!adding.isEmpty)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("官方服务（网页登录）")
                } footer: {
                    Text("点「登录」会打开系统登录页，授权一次后自动连接，令牌只保存在这台手机的钥匙串里。")
                }
            }

            Section {
                NavigationLink {
                    AddMCPView(onAdded: reload)
                } label: {
                    Label("添加自定义服务器", systemImage: "plus.circle")
                }
            } footer: {
                Text("支持 Streamable HTTP（新旧版本协议自动适配）和 OAuth 网页登录；也可以手动填访问令牌。暂不支持旧式 SSE 地址。")
            }
        }
        .navigationTitle("MCP 服务")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    func dot(_ r: Row) -> Color {
        if r.i("enabled") != 1 { return Brand.sub.opacity(0.4) }
        return r.s("tools").isEmpty ? Color.orange : Brand.mint
    }

    func sub(_ r: Row) -> String {
        let host = URL(string: r.s("url"))?.host ?? r.s("url")
        if r.i("enabled") != 1 { return host + " · " + L10n.tr("已停用") }
        let n = MCP.cachedTools(r).count
        return host + " · " + (n > 0 ? L10n.f("{} 个工具", "\(n)") : L10n.tr("未连接"))
    }

    func addPreset(_ p: MCPPreset) {
        adding = p.name
        info = ""
        let r = MCP.add(name: p.name, url: p.url, token: "", headers: "", auto: !p.oauth)
        if r.id == 0 {
            info = L10n.tr(r.error)
            adding = ""
            return
        }
        reload()
        Task {
            if p.oauth, let u = URL(string: p.url) {
                let e = await MCPOAuth.login(r.id, url: u)
                if !e.isEmpty {
                    adding = ""
                    reload()
                    info = L10n.f("{} 已添加，但登录未完成：{}", p.name, L10n.tr(e))
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
            }
            let err = await MCP.refresh(r.id)
            adding = ""
            reload()
            info = err.isEmpty ? L10n.f("已连接 {}", p.name) : L10n.f("{} 已添加，但连接失败：{}", p.name, L10n.tr(err))
            UINotificationFeedbackGenerator().notificationOccurred(err.isEmpty ? .success : .warning)
        }
    }

    func reload() { rows = MCP.servers() }
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
                ForEach(tools.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: tools[i].name).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Brand.ink)
                            if tools[i].readOnly {
                                Text("只读")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Brand.mint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Brand.mint.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                        if !tools[i].desc.isEmpty {
                            Text(verbatim: String(tools[i].desc.prefix(240))).font(.system(size: 12.5)).foregroundStyle(Brand.sub)
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
