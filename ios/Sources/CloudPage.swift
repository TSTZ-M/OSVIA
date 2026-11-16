import SwiftUI

// 设置 → 云端大脑：每个用户填自己的免费密钥，成本由用户自己的免费额度承担，开发者零成本
struct CloudPage: View {
    @AppStorage("cloudOn") private var on = true
    @AppStorage("cloudPreset") private var preset = "zhipu"
    @AppStorage("cloudBase") private var customBase = ""
    @AppStorage("cloudModel") private var customModel = ""
    @State private var key = ""
    @State private var testing = false
    @State private var result = ""
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelsError = ""

    private var current: CloudPreset { CloudLLM.presets.first { $0.id == preset } ?? CloudLLM.presets[0] }

    var body: some View {
        Form {
            Section {
                Text("填一个免费的 AI 服务密钥后，回答、联网搜索、设闹钟都会明显更聪明、更快。请求由你的手机直接发给所选服务商，不经过任何第三方服务器；密钥只保存在本机钥匙串。不填则继续使用本机模型。")
                    .font(.footnote).foregroundStyle(Brand.sub)
            }
            Section {
                Toggle("使用云端大脑", isOn: $on).toggleStyle(SwitchToggleStyle(tint: .green))
            }
            Section("服务商") {
                Picker("服务商", selection: $preset) {
                    ForEach(CloudLLM.presets) { p in Text(p.name).tag(p.id) }
                }
                .pickerStyle(.menu)
                Text(current.note).font(.footnote).foregroundStyle(Brand.sub)
                if let u = URL(string: current.keyURL), !current.keyURL.isEmpty {
                    Link(destination: u) { Label("去获取免费密钥", systemImage: "key") }
                }
            }
            if preset == "custom" {
                Section("接口地址（到 /v1 为止，不含 /chat/completions）") {
                    TextField("https://…/v1", text: $customBase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            Section("模型名（留空用默认）") {
                TextField(current.model.isEmpty ? "例如 gpt-4o-mini" : current.model, text: $customModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button {
                    loadModels()
                } label: {
                    HStack(spacing: 8) {
                        if loadingModels { ProgressView() }
                        Label("获取可用模型列表", systemImage: "list.bullet")
                    }
                }
                .disabled(loadingModels || key.isEmpty)
                if !models.isEmpty {
                    Picker("选择模型", selection: $customModel) {
                        Text("默认").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
                if !modelsError.isEmpty { Text(verbatim: L10n.tr(modelsError)).font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text("服务商更新了模型名、或想换更强的模型时，先填好密钥，点这里读取你账号当前能用的模型。")
            }
            Section("密钥") {
                SecureField("粘贴 API Key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button { runTest() } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView() }
                        Text(testing ? "测试中…" : "测试连接").frame(maxWidth: .infinity)
                    }
                }
                .disabled(testing || key.isEmpty)
                if !result.isEmpty {
                    Text(result).font(.subheadline).foregroundStyle(result.hasPrefix("连接成功") ? Color.green : Color.red)
                }
            }
        }
        .navigationTitle("云端大脑")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { key = SecretStore.get("cloudKey") }
        .onChange(of: key) { _, v in SecretStore.set("cloudKey", v.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .onChange(of: preset) { _, _ in
            customModel = ""
            models = []
            modelsError = ""
            result = ""
        }
    }

    private func loadModels() {
        loadingModels = true
        modelsError = ""
        SecretStore.set("cloudKey", key.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            let r = await CloudLLM.listModels()
            models = r.ids
            modelsError = r.error
            loadingModels = false
        }
    }

    private func runTest() {
        testing = true
        result = ""
        SecretStore.set("cloudKey", key.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            let r = await CloudLLM.test()
            result = r
            testing = false
        }
    }
}
