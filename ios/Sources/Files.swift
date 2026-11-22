import Foundation
import UIKit
import ImageIO

// 文件与图片的稳健读取：校验、缩略图、文件大小、从「文件」App 导入
enum Files {
    // 文件大小（字节）；读不到返回 nil，不再误显示 0
    static func size(_ u: URL) -> Int64? {
        guard let n = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(n)
    }

    static func isImage(_ u: URL) -> Bool { Convert.imgExt.contains(u.pathExtension.lowercased()) }

    // 系统能否把它解码成图片（按内容判断，不看扩展名）。ImageIO 不行时再用 UIImage 与原始数据各试一次
    static func readable(_ u: URL) -> Bool {
        if (size(u) ?? 0) == 0 { return false }
        if let s = CGImageSourceCreateWithURL(u as CFURL, nil), CGImageSourceGetCount(s) > 0 { return true }
        if UIImage(contentsOfFile: u.path) != nil { return true }
        if let raw = try? Data(contentsOf: u), UIImage(data: raw) != nil { return true }
        return false
    }

    private static let cache = NSCache<NSString, UIImage>()

    // 缩略图：按长边缩放并带缓存，界面刷新时不再反复解码大图
    static func thumb(_ u: URL, max px: CGFloat = 300) -> UIImage? {
        let stamp = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(u.path)|\(Int(px))|\(stamp)" as NSString
        if let c = cache.object(forKey: key) { return c }
        var img: UIImage?
        if let s = CGImageSourceCreateWithURL(u as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(px)
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary) { img = UIImage(cgImage: cg) }
        }
        if img == nil { img = UIImage(contentsOfFile: u.path) }
        guard let out = img else { return nil }
        cache.setObject(out, forKey: key)
        return out
    }

    // 转成方向正确、长边不超过 maxPixel 的 JPEG（HEIC、竖拍、超大图都能稳定读取，识别文字不会躺倒）
    // 三层兜底：ImageIO 缩略图 → UIImage 文件解码 → 原始数据解码
    static func normalizedJPEG(from src: URL, maxPixel: Int = 3072) -> Data? {
        if let s = CGImageSourceCreateWithURL(src as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary),
               let d = UIImage(cgImage: cg).jpegData(compressionQuality: 0.92) { return d }
        }
        if let ui = UIImage(contentsOfFile: src.path), let d = ui.jpegData(compressionQuality: 0.92) { return d }
        if let raw = try? Data(contentsOf: src), let ui = UIImage(data: raw), let d = ui.jpegData(compressionQuality: 0.92) { return d }
        return nil
    }

    // iCloud 文件要等下载、大视频要整份拷贝：放到后台做，界面不会卡住
    static func importFileAsync(_ src: URL) async -> (url: URL?, error: String?) {
        await Task.detached(priority: .userInitiated) { Files.importFile(src) }.value
    }

    // 从「文件」App 导入：协调读取（会触发 iCloud 下载），并校验文件非空、图片可打开
    static func importFile(_ src: URL) -> (url: URL?, error: String?) {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        let name = src.lastPathComponent
        let dst = Store.dir("Inbox").appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        var copied = false
        var coordErr: NSError?
        NSFileCoordinator().coordinate(readingItemAt: src, options: [], error: &coordErr) { u in
            copied = (try? FileManager.default.copyItem(at: u, to: dst)) != nil
        }
        guard copied else { return (nil, "「\(name)」读取失败。如果它在 iCloud 里，请先在「文件」App 里下载到本机。") }
        if (size(dst) ?? 0) == 0 {
            try? FileManager.default.removeItem(at: dst)
            return (nil, "「\(name)」是空文件。")
        }
        if isImage(dst) && !readable(dst) {
            try? FileManager.default.removeItem(at: dst)
            return (nil, "「\(name)」不是有效的图片。")
        }
        return (dst, nil)
    }
}
