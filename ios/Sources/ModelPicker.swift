import SwiftUI
import FoundationModels

// MARK: 回答用哪个模型：自动 / 云端 / 本地 / 系统自带
enum ModelMode: String, CaseIterable, Identifiable {
    case auto, cloud, local, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "自动"
        case .cloud: return "云端大脑"
        case .local: return "本地大模型"
        case .system: return "系统自带模型"
        }
    }
    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .cloud: return "cloud"
        case .local: return "cpu"
        case .system: return "apple.logo"
        }
    }
}

@MainActor
enum ModelPref {
    static let key = "modelMode"

    static var mode: ModelMode {
        get { ModelMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var systemOK: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // 云端失败或没设置时，离线可用的下一个：本地大模型 → 系统自带
    static var offline: ModelMode {
        if mode == .system { return .system }
        return LocalLLM.shared.canUse ? .local : .system
    }

    // 这一次实际会用的模型。明确选了本地却不可用时回到系统自带，绝不悄悄改走云端
    static var effective: ModelMode {
        switch mode {
        case .cloud, .auto: return CloudLLM.ready ? .cloud : (LocalLLM.shared.canUse ? .local : .system)
        case .local: return LocalLLM.shared.canUse ? .local : .system
        case .system: return .system
        }
    }

    static func short(_ s: String, _ n: Int = 16) -> String {
        let t = s.components(separatedBy: "（")[0].components(separatedBy: "/").last ?? s
        return t.count > n ? String(t.prefix(n)) : t
    }

    static var cloudName: String { short(CloudLLM.model, 22) }
    static var localName: String { short(LocalLLM.shared.selectedName, 22) }

    static var label: String {
        switch effective {
        case .cloud: return short(CloudLLM.model)
        case .local: return short(LocalLLM.shared.selectedName)
        default: return "系统模型"
        }
    }

    static var icon: String { effective.icon }
}

// 输入栏里的模型按钮：点开直接切换
struct ModelPill: View {
    @ObservedObject private var local = LocalLLM.shared
    @ObservedObject private var state = AppState.shared
    @AppStorage("modelMode") private var modeRaw = "auto"
    @AppStorage("cloudOn") private var cloudOn = true
    @AppStorage("cloudConsent") private var cloudConsent = ""   // 授权变化时刷新按钮

    private var mode: ModelMode { ModelMode(rawValue: modeRaw) ?? .auto }

    var body: some View {
        Menu {
            Section("回答使用的模型") {
                row(.auto, "自动（云端优先）", ok: true)
                row(.cloud, CloudLLM.configured ? "云端 · " + ModelPref.cloudName : "云端大脑（未设置）", ok: CloudLLM.configured)
                row(.local, local.canUse ? "本地 · " + ModelPref.localName : "本地大模型（未启用）", ok: local.canUse)
                row(.system, "系统自带模型", ok: ModelPref.systemOK)
            }
            let ready = LocalModelList.installed()
            if ready.count > 1 {
                Section("切换本地模型") {
                    ForEach(ready, id: \.id) { m in
                        Button {
                            local.select(m.id)
                            modeRaw = ModelMode.local.rawValue
                        } label: {
                            Label(m.name.components(separatedBy: "（")[0], systemImage: local.selectedID == m.id ? "checkmark" : "cpu")
                        }
                    }
                }
            }
            Button { state.page = .settings } label: { Label("模型设置…", systemImage: "slider.horizontal.3") }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: ModelPref.icon).fontSz(12, weight: .medium)
                Text(verbatim: ModelPref.label).fontSz(13, weight: .medium).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").fontSz(8, weight: .bold).foregroundStyle(Brand.sub)
            }
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .frame(maxWidth: 190)
            .background(Brand.userBubble)
            .clipShape(Capsule())
        }
        .accessibilityLabel("选择模型")
    }

    private func row(_ m: ModelMode, _ title: String, ok: Bool) -> some View {
        Button {
            modeRaw = m.rawValue
            if m == .cloud { CloudLLM.askAgain() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(title, systemImage: mode == m ? "checkmark" : m.icon)
        }
        .disabled(!ok)
    }
}

enum LocalModelList {
    @MainActor
    static func installed() -> [LocalModel] {
        LocalLLM.models.filter { LocalLLM.shared.isInstalled($0.id) }
    }
}
