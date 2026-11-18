import Foundation
import SwiftUI
import UIKit
import os
import MLX

// MARK: 崩溃防护
// 1. 内存余量：载入本地大模型前先看系统还允许本进程再用多少内存，不够就不载入（系统会直接杀掉进程，表现就是闪退）
// 2. MLX 缓存上限：MLX 默认缓存不设上限，生成几次后占用会一路涨到被系统杀掉
// 3. 闪退循环自动进入「安全模式」：连续两次启动都异常结束，就暂停本地模型和自动任务，保证至少能打开
// 4. 本地模型「在途标记」：模型载入或生成期间留一个文件，下次启动还在，说明上次死在模型里，自动停用本地模型
enum Safety {
    private static let crashKey = "safety.crashes"
    private static let localOffKey = "safety.localOff"
    private static let lock = NSLock()
    private static var _safe = false
    private static var stableWork: DispatchWorkItem?
    private static var tuned = false

    // MARK: 状态
    static var safeMode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _safe
    }

    // 上次死在本地模型里，已自动停用
    static var localOff: Bool { UserDefaults.standard.bool(forKey: localOffKey) }

    // 本地模型是否允许使用
    static var localAllowed: Bool { !safeMode && !localOff }

    // 界面上的提示文字；空串表示一切正常
    static func notice() -> String {
        if safeMode { return "检测到连续闪退，已进入安全模式：暂停本地模型和自动任务，聊天仍可正常使用。" }
        if localOff { return "本地模型上次运行时被系统终止（多半是内存不足），已自动停用，改用系统自带模型。" }
        return ""
    }

    // MARK: 启动与前后台
    // 启动时调用：abnormal = 上一次是否在前台异常结束
    static func launch(abnormal: Bool) {
        let ud = UserDefaults.standard
        var n = ud.integer(forKey: crashKey)
        if abnormal { n += 1 }
        ud.set(n, forKey: crashKey)
        lock.lock()
        _safe = n >= 2
        lock.unlock()
        if FileManager.default.fileExists(atPath: markerURL.path) {
            try? FileManager.default.removeItem(at: markerURL)
            ud.set(true, forKey: localOffKey)
            Diag.mark("上次死在本地模型运行中：已自动停用本地模型")
        }
        Diag.mark("启动自检：连续异常 \(n) 次，安全模式\(safeMode ? "开" : "关")，内存余量 \(availableBytes() >> 20) MB")
        SafetyState.shared.refresh()
    }

    // 进入前台：稳定运行 25 秒就把闪退计数清零（安全模式下不清零，要用户点「恢复」）
    static func foreground() {
        stableWork?.cancel()
        stableWork = nil
        guard !safeMode else { return }
        let w = DispatchWorkItem {
            UserDefaults.standard.set(0, forKey: crashKey)
            Diag.mark("稳定运行 25 秒，闪退计数清零")
        }
        stableWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: w)
    }

    static func background() {
        stableWork?.cancel()
        stableWork = nil
    }

    // 用户点「恢复」：退出安全模式，重新启用本地模型
    static func restore() {
        let ud = UserDefaults.standard
        ud.set(0, forKey: crashKey)
        ud.set(false, forKey: localOffKey)
        lock.lock()
        _safe = false
        lock.unlock()
        try? FileManager.default.removeItem(at: markerURL)
        Diag.mark("用户恢复正常模式")
        SafetyState.shared.refresh()
        foreground()
    }

    // MARK: 本地模型在途标记
    private static var markerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mlx-inflight")
    }

    static func begin() { try? Data("1".utf8).write(to: markerURL) }

    static func end() { try? FileManager.default.removeItem(at: markerURL) }

    // MARK: 内存
    // 系统还允许本进程再用多少字节（真机才有值；拿不到时返回 0，表示「不限制」）
    static func availableBytes() -> Int { max(os_proc_available_memory(), 0) }

    // MLX 缓存上限：官方 iOS 示例也这样设
    static func tuneMLX() {
        guard !tuned else { return }
        tuned = true
        MLX.Memory.cacheLimit = 32 * 1024 * 1024
    }

    // 释放 MLX 缓存的显存。没载入过本地模型就什么都不做：
    // 不能为了「清缓存」去初始化一遍 Metal 和 MLX（每次进后台、内存警告都会走到这里）
    static func trimMLX() {
        guard tuned else { return }
        MLX.Memory.clearCache()
    }
}

// 界面用：安全提示条
final class SafetyState: ObservableObject {
    static let shared = SafetyState()
    @Published var notice = ""
    @Published var crash = false

    func refresh() {
        let n = Safety.notice()
        let c = Diag.hasLead
        if Thread.isMainThread { notice = n; crash = c } else { DispatchQueue.main.async { self.notice = n; self.crash = c } }
    }
}

struct SafetyBanner: View {
    @ObservedObject private var s = SafetyState.shared
    @State private var copied = false

    var body: some View {
        VStack(spacing: 6) {
            if !s.notice.isEmpty { safeCard }
            if s.crash { crashCard }
        }
    }

    private var safeCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(.orange).padding(.top, 2)
            Text(L10n.tr(s.notice)).font(.footnote).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(L10n.tr("恢复")) { Safety.restore() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.mint)
        }
        .modifier(BannerStyle())
    }

    // 上次异常退出：一键复制诊断信息（崩溃调用栈、内存、最后的操作），发给开发者即可定位
    private var crashCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "ladybug").foregroundStyle(.red).padding(.top, 2)
            Text(copied ? "已复制，直接粘贴发给开发者" : "上次异常退出，已记下现场。点「复制」发给开发者，就能定位原因。")
                .font(.footnote).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(copied ? "收起" : "复制") {
                if copied {
                    Diag.acknowledge()
                    copied = false
                } else {
                    UIPasteboard.general.string = Diag.report()
                    copied = true
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Brand.mint)
            if !copied {
                Button("忽略") { Diag.acknowledge() }
                    .font(.footnote)
                    .foregroundStyle(Brand.sub)
            }
        }
        .modifier(BannerStyle())
    }
}

private struct BannerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.line, lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
