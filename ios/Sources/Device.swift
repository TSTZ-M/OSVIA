import SwiftUI
import UIKit
import CoreLocation
import Contacts

// MARK: 设备能力：位置、通讯录、已安装的 App、剪贴板、导出到备忘录/文件/任意 App
// iOS 不允许读取其他 App 的内部数据；能做的是：用系统授权读取位置/通讯录/日历/提醒/照片，
// 用 URL Scheme 检测并打开常用 App，用分享面板把内容交给备忘录、文件、Pages、Obsidian 等任何接受文本/文件的 App。

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let mgr = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var allowed: Bool { mgr.authorizationStatus == .authorizedWhenInUse || mgr.authorizationStatus == .authorizedAlways }

    struct Fix {
        var lat: Double
        var lon: Double
        var accuracy: Double
        var place: String
    }

    // 返回 (位置, 错误)。第一次会弹出系统授权
    func current() async -> (Fix?, String) {
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                authWaiters.append(c)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    self?.flushAuth()
                }
            }
        }
        guard allowed else { return (nil, "没有定位权限。请到「设置 › OSVIA › 位置」里选择「使用 App 期间」。") }
        let loc: CLLocation? = await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            waiters.append(c)
            mgr.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self?.flush(nil)
            }
        }
        guard let l = loc ?? mgr.location else { return (nil, "暂时定位不到，请确认定位服务已开启，并到室外或窗边再试。") }
        var fix = Fix(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy, place: "")
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(l, preferredLocale: Locale(identifier: "zh_CN")).first {
            var parts: [String] = []
            for v in [pm.country, pm.administrativeArea, pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare] {
                if let v, !v.isEmpty, !parts.contains(v) { parts.append(v) }
            }
            fix.place = parts.joined(separator: " ")
        }
        return (fix, "")
    }

    private func flush(_ l: CLLocation?) {
        let w = waiters
        waiters = []
        for c in w { c.resume(returning: l) }
    }

    private func flushAuth() {
        let w = authWaiters
        authWaiters = []
        for c in w { c.resume() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in self.flush(l) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.flush(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.flushAuth() }
    }
}

@MainActor
enum Export {
    // 系统分享面板：备忘录、文件、Pages、Word、Obsidian、Bear、Notion 等所有接受文本或文件的 App 都在里面。返回用户选的去处，取消返回空串
    static func share(_ items: [Any], title: String = "") async -> String {
        guard let vc = UIApplication.shared.topVC else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let a = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if !title.isEmpty { a.setValue(title, forKey: "subject") }
            a.completionWithItemsHandler = { type, done, _, _ in
                cont.resume(returning: done ? (type?.rawValue ?? "done") : "")
            }
            if let p = a.popoverPresentationController {
                p.sourceView = vc.view
                p.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
                p.permittedArrowDirections = []
            }
            vc.present(a, animated: true)
        }
    }

    @MainActor
    private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        var done: ((Bool) -> Void)?
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done?(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done?(false) }
    }

    private static var picker: PickerDelegate?

    // 存到「文件」：iCloud 云盘、本机、Dropbox、OneDrive 等任何文件提供方的文件夹
    static func saveToFiles(_ urls: [URL]) async -> Bool {
        guard let vc = UIApplication.shared.topVC, !urls.isEmpty else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let p = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
            let d = PickerDelegate()
            d.done = { ok in
                picker = nil
                cont.resume(returning: ok)
            }
            picker = d
            p.delegate = d
            vc.present(p, animated: true)
        }
    }

    // 把一段文字写成临时文件（用于「存为文件」）
    static func tempFile(named name: String, text: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let u = dir.appendingPathComponent(safe)
        do {
            try text.write(to: u, atomically: true, encoding: .utf8)
            return u
        } catch {
            return nil
        }
    }

    // 用正文第一行做文件名
    static func suggestedName(for text: String, ext: String = "md") -> String {
        let first = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "OSVIA"
        var t = first.trimmingCharacters(in: CharacterSet(charactersIn: "# *>-").union(.whitespaces))
        t = String(t.prefix(24))
        if t.isEmpty { t = "OSVIA" }
        return ext.isEmpty ? t : t + "." + ext
    }
}

// 回复下方的「存到…」菜单
struct ExportMenu: View {
    let text: String

    var body: some View {
        Menu {
            Button {
                Task { _ = await Export.share([text], title: Export.suggestedName(for: text, ext: "")) }
            } label: { Label("备忘录 / 其他 App…", systemImage: "note.text") }
            Button {
                if let u = Export.tempFile(named: Export.suggestedName(for: text), text: text) {
                    Task { _ = await Export.saveToFiles([u]) }
                }
            } label: { Label("存为文件（Markdown）", systemImage: "folder") }
            Button {
                if let u = Export.tempFile(named: Export.suggestedName(for: text, ext: "txt"), text: text) {
                    Task { _ = await Export.share([u]) }
                }
            } label: { Label("以文件发送到 Pages / Word…", systemImage: "doc.richtext") }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
}

@MainActor
enum DeviceTools {
    static func doc() -> String {
        var s = ""
        s += "- location {}：用户当前位置（地址、经纬度）。问「附近」「我在哪」「本地」「离这儿多远」时先用它；之后可配合 maps、weather\n"
        s += "- contacts {\"q\":\"姓名或公司\"}：查通讯录里的联系人电话和邮箱（会先问用户）\n"
        s += "- apps {}：看用户装了哪些常用 App（微信、支付宝、Obsidian、Notion 等），再决定用 open_app 打开哪个\n"
        s += "- read_clipboard {}：读取剪贴板里的文字（用户说「我刚复制的」「剪贴板」时用，系统可能弹出粘贴确认）\n"
        s += "- share {\"text\":\"内容\",\"file\":\"工作区文件名\",\"title\":\"标题\",\"to\":\"share|files\"}：把文字或文件交给用户：share 打开系统分享面板（备忘录、Pages、Obsidian、微信等都在里面，用户点选），files 存到「文件」。「存到备忘录」「导出」「发给…」用它\n"
        return s
    }

    private static func str(_ a: [String: Any], _ k: String) -> String {
        if let s = a[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return ""
    }

    static func run(_ c: ToolCall, trace: Tracer, cloud: Bool) async -> ToolResult? {
        let a = c.args
        switch c.name {
        case "location":
            let sid = trace.begin(.map, "获取当前位置", "")
            let (fix, err) = await LocationService.shared.current()
            guard let f = fix else {
                trace.end(sid, ok: false, detail: L10n.tr(err))
                return ToolResult(text: err, ok: false)
            }
            let place = f.place.isEmpty ? String(format: "%.4f, %.4f", f.lat, f.lon) : f.place
            trace.end(sid, detail: place)
            return ToolResult(text: "当前位置：\(f.place.isEmpty ? "（没有地址信息）" : f.place)；纬度 \(String(format: "%.5f", f.lat))，经度 \(String(format: "%.5f", f.lon))，精度约 \(Int(f.accuracy)) 米。")

        case "contacts":
            return await contacts(str(a, "q"), trace)

        case "apps":
            let list = Hands.installedApps()
            trace.note(.phone, "检查已安装的 App", L10n.f("{} 个", "\(list.count)"))
            return ToolResult(text: list.isEmpty ? "没有检测到常用第三方 App（系统不允许列出全部 App，只能检测常用的）。" : "已安装的常用 App：" + list.joined(separator: "、") + "。（系统不允许列出全部 App，只能检测常用的。）")

        case "read_clipboard":
            guard UIPasteboard.general.hasStrings, let s = UIPasteboard.general.string, !s.isEmpty else {
                return ToolResult(text: "剪贴板里没有文字。", ok: false)
            }
            trace.note(.phone, "读取剪贴板", String(s.prefix(30)))
            return ToolResult(text: "剪贴板内容：\n" + String(s.prefix(6000)))

        case "share":
            return await share(a, trace)

        default:
            return await MoreTools.run(c, trace: trace, cloud: cloud)
        }
    }

    private static func contacts(_ q: String, _ trace: Tracer) async -> ToolResult {
        guard !q.isEmpty else { return ToolResult(text: "需要联系人姓名或公司。", ok: false) }
        let ok = await Agent.shared.requestConfirm(title: L10n.f("查看通讯录：{}", q), detail: L10n.tr("助理想读取这个联系人的电话和邮箱，用来完成你的请求。"))
        guard ok else { return ToolResult(text: "用户拒绝了读取通讯录。", ok: false) }
        let sid = trace.begin(.phone, "查通讯录", q)
        let store = CNContactStore()
        do {
            if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
                _ = try await store.requestAccess(for: .contacts)
            }
            let st = CNContactStore.authorizationStatus(for: .contacts)
            guard st == .authorized else {
                trace.end(sid, ok: false, detail: L10n.tr("没有通讯录权限"))
                return ToolResult(text: "没有通讯录权限。请到「设置 › OSVIA › 通讯录」打开。", ok: false)
            }
            let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                           CNContactPhoneNumbersKey as CNKeyDescriptor,
                                           CNContactEmailAddressesKey as CNKeyDescriptor,
                                           CNContactOrganizationNameKey as CNKeyDescriptor]
            let found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: q), keysToFetch: keys)
            if found.isEmpty {
                trace.end(sid, ok: false, detail: q + " · " + L10n.tr("没有找到"))
                return ToolResult(text: "通讯录里没有找到「\(q)」。", ok: false)
            }
            var lines: [String] = []
            for c in found.prefix(6) {
                let name = CNContactFormatter.string(from: c, style: .fullName) ?? c.organizationName
                var s = "- " + name
                if !c.organizationName.isEmpty, c.organizationName != name { s += "（\(c.organizationName)）" }
                let ph = c.phoneNumbers.map { $0.value.stringValue }
                let em = c.emailAddresses.map { String($0.value) }
                if !ph.isEmpty { s += " 电话：" + ph.joined(separator: "、") }
                if !em.isEmpty { s += " 邮箱：" + em.joined(separator: "、") }
                lines.append(s)
            }
            trace.end(sid, detail: L10n.f("{} 位联系人", "\(found.count)"))
            return ToolResult(text: lines.joined(separator: "\n"))
        } catch {
            trace.end(sid, ok: false, detail: String(error.localizedDescription.prefix(40)))
            return ToolResult(text: "读取通讯录失败：" + error.localizedDescription, ok: false)
        }
    }

    private static func share(_ a: [String: Any], _ trace: Tracer) async -> ToolResult {
        let text = str(a, "text")
        let file = str(a, "file")
        let title = str(a, "title")
        let to = str(a, "to")
        var items: [Any] = []
        var urls: [URL] = []
        if !file.isEmpty {
            guard let u = Hands.workspaceURL(file) else { return ToolResult(text: "工作区里没有这个文件，可以先用 list_files 看看。", ok: false) }
            urls = [u]
            items = [u]
        } else if !text.isEmpty {
            if to == "files" {
                guard let u = Export.tempFile(named: Export.suggestedName(for: title.isEmpty ? text : title), text: text) else {
                    return ToolResult(text: "没能生成临时文件。", ok: false)
                }
                urls = [u]
            }
            items = [text]
        } else {
            return ToolResult(text: "需要 text 或 file。", ok: false)
        }
        let sid = trace.begin(.phone, to == "files" ? "存到「文件」" : "打开分享面板", title.isEmpty ? String((file.isEmpty ? text : file).prefix(24)) : title)
        if to == "files" {
            let ok = await Export.saveToFiles(urls)
            trace.end(sid, ok: ok, detail: ok ? nil : L10n.tr("已取消"))
            return ToolResult(text: ok ? "已存到「文件」。" : "用户取消了保存。", final: ok, ok: ok)
        }
        let dest = await Export.share(items, title: title)
        trace.end(sid, ok: !dest.isEmpty, detail: dest.isEmpty ? L10n.tr("已取消") : nil)
        return ToolResult(text: dest.isEmpty ? "用户关闭了分享面板，没有发送。" : "已交给用户选择的 App（\(dest.split(separator: ".").last.map(String.init) ?? dest)）。", final: !dest.isEmpty, ok: !dest.isEmpty)
    }
}
