import SwiftUI
import UserNotifications
import UIKit

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// 主题：只用 UIKit 的深浅色覆盖，写到每个窗口，并逐层写到所有已弹出的页面（设置、分享、相册……）。
// 不再使用 SwiftUI 的 preferredColorScheme：它会给已弹出的页面留下旧的深浅色，导致「主界面变了、设置页没变」。
enum AppTheme {
    static func style(_ v: Int) -> UIUserInterfaceStyle { v == 1 ? .light : (v == 2 ? .dark : .unspecified) }

    static func apply(_ v: Int) {
        let st = style(v)
        for case let s as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in s.windows {
                w.overrideUserInterfaceStyle = st
                paint(w.rootViewController, st)
            }
        }
    }

    private static func paint(_ vc: UIViewController?, _ st: UIUserInterfaceStyle) {
        guard let vc else { return }
        vc.overrideUserInterfaceStyle = st
        for c in vc.children { paint(c, st) }
        paint(vc.presentedViewController, st)
    }
}

@main
struct OSVIAApp: App {
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = 0

    init() {
        L10n.bootstrap()
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        // 主题只保留「跟随系统 / 浅色 / 深色」，升级后默认恢复为跟随系统
        let ud = UserDefaults.standard
        if !ud.bool(forKey: "themeReset05") {
            ud.set(0, forKey: "appearance")
            ud.set(true, forKey: "themeReset05")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Brand.accent)
                .onAppear { AppTheme.apply(appearance) }
                .onChange(of: appearance) { _, v in AppTheme.apply(v) }
                .onOpenURL { URLRouter.handle($0) }
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                AppTheme.apply(appearance)
                Task { await Tasks.refresh(); await Evolve.run() }
            }
        }
    }
}

// 其他应用调用：osvia://ask?q=问题   osvia://run?name=技能名&input=内容&x-success=回调地址
// 内部回调：osvia://clock（系统时钟闹钟）  osvia://connector（连接器结果）
enum URLRouter {
    @MainActor static func handle(_ url: URL) {
        guard url.scheme == "osvia" else { return }
        var q: [String: String] = [:]
        for i in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[i.name] = i.value ?? "" }
        AppState.shared.drawer = false
        AppState.shared.page = nil
        switch url.host {
        case "ask":
            Agent.shared.start(q["q"] ?? "")
        case "run":
            let out = Skills.run(q["name"] ?? "", q["input"] ?? "").1
            if let s = q["x-success"], var c = URLComponents(string: s) {
                c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "result", value: out)]
                if let u = c.url { Task { await UIApplication.shared.open(u) } }
            }
        case "clock":
            ClockBridge.callback(q)
        case "connector":
            Connectors.callback(q)
        default:
            break
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// 应用标志（图形定义在 Shared/BrandMark.swift，与桌面图标、灵动岛共用）
struct LogoMark: View {
    var size: CGFloat = 64
    var body: some View { BrandMark(size: size) }
}

// 文件显示：图片直接显示缩略图（不再套大框），其他文件显示一个小药丸。点击预览，长按可预览或分享。
struct FileCard: View {
    let url: URL
    @Binding var preview: URL?

    private var ext: String { url.pathExtension.lowercased() }
    private var isImage: Bool { Convert.imgExt.contains(ext) }

    private var kind: (String, String) {
        if isImage { return ("photo", "图片") }
        if ext == "pdf" { return ("doc.richtext", "PDF 文档") }
        if ["csv", "tsv", "json"].contains(ext) { return ("tablecells", "表格数据") }
        if ["txt", "md", "html", "rtf"].contains(ext) { return ("doc.text", "文本文档") }
        if Convert.vidExt.contains(ext) { return ("film", "视频") }
        if ext == "m4a" { return ("waveform", "音频") }
        return ("doc", "文件")
    }

    private var sizeText: String {
        guard let n = Files.size(url) else { return "文件不存在" }
        return n == 0 ? "空文件" : ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    var body: some View {
        if isImage {
            if let ui = Files.thumb(url, max: 900) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { preview = url }
                    .contextMenu { menu }
            } else {
                Label("这张图片无法读取", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.red)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: kind.0).font(.system(size: 18)).foregroundStyle(Brand.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.1).font(.subheadline.weight(.medium)).foregroundStyle(Brand.ink)
                    Text(sizeText).font(.caption).foregroundStyle(Brand.sub)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Brand.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { preview = url }
            .contextMenu { menu }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button { preview = url } label: { Label("预览", systemImage: "eye") }
        ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
    }
}
