import SwiftUI
import Translation

// MARK: 让所有写在代码里的中文界面文字自动按当前语言显示
// 原理：给常用控件增加「参数是 String」的初始化方法，编译器对字面量优先选它，再在里面查表翻译。
extension Text {
    init(_ s: String) { self.init(verbatim: L10n.tr(s)) }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, systemImage name: String) {
        self.init { Text(verbatim: L10n.tr(title)) } icon: { Image(systemName: name) }
    }
}

extension Button where Label == Text {
    init(_ title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(verbatim: L10n.tr(title)) }
    }

    init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(verbatim: L10n.tr(title)) }
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(verbatim: L10n.tr(title)) })
    }
}

extension Picker where Label == Text {
    init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content, label: { Text(verbatim: L10n.tr(title)) })
    }
}

extension Toggle where Label == Text {
    init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(verbatim: L10n.tr(title)) }
    }
}

extension TextField where Label == Text {
    init(_ title: String, text: Binding<String>) {
        self.init(text: text, label: { Text(verbatim: L10n.tr(title)) })
    }

    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.init(text: text, axis: axis, label: { Text(verbatim: L10n.tr(title)) })
    }
}

extension SecureField where Label == Text {
    init(_ title: String, text: Binding<String>) {
        self.init(text: text, label: { Text(verbatim: L10n.tr(title)) })
    }
}

extension NavigationLink where Label == Text, Destination: View {
    init(_ title: String, @ViewBuilder destination: () -> Destination) {
        self.init(destination: destination, label: { Text(verbatim: L10n.tr(title)) })
    }
}

extension View {
    func accessibilityLabel(_ label: String) -> some View {
        accessibilityLabel(Text(verbatim: L10n.tr(label)))
    }

    func navigationTitle(_ title: String) -> some View {
        navigationTitle(Text(verbatim: L10n.tr(title)))
    }

    func alert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        alert(Text(verbatim: L10n.tr(title)), isPresented: isPresented, actions: actions)
    }

    func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(verbatim: L10n.tr(title)), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions)
    }

    // 「.buttonStyle(.borderedProminent)」在深色模式下底色是近白、文字也是白色，看不清。
    // 这里统一换成对比度正确的按钮样式（浅色模式黑底白字，深色模式白底黑字）。
    func buttonStyle(_ style: BorderedProminentButtonStyle) -> some View {
        buttonStyle(PrimaryButtonStyle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontSz(size == .large ? 17 : 15, weight: .semibold)
            .foregroundStyle(Brand.onAccent)
            .padding(.vertical, size == .large ? 15 : 11)
            .padding(.horizontal, 18)
            .background(Brand.accent.opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: 语言切换与系统翻译
@MainActor
final class L10nState: ObservableObject {
    static let shared = L10nState()
    @Published var version = 0
    @Published var config: TranslationSession.Configuration?
    @Published var status = ""
    @Published var busy = false
    private var target = ""

    func select(_ setting: String) {
        UserDefaults.standard.set(setting, forKey: "appLang")
        L10n.reload()
        version += 1
        ensureTranslation()
    }

    // 简体中文和 English 内置；其他语言缺译文时让系统翻译在本机生成
    func ensureTranslation() {
        let c = L10n.code
        guard c != "zh-Hans" else {
            status = ""
            busy = false
            return
        }
        guard !L10n.missingKeys(c).isEmpty else {
            status = ""
            busy = false
            return
        }
        target = c
        busy = true
        status = tr("正在准备语言包…")
        let apple = c == "en" ? "en-US" : (L10n.langs.first { $0.code == c }?.apple ?? c)
        let next = TranslationSession.Configuration(source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: apple))
        if config == next { config?.invalidate() } else { config = next }
    }

    func run(_ session: TranslationSession) async {
        let c = target
        let keys = L10n.missingKeys(c)
        guard !keys.isEmpty else { busy = false; return }
        do {
            try await session.prepareTranslation()
            var result = L10n.cacheCopy(c)
            var done = 0
            var i = 0
            while i < keys.count {
                let chunk = Array(keys[i..<min(i + 40, keys.count)])
                var masks: [Int] = []
                var reqs: [TranslationSession.Request] = []
                for (n, k) in chunk.enumerated() {
                    let m = L10n.mask(k)
                    masks.append(m.1)
                    reqs.append(TranslationSession.Request(sourceText: m.0, clientIdentifier: String(n)))
                }
                let rs = try await session.translations(from: reqs)
                for r in rs {
                    guard let id = r.clientIdentifier, let n = Int(id), n < chunk.count else { continue }
                    if let t = L10n.unmask(r.targetText, masks[n]), !t.isEmpty { result[chunk[n]] = t }
                }
                done += chunk.count
                i += 40
                status = L10n.f("正在翻译界面：{}", "\(min(done, keys.count))/\(keys.count)")
                if (i / 40) % 6 == 0 { L10n.saveCache(c, result) }   // 中途退出也不丢已翻译的部分
            }
            L10n.saveCache(c, result)
            version += 1
            status = ""
        } catch {
            status = L10n.f("语言包准备失败：{}", String("\(error.localizedDescription)".prefix(80))) + "\n" + tr("该语言暂时使用英文界面")
        }
        busy = false
    }
}

struct LanguagePage: View {
    @ObservedObject private var st = L10nState.shared
    @AppStorage("appLang") private var setting = "system"

    var body: some View {
        List {
            Section {
                Text("切换后整个应用的界面、通知、灵动岛、分享页和助理回答都会使用所选语言。简体中文和 English 已内置，其他语言由系统翻译在本机完成，首次选择时需要下载语言包。")
                    .font(.footnote).foregroundStyle(Brand.sub)
            }
            Section {
                row("system", L10n.currentNameForSystem, "")
                ForEach(L10n.langs) { l in
                    row(l.code, l.native, L10n.modelSupports(l.code) ? "" : tr("本机模型暂不支持该语言，助理回答会改用英语"))
                }
            }
            if !st.status.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        if st.busy { ProgressView() }
                        Text(st.status).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("应用语言")
        .navigationBarTitleDisplayMode(.inline)
    }

    func row(_ code: String, _ title: String, _ note: String) -> some View {
        Button { st.select(code) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Brand.ink)
                    if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(Brand.sub) }
                }
                Spacer()
                if setting == code { Image(systemName: "checkmark").foregroundStyle(Brand.ink) }
            }
        }
    }
}

extension L10n {
    static var currentNameForSystem: String {
        tr("跟随系统") + " · " + (langs.first { $0.code == systemCode() }?.native ?? "English")
    }
}
