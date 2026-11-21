import SwiftUI

// MARK: 存储空间：看清楚各类文件占了多少，一键清理；临时文件启动时自动清掉
enum StorageInfo {
    static func fileSize(_ u: URL) -> Int64 {
        Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
    }

    static func size(of u: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(u) }
        guard let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: []) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            total += fileSize(f)
        }
        return total
    }

    // 清空目录里的内容；cutoff 不为空时只删修改时间早于它的。返回释放的字节数
    @discardableResult
    static func clear(_ dir: URL, olderThan cutoff: Date? = nil, prefix: String? = nil) -> Int64 {
        let fm = FileManager.default
        guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return 0 }
        var freed: Int64 = 0
        for u in list {
            if let p = prefix, !u.lastPathComponent.hasPrefix(p) { continue }
            if let c = cutoff {
                let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if m > c { continue }
            }
            let s = size(of: u)
            if (try? fm.removeItem(at: u)) != nil { freed += s }
        }
        return freed
    }

    static var tmp: URL { FileManager.default.temporaryDirectory }
    static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
    // 只动本 App 自己的可再生缓存（头像、图标），不碰系统和第三方库的缓存目录
    static var ownCaches: [URL] { ["aiicons", "senderlogos"].map { caches.appendingPathComponent($0, isDirectory: true) } }

    static func clearOwnCaches() -> Int64 {
        var n: Int64 = 0
        for d in ownCaches { n += clear(d) }
        URLCache.shared.removeAllCachedResponses()
        return n
    }

    // 启动时清理本 App 留下的临时文件（超过 1 小时的）：快捷指令中转、转写切片等
    static func cleanTempAsync() {
        DispatchQueue.global(qos: .utility).async {
            clear(tmp, olderThan: Date().addingTimeInterval(-3600), prefix: "osvia-")
        }
    }

    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct StoragePage: View {
    private struct Item: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let note: String
        var bytes: Int64
    }

    @State private var rows: [Item] = []
    @State private var loading = true
    @State private var confirm: String?
    @State private var freed: Int64 = 0

    private static func make() -> [Item] {
        [
            Item(id: "out", icon: "tray.full", color: Brand.mint, title: "生成的文件", note: "转换、扫描、剪辑、打码等工具生成的结果", bytes: StorageInfo.size(of: Store.dir("Outputs"))),
            Item(id: "in", icon: "square.and.arrow.down", color: .blue, title: "导入的文件", note: "从相册、「文件」App、相机带进来的副本", bytes: StorageInfo.size(of: Store.dir("Inbox"))),
            Item(id: "tmp", icon: "clock.arrow.circlepath", color: .orange, title: "临时文件", note: "处理过程中的中转文件，可随时清理", bytes: StorageInfo.size(of: StorageInfo.tmp)),
            Item(id: "cache", icon: "internaldrive", color: .gray, title: "缓存", note: "头像和图标缓存，会按需重新生成", bytes: StorageInfo.ownCaches.reduce(0) { $0 + StorageInfo.size(of: $1) })
        ]
    }

    private func reload() {
        loading = true
        Task {
            let r = await Task<[Item], Never>.detached(priority: .utility) { StoragePage.make() }.value
            rows = r
            loading = false
        }
    }

    private var total: Int64 { rows.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("合计")
                    Spacer()
                    if loading { ProgressView() } else { Text(verbatim: StorageInfo.text(total)).foregroundStyle(Brand.sub) }
                }
            } footer: {
                if freed > 0 { Text(L10n.f("已释放 {}", StorageInfo.text(freed))) }
            }
            Section {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: r.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 29, height: 29).background(r.color)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(r.title)).foregroundStyle(Brand.ink)
                                Text(LocalizedStringKey(r.note)).font(.caption).foregroundStyle(Brand.sub)
                            }
                            Spacer(minLength: 8)
                            Text(verbatim: StorageInfo.text(r.bytes)).foregroundStyle(Brand.sub)
                        }
                        if r.bytes > 0 {
                            HStack(spacing: 18) {
                                if r.id == "out" || r.id == "in" {
                                    Button("清理 7 天前的") { confirm = r.id + ":7" }
                                }
                                Button("全部清理", role: .destructive) { confirm = r.id + ":0" }
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .padding(.leading, 41)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("清理「生成的文件」和「导入的文件」后，对话里引用过的这些文件将无法再预览。本地大模型在 设置 → 本地大模型 里管理。")
            }
        }
        .navigationTitle("存储空间")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .confirmationDialog("确定清理吗？此操作无法撤销", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("清理", role: .destructive) {
                guard let c = confirm else { return }
                confirm = nil
                let parts = c.components(separatedBy: ":")
                let days = Int(parts.last ?? "0") ?? 0
                let cutoff: Date? = days > 0 ? Date().addingTimeInterval(-Double(days) * 86400) : nil
                let id = parts.first ?? ""
                Task {
                    let n: Int64 = await Task.detached(priority: .utility) {
                        switch id {
                        case "out": return StorageInfo.clear(Store.dir("Outputs"), olderThan: cutoff)
                        case "in": return StorageInfo.clear(Store.dir("Inbox"), olderThan: cutoff)
                        case "tmp": return StorageInfo.clear(StorageInfo.tmp, olderThan: Date().addingTimeInterval(-600))
                        default: return StorageInfo.clearOwnCaches()
                        }
                    }.value
                    freed += n
                    reload()
                }
            }
        }
    }
}
