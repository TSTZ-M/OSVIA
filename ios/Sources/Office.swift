import Foundation
import Compression
import UIKit

// MARK: 最小 ZIP 读写。docx / xlsx / pptx / odt 都是 ZIP 包。
// 读：中央目录 + 系统压缩库解 deflate；写：不压缩（stored），Word / Excel 都能直接打开。
enum Zip {
    struct Entry {
        let name: String
        let method: Int
        let csize: Int
        let usize: Int
        let offset: Int
    }

    final class Archive {
        let bytes: [UInt8]
        let list: [Entry]

        init?(url: URL) {
            guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count > 22 else { return nil }
            bytes = [UInt8](d)
            list = Zip.entries(bytes)
            if list.isEmpty { return nil }
        }

        func read(_ name: String) -> Data? {
            guard let e = list.first(where: { $0.name == name }) else { return nil }
            return Zip.data(bytes, e)
        }

        func names(prefix: String, suffix: String) -> [String] {
            list.map(\.name).filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }
    private static func u32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | (Int(b[i + 1]) << 8) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24)
    }

    static func entries(_ b: [UInt8]) -> [Entry] {
        guard b.count > 22 else { return [] }
        let low = max(0, b.count - 65_557)
        var i = b.count - 22
        while i >= low {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 0x05, b[i + 3] == 0x06 { break }
            i -= 1
        }
        guard i >= low else { return [] }
        let count = u16(b, i + 10)
        var p = u32(b, i + 16)
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x02014b50 else { break }
            let method = u16(b, p + 10)
            let cs = u32(b, p + 20)
            let us = u32(b, p + 24)
            let nl = u16(b, p + 28)
            let el = u16(b, p + 30)
            let cl = u16(b, p + 32)
            let off = u32(b, p + 42)
            guard p + 46 + nl <= b.count else { break }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nl)], as: UTF8.self)
            out.append(Entry(name: name, method: method, csize: cs, usize: us, offset: off))
            p += 46 + nl + el + cl
        }
        return out
    }

    static func data(_ b: [UInt8], _ e: Entry) -> Data? {
        let o = e.offset
        guard o + 30 <= b.count, u32(b, o) == 0x04034b50 else { return nil }
        let start = o + 30 + u16(b, o + 26) + u16(b, o + 28)
        guard start + e.csize <= b.count else { return nil }
        if e.csize == 0 { return Data() }
        if e.method == 0 { return Data(b[start..<(start + e.csize)]) }
        guard e.method == 8, e.usize > 0, e.usize < 200_000_000 else { return nil }
        let comp = Array(b[start..<(start + e.csize)])
        var dst = [UInt8](repeating: 0, count: e.usize)
        let cap = e.usize
        let n = comp.withUnsafeBufferPointer { s -> Int in
            dst.withUnsafeMutableBufferPointer { d -> Int in
                compression_decode_buffer(d.baseAddress!, cap, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        return Data(dst[0..<n])
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in d { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    static func write(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in files {
            let nm = Data(name.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)
            let offset = UInt32(out.count)
            out.append(le32(0x04034b50))
            out.append(le16(20))
            out.append(le16(0x0800))
            out.append(le16(0))
            out.append(le16(0))
            out.append(le16(0x21))
            out.append(le32(crc))
            out.append(le32(size))
            out.append(le32(size))
            out.append(le16(nm.count))
            out.append(le16(0))
            out.append(nm)
            out.append(data)

            central.append(le32(0x02014b50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0x21))
            central.append(le32(crc))
            central.append(le32(size))
            central.append(le32(size))
            central.append(le16(nm.count))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nm)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(files.count))
        out.append(le16(files.count))
        out.append(le32(UInt32(central.count)))
        out.append(le32(cdOffset))
        out.append(le16(0))
        return out
    }
}

// MARK: Office 文档：读文字 / 表格，写 docx / xlsx / rtf
enum Office {
    static let exts: Set<String> = ["docx", "xlsx", "pptx", "odt", "ods", "odp", "rtf"]

    // MARK: 读
    static func text(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "rtf" { return rtf(url) }
        guard let a = Zip.Archive(url: url) else { return "" }
        switch ext {
        case "docx": return docx(a)
        case "pptx": return pptx(a)
        case "xlsx":
            return sheets(a).map { s in
                (sheets(a).count > 1 ? "【\(s.name)】\n" : "") + Convert.csvOut(s.rows, "\t")
            }.joined(separator: "\n\n")
        case "odt", "ods", "odp": return odf(a)
        default: return ""
        }
    }

    static func sheets(of url: URL) -> [(name: String, rows: [[String]])] {
        guard url.pathExtension.lowercased() == "xlsx", let a = Zip.Archive(url: url) else { return [] }
        return sheets(a)
    }

    private static func rtf(_ url: URL) -> String {
        guard let d = try? Data(contentsOf: url),
              let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else { return "" }
        return a.string
    }

    private static func xml(_ a: Zip.Archive, _ name: String) -> String {
        guard let d = a.read(name) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    private static func strip(_ s: String) -> String {
        Web.decodeEntities(s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
    }

    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func docx(_ a: Zip.Archive) -> String {
        var s = xml(a, "word/document.xml")
        guard !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: "<w:instrText[\\s\\S]*?</w:instrText>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<w:delText[\\s\\S]*?</w:delText>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<w:tab\\s*/>", with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: "<w:(br|cr)\\b[^>]*/>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</w:p>\\s*</w:tc>", with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: "</w:tr>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</w:p>", with: "\n", options: .regularExpression)
        return tidy(strip(s))
    }

    private static func pptx(_ a: Zip.Archive) -> String {
        let names = a.names(prefix: "ppt/slides/slide", suffix: ".xml").sorted { x, y in
            func n(_ s: String) -> Int { Int(s.filter(\.isNumber)) ?? 0 }
            return n(x) < n(y)
        }
        var out: [String] = []
        for (i, n) in names.enumerated() {
            var s = xml(a, n)
            s = s.replacingOccurrences(of: "</a:p>", with: "\n", options: .regularExpression)
            let t = tidy(strip(s))
            if !t.isEmpty { out.append("—— 第 \(i + 1) 页 ——\n" + t) }
        }
        return out.joined(separator: "\n\n")
    }

    private static func odf(_ a: Zip.Archive) -> String {
        var s = xml(a, "content.xml")
        s = s.replacingOccurrences(of: "<text:tab\\s*/>", with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: "<text:line-break\\s*/>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</table:table-cell>", with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: "</table:table-row>|</text:p>|</text:h>", with: "\n", options: .regularExpression)
        return tidy(strip(s))
    }

    private static func all(_ s: String, _ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        }
    }

    private static func attr(_ tag: String, _ name: String) -> String {
        all(tag, "\\b" + name + "=\"([^\"]*)\"").first?[1] ?? ""
    }

    private static func colIndex(_ ref: String) -> Int {
        var n = 0
        for c in ref.uppercased() {
            guard let v = c.asciiValue, v >= 65, v <= 90 else { break }
            n = n * 26 + Int(v - 64)
        }
        return max(n - 1, 0)
    }

    private static func sheets(_ a: Zip.Archive) -> [(name: String, rows: [[String]])] {
        // 共享字符串
        var shared: [String] = []
        let ss = xml(a, "xl/sharedStrings.xml").replacingOccurrences(of: "<rPh[\\s\\S]*?</rPh>", with: "", options: .regularExpression)
        for m in all(ss, "<si\\b[^>]*>([\\s\\S]*?)</si>") {
            shared.append(all(m[1], "<t\\b[^>]*>([\\s\\S]*?)</t>").map { Web.decodeEntities($0[1]) }.joined())
        }
        // 工作表名称与文件的对应
        let wb = xml(a, "xl/workbook.xml")
        let rels = xml(a, "xl/_rels/workbook.xml.rels")
        var target: [String: String] = [:]
        for m in all(rels, "<Relationship\\b[^>]*>") {
            target[attr(m[0], "Id")] = attr(m[0], "Target")
        }
        var list: [(String, String)] = []
        for m in all(wb, "<sheet\\b[^>]*>") {
            let rid = attr(m[0], "r:id")
            var t = target[rid] ?? ""
            if t.hasPrefix("/") { t.removeFirst() } else if !t.isEmpty { t = "xl/" + t }
            list.append((Web.decodeEntities(attr(m[0], "name")), t))
        }
        if list.isEmpty {
            list = a.names(prefix: "xl/worksheets/sheet", suffix: ".xml").sorted().enumerated().map { ("Sheet\($0.offset + 1)", $0.element) }
        }
        var out: [(name: String, rows: [[String]])] = []
        for (name, path) in list {
            let sx = xml(a, path)
            if sx.isEmpty { continue }
            var rows: [[String]] = []
            for r in all(sx, "<row\\b[^>]*>([\\s\\S]*?)</row>") {
                var row: [String] = []
                for c in all(r[1], "<c\\b([^>]*?)(?:/>|>([\\s\\S]*?)</c>)") {
                    let attrs = c[1]
                    let body = c[2]
                    let idx = colIndex(attr(attrs, "r"))
                    let type = attr(attrs, "t")
                    var v = all(body, "<v>([\\s\\S]*?)</v>").first?[1] ?? ""
                    switch type {
                    case "s": v = Int(v).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
                    case "inlineStr": v = all(body, "<t\\b[^>]*>([\\s\\S]*?)</t>").map { Web.decodeEntities($0[1]) }.joined()
                    case "b": v = v == "1" ? "TRUE" : "FALSE"
                    default: v = Web.decodeEntities(v)
                    }
                    while row.count < idx { row.append("") }
                    if row.count == idx { row.append(v) } else { row[idx] = v }
                }
                rows.append(row)
            }
            while let l = rows.last, l.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
            if !rows.isEmpty { out.append((name, rows)) }
        }
        return out
    }

    // MARK: 写
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let docRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    // 简单排版：# / ## / ### 标题加粗放大，- 开头变成圆点
    static func docx(_ text: String) -> Data {
        var body = ""
        for raw in text.components(separatedBy: "\n") {
            var line = raw
            var size = 0
            var bold = false
            if line.hasPrefix("### ") { line.removeFirst(4); size = 26; bold = true }
            else if line.hasPrefix("## ") { line.removeFirst(3); size = 30; bold = true }
            else if line.hasPrefix("# ") { line.removeFirst(2); size = 36; bold = true }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
            var rpr = ""
            if bold || size > 0 {
                rpr = "<w:rPr>" + (bold ? "<w:b/>" : "") + (size > 0 ? "<w:sz w:val=\"\(size)\"/>" : "") + "</w:rPr>"
            }
            body += "<w:p><w:r>\(rpr)<w:t xml:space=\"preserve\">\(esc(line))</w:t></w:r></w:p>"
        }
        let sect = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr>"
        let document = head + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>" + body + sect + "</w:body></w:document>"
        let types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"
        let rels = head + "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"rId1\" Type=\"\(docRel)/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
        return Zip.write([
            ("[Content_Types].xml", Data(types.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("word/document.xml", Data(document.utf8)),
        ])
    }

    private static func colName(_ i: Int) -> String {
        var n = i + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(UInt8(65 + r))) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func xlsx(_ rows: [[String]], sheet: String = "Sheet1") -> Data {
        var data = ""
        for (ri, row) in rows.enumerated() {
            data += "<row r=\"\(ri + 1)\">"
            for (ci, cell) in row.enumerated() {
                let ref = colName(ci) + String(ri + 1)
                let isNum = Double(cell) != nil && cell.count < 16 && !(cell.hasPrefix("0") && cell.count > 1 && !cell.hasPrefix("0."))
                if isNum {
                    data += "<c r=\"\(ref)\"><v>\(cell)</v></c>"
                } else if !cell.isEmpty {
                    data += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(cell))</t></is></c>"
                }
            }
            data += "</row>"
        }
        let name = esc(String(sheet.prefix(31)))
        let ws = head + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>" + data + "</sheetData></worksheet>"
        let wb = head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"\(docRel)\"><sheets><sheet name=\"\(name)\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
        let wbRels = head + "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"rId1\" Type=\"\(docRel)/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
        let rels = head + "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"rId1\" Type=\"\(docRel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        let types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"
        return Zip.write([
            ("[Content_Types].xml", Data(types.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("xl/workbook.xml", Data(wb.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(wbRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(ws.utf8)),
        ])
    }

    static func rtfData(_ text: String) -> Data? {
        let a = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12)])
        return try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

// MARK: 极简 Markdown → HTML（转 PDF、网页、Word 时用）
enum MDHTML {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inline(_ raw: String) -> String {
        var s = esc(raw)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<b>$1</b>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![*\\w])\\*([^*\\n]+)\\*(?!\\w)", with: "<i>$1</i>", options: .regularExpression)
        s = s.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)", with: "<img alt=\"$1\" src=\"$2\" style=\"max-width:100%\">", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return s
    }

    static func html(_ md: String) -> String {
        var out: [String] = []
        var list = ""      // "ul" / "ol" / ""
        var code = false
        var table: [String] = []
        var para: [String] = []

        func flushPara() {
            if !para.isEmpty { out.append("<p>" + para.map(inline).joined(separator: "<br>") + "</p>"); para = [] }
        }
        func closeList() {
            if !list.isEmpty { out.append("</\(list)>"); list = "" }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let rows = Convert.mdRows(table.joined(separator: "\n"))
            if !rows.isEmpty {
                var t = "<table>"
                for (i, r) in rows.enumerated() {
                    let tag = i == 0 ? "th" : "td"
                    t += "<tr>" + r.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>"
                }
                out.append(t + "</table>")
            }
            table = []
        }

        for line in md.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                flushPara(); closeList(); flushTable()
                out.append(code ? "</code></pre>" : "<pre><code>")
                code.toggle()
                continue
            }
            if code { out.append(esc(line)); continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { flushPara(); closeList(); table.append(t); continue }
            flushTable()
            if t.isEmpty { flushPara(); closeList(); continue }
            if let m = t.range(of: "^#{1,6} ", options: .regularExpression) {
                flushPara(); closeList()
                let n = t[m].count - 1
                out.append("<h\(n)>" + inline(String(t[m.upperBound...])) + "</h\(n)>")
            } else if t.range(of: "^(-{3,}|\\*{3,})$", options: .regularExpression) != nil {
                flushPara(); closeList(); out.append("<hr>")
            } else if t.hasPrefix("> ") {
                flushPara(); closeList(); out.append("<blockquote>" + inline(String(t.dropFirst(2))) + "</blockquote>")
            } else if let m = t.range(of: "^[-*+] ", options: .regularExpression) {
                flushPara()
                if list != "ul" { closeList(); out.append("<ul>"); list = "ul" }
                out.append("<li>" + inline(String(t[m.upperBound...])) + "</li>")
            } else if let m = t.range(of: "^\\d+[.)] ", options: .regularExpression) {
                flushPara()
                if list != "ol" { closeList(); out.append("<ol>"); list = "ol" }
                out.append("<li>" + inline(String(t[m.upperBound...])) + "</li>")
            } else {
                closeList(); para.append(t)
            }
        }
        flushPara(); closeList(); flushTable()
        if code { out.append("</code></pre>") }
        return page(out.joined(separator: "\n"))
    }

    static func page(_ body: String) -> String {
        "<meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><style>body{font:14px/1.7 -apple-system,'PingFang SC',sans-serif;color:#222;margin:0}h1,h2,h3{line-height:1.3}pre{background:#f4f4f5;padding:10px;border-radius:6px;white-space:pre-wrap}code{background:#f4f4f5;padding:1px 4px;border-radius:4px}blockquote{margin:8px 0;padding:2px 12px;border-left:3px solid #ccc;color:#555}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px 8px}img{max-width:100%}</style>" + body
    }

    // 纯文本放进网页里，保留换行
    static func pre(_ text: String) -> String {
        page("<div style='white-space:pre-wrap'>" + esc(text) + "</div>")
    }
}
