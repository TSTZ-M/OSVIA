import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// MARK: 去水印引擎（纯本机）
// 思路：把用户框出的区域当作「空洞」，用周围的真实像素做 push-pull 多尺度填充，再迭代平滑，最后补回和周围一致的颗粒。
// 适合纯色、渐变、虚化背景上的固定水印；复杂纹理背景会留下痕迹。
enum Delogo {
    // 在 BGRA / RGBA 像素缓冲里依次处理若干矩形（像素坐标，左上角为原点）
    static func apply(_ base: UnsafeMutablePointer<UInt8>, stride: Int, width: Int, height: Int,
                      rects: [CGRect], smart: Bool, bgra: Bool) {
        for r in rects { one(base, stride, width, height, r, smart, bgra) }
    }

    private static func one(_ base: UnsafeMutablePointer<UInt8>, _ stride: Int, _ width: Int, _ height: Int,
                            _ rect: CGRect, _ smart: Bool, _ bgra: Bool) {
        // 区域坐标可能来自模型参数（NaN / 超大值），先截断到画面范围再转整数，避免 Int() 陷阱崩溃
        func px(_ v: CGFloat, _ hi: Int) -> Int { v.isFinite ? Int(min(max(v, 0), CGFloat(hi))) : 0 }
        let x0 = px(rect.minX.rounded(.down), width)
        let y0 = px(rect.minY.rounded(.down), height)
        let x1 = px(rect.maxX.rounded(.up), width)
        let y1 = px(rect.maxY.rounded(.up), height)
        guard x1 - x0 >= 2, y1 - y0 >= 2 else { return }
        let rw = x1 - x0
        let rh = y1 - y0
        var m = max(16, max(rw, rh) / 2)
        // 参考区域太大会吃掉几百 MB 内存：逐步收窄周围的参考范围，总像素控制在 1600 万以内
        while m > 16, (min(width, x1 + m) - max(0, x0 - m)) * (min(height, y1 + m) - max(0, y0 - m)) > 16_000_000 { m = max(16, m / 2) }
        let cx0 = max(0, x0 - m)
        let cy0 = max(0, y0 - m)
        let cx1 = min(width, x1 + m)
        let cy1 = min(height, y1 + m)
        let cw = cx1 - cx0
        let ch = cy1 - cy0
        guard cw > rw || ch > rh else { return }   // 框住了整张图，没有可参考的周围
        guard cw * ch <= 24_000_000 else { return }
        let n = cw * ch
        let ro = bgra ? 2 : 0
        let bo = bgra ? 0 : 2

        var px = [Float](repeating: 0, count: n * 3)
        var lum = [Float](repeating: 0, count: n)
        for y in 0..<ch {
            let row = base + (cy0 + y) * stride + cx0 * 4
            for x in 0..<cw {
                let p = row + x * 4
                let i = y * cw + x
                let r = Float(p[ro]), g = Float(p[1]), b = Float(p[bo])
                px[i * 3] = r
                px[i * 3 + 1] = g
                px[i * 3 + 2] = b
                lum[i] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        var hole = [Bool](repeating: false, count: n)
        for y in (y0 - cy0)..<(y1 - cy0) {
            for x in (x0 - cx0)..<(x1 - cx0) { hole[y * cw + x] = true }
        }

        // 周围的颗粒强度：用环带里「像素与四邻均值之差」的中位数估计
        var ringDiffs: [Float] = []
        var yy = 1
        while yy < ch - 1 {
            var xx = 1
            while xx < cw - 1 {
                let i = yy * cw + xx
                if !hole[i] && !hole[i - 1] && !hole[i + 1] && !hole[i - cw] && !hole[i + cw] {
                    ringDiffs.append(abs(lum[i] - (lum[i - 1] + lum[i + 1] + lum[i - cw] + lum[i + cw]) / 4))
                }
                xx += 2
            }
            yy += 2
        }
        let grain = min(8, median(ringDiffs) * 1.4826 * 0.894 * 0.9)

        var mask = hole
        if smart, let thin = thinMask(lum, hole, cw, ch, ringDiffs) { mask = thin }

        let known = mask.map { !$0 }
        let filled = fill(px, known, cw, ch)

        var seed = UInt32(truncatingIfNeeded: x0 &* 73856093 ^ y0 &* 19349663 ^ 0x9E3779B9)
        if seed == 0 { seed = 1 }
        for y in 0..<ch {
            for x in 0..<cw {
                let i = y * cw + x
                guard mask[i] else { continue }
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                let u = Float(seed & 0xFFFF) / 65535 - 0.5
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                let v = Float(seed & 0xFFFF) / 65535 - 0.5
                let noise = (u + v) * 1.73 * grain   // 近似高斯
                let p = base + (cy0 + y) * stride + (cx0 + x) * 4
                p[ro] = clamp(filled[i * 3] + noise)
                p[1] = clamp(filled[i * 3 + 1] + noise)
                p[bo] = clamp(filled[i * 3 + 2] + noise)
            }
        }
    }

    private static func clamp(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }

    private static func median(_ a: [Float]) -> Float {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted()
        return s[s.count / 2]
    }

    // 细线条水印（半透明文字）：只挑出和局部中位数差得多的像素，其余纹理保留
    private static func thinMask(_ lum: [Float], _ hole: [Bool], _ w: Int, _ h: Int, _ ring: [Float]) -> [Bool]? {
        let rad = 5
        // 选区超过 150 万像素时逐点取中位数太慢，直接走普通填充
        guard hole.reduce(0, { $0 + ($1 ? 1 : 0) }) <= 1_500_000 else { return nil }
        var dev = [Float](repeating: 0, count: w * h)
        var win = [Float](repeating: 0, count: (2 * rad + 1) * (2 * rad + 1))
        var cnt = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard hole[i] else { continue }
                var k = 0
                for dy in -rad...rad {
                    let yy = min(max(y + dy, 0), h - 1)
                    for dx in -rad...rad {
                        let xx = min(max(x + dx, 0), w - 1)
                        win[k] = lum[yy * w + xx]
                        k += 1
                    }
                }
                win.sort()
                dev[i] = abs(lum[i] - win[win.count / 2])
                cnt += 1
            }
        }
        guard cnt > 0 else { return nil }
        let thr = max(10, median(ring) * 6)
        var flag = [Bool](repeating: false, count: w * h)
        var hit = 0
        for i in 0..<(w * h) where hole[i] && dev[i] > thr {
            flag[i] = true
            hit += 1
        }
        let frac = Double(hit) / Double(cnt)
        guard frac > 0.015 && frac < 0.6 else { return nil }
        // 向外膨胀 2 圈，盖住抗锯齿边缘
        for _ in 0..<2 {
            var next = flag
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    guard hole[i], !flag[i] else { continue }
                    if (x > 0 && flag[i - 1]) || (x < w - 1 && flag[i + 1]) || (y > 0 && flag[i - w]) || (y < h - 1 && flag[i + w])
                        || (x > 0 && y > 0 && flag[i - w - 1]) || (x < w - 1 && y > 0 && flag[i - w + 1])
                        || (x > 0 && y < h - 1 && flag[i + w - 1]) || (x < w - 1 && y < h - 1 && flag[i + w + 1]) { next[i] = true }
                }
            }
            flag = next
        }
        return flag
    }

    // push-pull 填充：逐级缩小（只对已知像素求平均），再逐级放大，空洞用上一级的双线性插值补；最后做几轮高斯-赛德尔平滑
    private static func fill(_ px: [Float], _ known: [Bool], _ w: Int, _ h: Int) -> [Float] {
        var sums: [[Float]] = []
        var cnts: [[Float]] = []
        var dims: [(Int, Int)] = []
        var c0 = [Float](repeating: 0, count: w * h * 3)
        var k0 = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) where known[i] {
            c0[i * 3] = px[i * 3]
            c0[i * 3 + 1] = px[i * 3 + 1]
            c0[i * 3 + 2] = px[i * 3 + 2]
            k0[i] = 1
        }
        sums.append(c0)
        cnts.append(k0)
        dims.append((w, h))
        while dims[dims.count - 1].0 > 1 || dims[dims.count - 1].1 > 1 {
            let (lw, lh) = dims[dims.count - 1]
            let nw = (lw + 1) / 2
            let nh = (lh + 1) / 2
            var c = [Float](repeating: 0, count: nw * nh * 3)
            var k = [Float](repeating: 0, count: nw * nh)
            let pc = sums[sums.count - 1]
            let pk = cnts[cnts.count - 1]
            for y in 0..<lh {
                for x in 0..<lw {
                    let i = y * lw + x
                    let kk = pk[i]
                    if kk == 0 { continue }
                    let j = (y >> 1) * nw + (x >> 1)
                    c[j * 3] += pc[i * 3]
                    c[j * 3 + 1] += pc[i * 3 + 1]
                    c[j * 3 + 2] += pc[i * 3 + 2]
                    k[j] += kk
                }
            }
            sums.append(c)
            cnts.append(k)
            dims.append((nw, nh))
        }
        let top = dims.count - 1
        var cur: [Float] = [128, 128, 128]
        if cnts[top][0] > 0 {
            cur = [sums[top][0] / cnts[top][0], sums[top][1] / cnts[top][0], sums[top][2] / cnts[top][0]]
        }
        var lv = top - 1
        while lv >= 0 {
            let (lw, lh) = dims[lv]
            let (pw, ph) = dims[lv + 1]
            var out = [Float](repeating: 0, count: lw * lh * 3)
            for y in 0..<lh {
                for x in 0..<lw {
                    let i = y * lw + x
                    let kk = cnts[lv][i]
                    if kk > 0 {
                        out[i * 3] = sums[lv][i * 3] / kk
                        out[i * 3 + 1] = sums[lv][i * 3 + 1] / kk
                        out[i * 3 + 2] = sums[lv][i * 3 + 2] / kk
                        continue
                    }
                    let fx = (Float(x) + 0.5) / 2 - 0.5
                    let fy = (Float(y) + 0.5) / 2 - 0.5
                    let flx = fx.rounded(.down)
                    let fly = fy.rounded(.down)
                    let tx = fx - flx
                    let ty = fy - fly
                    let xa = min(max(Int(flx), 0), pw - 1)
                    let xb = min(max(Int(flx) + 1, 0), pw - 1)
                    let ya = min(max(Int(fly), 0), ph - 1)
                    let yb = min(max(Int(fly) + 1, 0), ph - 1)
                    for c in 0..<3 {
                        let a = cur[(ya * pw + xa) * 3 + c]
                        let b = cur[(ya * pw + xb) * 3 + c]
                        let d = cur[(yb * pw + xa) * 3 + c]
                        let e = cur[(yb * pw + xb) * 3 + c]
                        out[i * 3 + c] = (a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty
                    }
                }
            }
            cur = out
            lv -= 1
        }
        // 平滑：只改空洞里的像素，已知像素是固定边界
        var holes: [Int] = []
        for i in 0..<(w * h) where !known[i] { holes.append(i) }
        let reversedHoles = Array(holes.reversed())
        for pass in 0..<16 {
            let order: [Int] = pass % 2 == 0 ? holes : reversedHoles
            for i in order {
                let x = i % w
                let y = i / w
                let l = x > 0 ? i - 1 : i
                let r = x < w - 1 ? i + 1 : i
                let u = y > 0 ? i - w : i
                let d = y < h - 1 ? i + w : i
                for c in 0..<3 {
                    cur[i * 3 + c] = (cur[l * 3 + c] + cur[r * 3 + c] + cur[u * 3 + c] + cur[d * 3 + c]) / 4
                }
            }
        }
        return cur
    }

    // MARK: 图片
    static func image(_ src: URL, regions: [CGRect], smart: Bool) throws -> URL {
        guard let cg = OCR.cg(src, maxPixel: 6144) else { throw Convert.err("无法读取图片") }
        let w = cg.width
        let h = cg.height
        let png = src.pathExtension.lowercased() == "png"
        var data: Data?
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let rects = regions.map { r in
                CGRect(x: r.minX * Double(w), y: r.minY * Double(h), width: r.width * Double(w), height: r.height * Double(h)).insetBy(dx: -2, dy: -2)
            }
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            apply(base, stride: w * 4, width: w, height: h, rects: rects, smart: smart, bgra: true)
            guard let out = ctx.makeImage() else { return }
            let ui = UIImage(cgImage: out)
            data = png ? ui.pngData() : ui.jpegData(compressionQuality: 0.95)
        }
        guard let d = data else { throw Convert.err("处理失败") }
        let name = src.deletingPathExtension().lastPathComponent + "-去水印"
        let dst = Convert.out(name, png ? "png" : "jpg")
        try d.write(to: dst)
        return dst
    }

    // MARK: 视频（固定位置的水印；逐帧处理，声音原样保留）
    final class Cancel { var on = false }

    static func video(_ src: URL, regions: [CGRect], progress: @escaping (Double) -> Void, cancel: Cancel) async throws -> URL {
        let asset = AVURLAsset(url: src)
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else { throw Convert.err("没有找到视频画面") }
        let size = try await vt.load(.naturalSize)
        let tf = try await vt.load(.preferredTransform)
        let rate = try await vt.load(.estimatedDataRate)
        let durationSeconds = try await asset.load(.duration).seconds
        let total = max(durationSeconds, 0.001)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        var fmt: CMFormatDescription?
        if let at = audioTrack { fmt = try await at.load(.formatDescriptions).first }

        let W = Int(size.width.rounded())
        let H = Int(size.height.rounded())
        let disp = size.applying(tf)
        let dw = abs(disp.width)
        let dh = abs(disp.height)
        let inv = tf.inverted()
        let rects: [CGRect] = regions.map { r in
            let pts = [CGPoint(x: r.minX * dw, y: r.minY * dh), CGPoint(x: r.maxX * dw, y: r.minY * dh),
                       CGPoint(x: r.minX * dw, y: r.maxY * dh), CGPoint(x: r.maxX * dw, y: r.maxY * dh)].map { $0.applying(inv) }
            let xs = pts.map { $0.x }
            let ys = pts.map { $0.y }
            return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
                .insetBy(dx: -2, dy: -2)
        }

        let reader = try AVAssetReader(asset: asset)
        let vout = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(vout) else { throw Convert.err("无法读取视频") }
        reader.add(vout)

        let mov = src.pathExtension.lowercased() == "mov"
        let base = src.deletingPathExtension().lastPathComponent + "-去水印"
        let dst = Convert.out(base, mov ? "mov" : "mp4")
        try? FileManager.default.removeItem(at: dst)
        let writer = try AVAssetWriter(outputURL: dst, fileType: mov ? .mov : .mp4)
        let vin = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(rate.isFinite ? Int(min(rate, 100_000_000) * 1.2) : 0, 2_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        vin.transform = tf
        vin.expectsMediaDataInRealTime = false
        guard writer.canAdd(vin) else { throw Convert.err("无法写入视频") }
        writer.add(vin)

        var ain: AVAssetWriterInput?
        var aout: AVAssetReaderTrackOutput?
        if let at = audioTrack {
            let pass = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)
            if writer.canAdd(pass) {
                writer.add(pass)
                ain = pass
                aout = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
            } else {
                let pcm: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                                          AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                let aac: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000]
                let enc = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
                if writer.canAdd(enc) {
                    writer.add(enc)
                    ain = enc
                    aout = AVAssetReaderTrackOutput(track: at, outputSettings: pcm)
                }
            }
            if let o = aout, reader.canAdd(o) { reader.add(o) } else { aout = nil; ain = nil }
        }

        guard reader.startReading() else { throw Convert.err("无法读取视频：" + (reader.error?.localizedDescription ?? "")) }
        guard writer.startWriting() else { throw Convert.err("无法写入视频：" + (writer.error?.localizedDescription ?? "")) }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        var lastReported = 0.0   // 只在视频写入队列里读写；进度变化不到 1% 不回调，避免刷爆主线程
        group.enter()
        vin.requestMediaDataWhenReady(on: DispatchQueue(label: "osvia.wm.video")) {
            while vin.isReadyForMoreMediaData {
                if cancel.on { vin.markAsFinished(); group.leave(); return }
                guard let sb = vout.copyNextSampleBuffer() else { vin.markAsFinished(); group.leave(); return }
                if let pb = CMSampleBufferGetImageBuffer(sb) {
                    CVPixelBufferLockBaseAddress(pb, [])
                    if let addr = CVPixelBufferGetBaseAddress(pb) {
                        apply(addr.assumingMemoryBound(to: UInt8.self), stride: CVPixelBufferGetBytesPerRow(pb),
                              width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb), rects: rects, smart: false, bgra: true)
                    }
                    CVPixelBufferUnlockBaseAddress(pb, [])
                }
                if !vin.append(sb) { vin.markAsFinished(); group.leave(); return }
                let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                if pts.isFinite {
                    let p = min(1, max(0, pts / total))
                    if p - lastReported >= 0.01 { lastReported = p; progress(p) }
                }
            }
        }
        if let ain, let aout {
            group.enter()
            ain.requestMediaDataWhenReady(on: DispatchQueue(label: "osvia.wm.audio")) {
                while ain.isReadyForMoreMediaData {
                    if cancel.on { ain.markAsFinished(); group.leave(); return }
                    guard let sb = aout.copyNextSampleBuffer() else { ain.markAsFinished(); group.leave(); return }
                    if !ain.append(sb) { ain.markAsFinished(); group.leave(); return }
                }
            }
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }
        if cancel.on {
            writer.cancelWriting()
            reader.cancelReading()
            try? FileManager.default.removeItem(at: dst)
            throw Convert.err("已取消")
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: dst)
            throw Convert.err("读取视频失败：" + (reader.error?.localizedDescription ?? ""))
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw Convert.err("导出失败：" + (writer.error?.localizedDescription ?? "未知错误")) }
        progress(1)
        return dst
    }

    // 预览帧：视频取指定时间的一帧（已按方向旋正），图片取本身
    static func preview(_ src: URL, at t: Double = 0) async -> UIImage? {
        if Convert.vidExt.contains(src.pathExtension.lowercased()) {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: src))
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 1600, height: 1600)
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
            guard let (cg, _) = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { return nil }
            return UIImage(cgImage: cg)
        }
        guard let cg = OCR.cg(src, maxPixel: 2000) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: 选区画布：在图上拖出矩形，点虚线框把识别到的文字块加入选区
struct RegionCanvas: View {
    let image: UIImage
    @Binding var regions: [CGRect]
    var hints: [CGRect] = []
    var onHint: (CGRect) -> Void = { _ in }
    @State private var drag: CGRect?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { v in drag = Self.norm(v.startLocation, v.location, g.size) }
                                    .onEnded { v in
                                        let r = Self.norm(v.startLocation, v.location, g.size)
                                        drag = nil
                                        if r.width > 0.01 && r.height > 0.01 && regions.count < 6 { regions.append(r) }
                                    }
                            )
                        ForEach(Array(hints.enumerated()), id: \.offset) { _, r in
                            Rectangle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .foregroundStyle(Color.yellow)
                                .background(Color.yellow.opacity(0.12))
                                .frame(width: r.width * g.size.width, height: r.height * g.size.height)
                                .offset(x: r.minX * g.size.width, y: r.minY * g.size.height)
                                .contentShape(Rectangle())
                                .onTapGesture { onHint(r) }
                        }
                        ForEach(Array(regions.enumerated()), id: \.offset) { i, r in
                            Rectangle()
                                .fill(Color.red.opacity(0.28))
                                .overlay(Rectangle().stroke(Color.red, lineWidth: 1.5))
                                .frame(width: r.width * g.size.width, height: r.height * g.size.height)
                                .offset(x: r.minX * g.size.width, y: r.minY * g.size.height)
                                .allowsHitTesting(false)
                        }
                        if let d = drag {
                            Rectangle()
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .frame(width: d.width * g.size.width, height: d.height * g.size.height)
                                .offset(x: d.minX * g.size.width, y: d.minY * g.size.height)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func norm(_ a: CGPoint, _ b: CGPoint, _ size: CGSize) -> CGRect {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let x0 = min(max(min(a.x, b.x) / w, 0), 1)
        let x1 = min(max(max(a.x, b.x) / w, 0), 1)
        let y0 = min(max(min(a.y, b.y) / h, 0), 1)
        let y1 = min(max(max(a.y, b.y) / h, 0), 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

// MARK: 去水印页面
struct WatermarkView: View {
    let video: Bool
    let initial: URL?
    @State private var src: URL?
    @State private var frame: UIImage?
    @State private var regions: [CGRect] = []
    @State private var hints: [CGRect] = []
    @State private var smart = false
    @State private var time = 0.0
    @State private var duration = 0.0
    @State private var busy = false
    @State private var progress = 0.0
    @State private var err = ""
    @State private var result: URL?
    @State private var preview: URL?
    @State private var showPhotos = false
    @State private var showFile = false
    @State private var items: [PhotosPickerItem] = []
    @State private var loading = false
    @State private var cancel = Delogo.Cancel()

    init(video: Bool = false, initial: URL? = nil) {
        self.video = video
        self.initial = initial
    }

    private var isVideo: Bool { src.map { Convert.vidExt.contains($0.pathExtension.lowercased()) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if src == nil { picker } else { editor }
                if !err.isEmpty { Label(err, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red) }
                if let r = result { resultCard(r) }
                tips
            }
            .padding(16)
        }
        .background(Brand.page)
        .navigationTitle(video ? "视频去水印" : "图片去水印")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task {
            if let u = initial, src == nil { await setSource(u) }
        }
        .photosPicker(isPresented: $showPhotos, selection: $items, maxSelectionCount: 1, matching: video ? PHPickerFilter.videos : PHPickerFilter.images)
        .onChange(of: items) { _, v in
            guard let it = v.first else { return }
            items = []
            Task { await load(it) }
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: video ? [UTType.movie] : [UTType.image]) { r in
            guard let u = try? r.get() else { return }
            let res = Files.importFile(u)
            if let c = res.url { Task { await setSource(c) } } else { err = res.error ?? "文件读取失败" }
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            Image(systemName: video ? "film" : "photo.badge.checkmark").fontSz(40).foregroundStyle(Brand.mint).padding(.top, 20)
            Text(video ? "选一个带水印的视频" : "选一张带水印的图片").font(.headline).foregroundStyle(Brand.ink)
            Button { showPhotos = true } label: { Label("从相册选择", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button { showFile = true } label: { Label("从「文件」App 选择", systemImage: "folder").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            if loading { ProgressView("正在读取…") }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var editor: some View {
        if let f = frame {
            Text("在画面上拖动，框出水印的位置（可框多处）。黄色虚线框是识别到的文字，点一下就加入选区。")
                .font(.footnote).foregroundStyle(Brand.sub)
            RegionCanvas(image: f, regions: $regions, hints: hints) { r in
                regions.append(r.insetBy(dx: -0.004, dy: -0.004).intersection(CGRect(x: 0, y: 0, width: 1, height: 1)))
                hints.removeAll { $0 == r }
            }
            if isVideo && duration > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(Brand.sub)
                    Slider(value: $time, in: 0...max(duration - 0.1, 0.1), onEditingChanged: { editing in
                        if !editing { Task { await refreshFrame() } }
                    })
                }
            }
            HStack(spacing: 10) {
                Button { findText() } label: { Label("识别文字水印", systemImage: "text.viewfinder").font(.subheadline) }
                    .buttonStyle(.bordered)
                Button { regions = []; hints = [] } label: { Label("清除选区", systemImage: "arrow.uturn.backward").font(.subheadline) }
                    .buttonStyle(.bordered)
                    .disabled(regions.isEmpty && hints.isEmpty)
                Spacer(minLength: 0)
                Button { src = nil; frame = nil; regions = []; hints = []; result = nil } label: { Text("换一个").font(.subheadline) }
            }
            if !isVideo {
                Toggle(isOn: $smart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保留背景纹理").font(.subheadline)
                        Text("适合半透明文字水印；整块图标请关闭").font(.caption).foregroundStyle(Brand.sub)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
            }
            if busy {
                VStack(alignment: .leading, spacing: 8) {
                    if isVideo { ProgressView(value: progress) { Text("处理中 \(Int(progress * 100))%").font(.subheadline) } }
                    else { ProgressView("处理中…") }
                    if isVideo { Button("取消", role: .destructive) { cancel.on = true } }
                }
            } else {
                Button { run() } label: { Label("去除水印", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(regions.isEmpty)
            }
        } else {
            ProgressView("正在读取…").frame(maxWidth: .infinity)
        }
    }

    private func resultCard(_ r: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("处理结果").font(.headline)
            FileCard(url: r, preview: $preview)
            HStack(spacing: 10) {
                Button { PhotoSave.save(r) } label: { Label("存入相册", systemImage: "photo.badge.plus") }.buttonStyle(.bordered)
                ShareLink(item: r) { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明").font(.subheadline.weight(.semibold))
            Text("在手机上本地处理，不上传。适合纯色、渐变、虚化背景上位置固定的水印；背景纹理复杂时会留下模糊痕迹。位置会移动的水印暂不支持。请只处理自己拥有版权的内容。")
                .font(.footnote).foregroundStyle(Brand.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        let r = await MediaPick.load(item)
        if let u = r.url { await setSource(u) } else { err = r.error }
    }

    private func setSource(_ u: URL) async {
        err = ""
        result = nil
        regions = []
        hints = []
        time = 0
        src = u
        frame = nil
        if Convert.vidExt.contains(u.pathExtension.lowercased()) {
            duration = (try? await AVURLAsset(url: u).load(.duration).seconds) ?? 0
        } else {
            duration = 0
        }
        frame = await Delogo.preview(u, at: 0)
        if frame == nil { err = "无法读取这个文件"; src = nil }
    }

    private func refreshFrame() async {
        guard let u = src, isVideo else { return }
        if let f = await Delogo.preview(u, at: time) { frame = f }
        hints = []
    }

    private func findText() {
        guard let cg = frame?.cgImage else { return }
        Task {
            let lines = await Task.detached(priority: .userInitiated) { OCR.lines(cg) }.value
            let found = lines.map { $0.box }.filter { $0.width < 0.9 }
            hints = found
            if found.isEmpty { err = "没有识别到文字，请手动框选"; return }
            err = ""
        }
    }

    private func run() {
        guard let u = src, !regions.isEmpty else { return }
        busy = true
        err = ""
        result = nil
        progress = 0
        cancel = Delogo.Cancel()
        let rs = regions
        let sm = smart
        let c = cancel
        let vid = isVideo
        Task {
            do {
                if vid {
                    result = try await Delogo.video(u, regions: rs, progress: { p in DispatchQueue.main.async { progress = p } }, cancel: c)
                } else {
                    result = try await Task.detached(priority: .userInitiated) { try Delogo.image(u, regions: rs, smart: sm) }.value
                }
            } catch {
                err = error.localizedDescription
            }
            busy = false
        }
    }
}
