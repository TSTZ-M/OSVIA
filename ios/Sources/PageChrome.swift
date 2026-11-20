import SwiftUI

private struct PageRootKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    // 当前是否处在「侧栏打开的功能页」的根页面
    var isPageRoot: Bool {
        get { self[PageRootKey.self] }
        set { self[PageRootKey.self] = newValue }
    }
}

struct PageCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").fontSz(15, weight: .semibold).foregroundStyle(Brand.ink)
        }
        .accessibilityLabel("关闭")
    }
}

// 覆盖系统的 NavigationStack：功能页的根页面左上角放关闭按钮（放进导航栏里），
// 进入子页面后只剩系统返回键，两个按钮不会再重叠。其他位置的 NavigationStack 行为不变。
struct NavigationStack<Content: View>: View {
    @Environment(\.isPageRoot) private var isPageRoot
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        SwiftUI.NavigationStack {
            content
                .toolbar {
                    if isPageRoot {
                        ToolbarItem(placement: .topBarLeading) { PageCloseButton() }
                    }
                }
        }
        .environment(\.isPageRoot, false)
    }
}
