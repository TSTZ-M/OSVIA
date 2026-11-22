import Foundation
import UIKit
import PDFKit
import Vision

// MARK: 表格识别：iOS 26 文档识别接口，把图片、PDF 里的表格直接变成 Excel / CSV（全程本机）
enum TableOCR {
    struct Found {
        let label: String      // 工作表名，如「p2 表1」
        let rows: [[String]]
    }

    struct Output {
        let files: [URL]
        let found: [Found]
        let pages: Int
        let merged: Bool       // 同列数的表格是否合并成了一张（跨页长表常见）
    }

    static let maxPages = 30

    // MARK: 识别
    static func run(_ files: [URL], format: String) async throws -> Output {
        guard !files.isEmpty else { throw Convert.err("没有选择文件") }
        var found: [Found] = []
        var pages = 0
        var firstErr: Error?
        let multi = files.count > 1

        for (fi, u) in files.enumerated() {
            try Task.checkCancellation()
            let prefix = multi ? "\(fi + 1)-" : ""
            if u.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: u) else {
                    firstErr = firstErr ?? Convert.err("无法打开 \(u.lastPathComponent)，可能不是有效的 PDF")
                    continue
                }
                if doc.isLocked { firstErr = firstErr ?? Convert.err("\(u.lastPathComponent) 有密码，请先用「PDF 工具」解除密码"); continue }
                for i in 0..<min(doc.pageCount, maxPages) {
                    try Task.checkCancellation()
                    guard let p = doc.page(at: i) else { continue }
                    let cg: CGImage? = autoreleasepool { render(p) }
                    guard let cg else { continue }
                    pages += 1
                    do {
                        let tables = try await detect(cg)
                        for (ti, rows) in tables.enumerated() {
                            found.append(Found(label: "\(prefix)p\(i + 1) 表\(ti + 1)", rows: rows))
                        }
                    } catch {
                        firstErr = firstErr ?? error
                    }
                }
            } else {
                do {
                    let cg = try ImageOps.readCG(u, maxPixel: 4096)
                    pages += 1
                    let tables = try await detect(cg)
                    for (ti, rows) in tables.enumerated() {
                        found.append(Found(label: "\(prefix)表\(ti + 1)", rows: rows))
                    }
                } catch {
                    firstErr = firstErr ?? error
                }
            }
        }

        guard !found.isEmpty else {
            if let e = firstErr, pages == 0 { throw e }
            throw Convert.err("没有识别到表格。请换一张更清晰、表格线完整、正对拍摄的图片")
        }

        let base = ToolFS.base(files[0]) + "-表格"
        let merged = mergedRows(found)
        var outs: [URL] = []

        if format == "csv" {
            if found.count == 1 || merged != nil {
                let dst = ToolFS.out(base, "csv")
                try csv(merged ?? found[0].rows).write(to: dst, atomically: true, encoding: .utf8)
                outs.append(dst)
            } else {
                for (i, f) in found.prefix(40).enumerated() {
                    let dst = ToolFS.out("\(base)\(i + 1)", "csv")
                    try csv(f.rows).write(to: dst, atomically: true, encoding: .utf8)
                    outs.append(dst)
                }
            }
        } else {
            var sheets = found.map { (name: $0.label, rows: $0.rows) }
            if let m = merged { sheets.insert((name: "合并", rows: m), at: 0) }
            let dst = ToolFS.out(base, "xlsx")
            try Office.xlsx(sheets: sheets).write(to: dst)
            outs.append(dst)
        }
        return Output(files: outs, found: found, pages: pages, merged: merged != nil)
    }

    // MARK: 单张图的识别
    private static func detect(_ cg: CGImage) async throws -> [[[String]]] {
        let observations = try await RecognizeDocumentsRequest().perform(on: cg)
        var out: [[[String]]] = []
        for o in observations {
            for t in o.document.tables {
                let raw: [[String]] = t.rows.map { row in
                    row.map { cell in clean(cell.content.text.transcript) }
                }
                let rows = normalize(raw)
                let cols = rows.first?.count ?? 0
                if rows.count * cols >= 2 { out.append(rows) }
            }
        }
        return out
    }

    private static func clean(_ s: String) -> String {
        s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // 去掉全空的行和列，各行补齐到同样的列数
    static func normalize(_ raw: [[String]]) -> [[String]] {
        var rows = raw.filter { r in r.contains { !$0.isEmpty } }
        let w = rows.map { $0.count }.max() ?? 0
        guard w > 0 else { return [] }
        rows = rows.map { $0 + Array(repeating: "", count: w - $0.count) }
        let keep = (0..<w).filter { c in rows.contains { !$0[c].isEmpty } }
        return rows.map { r in keep.map { r[$0] } }
    }

    // 所有表格列数相同 → 合并成一张，后面各页重复出现的表头自动去掉
    static func mergedRows(_ found: [Found]) -> [[String]]? {
        guard found.count > 1, let w = found.first?.rows.first?.count, found.allSatisfy({ $0.rows.first?.count == w }) else { return nil }
        var all = found[0].rows
        let head = all.first
        for f in found.dropFirst() {
            all += (f.rows.first == head) ? Array(f.rows.dropFirst()) : f.rows
        }
        return all
    }

    // UTF-8 带 BOM，Excel 直接打开中文不乱码
    private static func csv(_ rows: [[String]]) -> String {
        "\u{FEFF}" + Convert.csvOut(rows, ",")
    }

    private static func render(_ p: PDFPage) -> CGImage? {
        var sz = p.bounds(for: .mediaBox).size
        if p.rotation % 180 != 0 { sz = CGSize(width: sz.height, height: sz.width) }
        guard sz.width > 0, sz.height > 0 else { return nil }
        // 长边约 2400 像素：小字也能识别，又不会撑爆内存
        let k = min(3, 2400 / max(sz.width, sz.height))
        let target = CGSize(width: max(1, (sz.width * k).rounded()), height: max(1, (sz.height * k).rounded()))
        return p.thumbnail(of: target, for: .mediaBox).cgImage
    }

    // MARK: 给助理 / 界面看的简短预览（Markdown）
    static func preview(_ found: [Found], rowsPerTable: Int = 8, tables: Int = 3) -> String {
        found.prefix(tables).map { f in
            let rows = Array(f.rows.prefix(rowsPerTable)).map { r in r.map { $0.replacingOccurrences(of: "|", with: "｜") } }
            let more = f.rows.count > rowsPerTable ? "\n…共 \(f.rows.count) 行" : ""
            return "【\(f.label)】\(f.rows.count) 行 × \(f.rows.first?.count ?? 0) 列\n" + Convert.mdOut(rows) + more
        }.joined(separator: "\n\n")
    }
}
