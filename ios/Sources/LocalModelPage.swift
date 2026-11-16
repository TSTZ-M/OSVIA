import SwiftUI

// 设置 → 本地大模型：下载、切换、删除
struct LocalModelPage: View {
    @ObservedObject private var m = LocalLLM.shared
    @AppStorage("localOn") private var on = true
    @AppStorage("localModelID") private var selected = LocalLLM.defaultID

    var body: some View {
        List {
            Section {
                Text("Apple 自带的模型很弱。这里可以把更强的开源大模型下载到手机，之后完全离线、免费运行。首次下载需要联网，下载时请保持 App 在前台并连接 Wi‑Fi。")
                    .font(.footnote).foregroundStyle(Brand.sub)
            }
            Section {
                Toggle("使用本地大模型回答", isOn: $on).toggleStyle(SwitchToggleStyle(tint: .green))
                statusRow
            }
            Section("选择模型") {
                ForEach(LocalLLM.models) { mod in row(mod) }
            }
            Section("下载线路") {
                Text("自动使用国内镜像 hf-mirror.com；失败时改用 huggingface.co。")
                    .font(.footnote).foregroundStyle(Brand.sub)
            }
        }
        .navigationTitle("本地大模型")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { m.refresh() }
    }

    @ViewBuilder
    var statusRow: some View {
        switch m.state {
        case .idle:
            if !m.blockReason.isEmpty {
                Text(L10n.tr(m.blockReason)).font(.footnote).foregroundStyle(.orange)
            } else {
                Text(m.canUse ? "已就绪" : "未下载本地模型").font(.subheadline).foregroundStyle(Brand.sub)
            }
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 6) {
                Text("正在下载 {}%".replacingOccurrences(of: "{}", with: "\(Int(f * 100))")).font(.subheadline)
                ProgressView(value: f)
            }
        case .loading:
            HStack(spacing: 8) { ProgressView(); Text("正在载入…").font(.subheadline) }
        case .ready:
            Text("已就绪").font(.subheadline).foregroundStyle(Brand.sub)
        case .failed(let e):
            Text(L10n.f("下载失败：{}", String(e.prefix(120)))).font(.footnote).foregroundStyle(.red)
        }
    }

    func row(_ mod: LocalModel) -> some View {
        let installed = m.installed.contains(mod.id)
        let downloading: Bool = { if case .downloading = m.state { return true }; return false }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mod.name).font(.headline)
                    Text(mod.note).font(.footnote).foregroundStyle(Brand.sub)
                    Text(L10n.f("大小约 {} GB", mod.gb)).font(.footnote).foregroundStyle(Brand.sub)
                }
                Spacer()
                if installed && selected == mod.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ink) }
            }
            HStack(spacing: 10) {
                if installed {
                    if selected != mod.id {
                        Button("使用这个模型") { m.select(mod.id); selected = mod.id }.buttonStyle(.bordered)
                    }
                    Button("删除模型", role: .destructive) { m.delete(mod.id) }.buttonStyle(.bordered)
                } else if downloading && selected == mod.id {
                    Button("取消下载") { m.cancelDownload() }.buttonStyle(.bordered)
                } else {
                    Button("下载") { selected = mod.id; m.download(mod.id) }
                        .buttonStyle(.borderedProminent)
                        .disabled(downloading)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
