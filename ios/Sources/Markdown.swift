import SwiftUI
import UIKit

// 轻量 Markdown 渲染：标题、列表（含缩进与任务列表）、引用、表格、代码块（可复制）、粗体斜体链接行内样式，引用编号 [1] 着色。
// 流式输出时每次重新解析，未闭合的代码块、尚未写完的表格也能正常显示；每个块单独比较，只有变化的块才重绘。
enum MDBlock: Equatable {
    case para(String)
    case heading(Int, String)
    case bullet(String, String, Int)
    case quote(String)
    case code(String, String)
    case table([[String]])
    case rule
}

enum MD {
    static func parse(_ s: String) -> [MDBlock] {
        var out: [MDBlock] = []
        var para: [String] = []
        var inCode = false
        var lang = ""
        var code: [String] = []
        func flush() {
            if !para.isEmpty {
                out.append(.para(para.joined(separator: "\n")))
                para = []
            }
        }
        let lines = s.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let tr = line.trimmingCharacters(in: .whitespaces)
            i += 1
            if inCode {
                if tr.hasPrefix("```") {
                    out.append(.code(lang, code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    code.append(line)
                }
                continue
            }
            if tr.hasPrefix("```") {
                flush()
                inCode = true
                lang = String(tr.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if tr.isEmpty { flush(); continue }
            // 表格：表头行 + 分隔行（|---|---|）+ 若干数据行
            if tr.hasPrefix("|"), i < lines.count, isSeparator(lines[i]) {
                flush()
                var rows: [[String]] = [cells(tr)]
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[j]))
                    j += 1
                }
                out.append(.table(rows))
                i = j
                continue
            }
            if let h = heading(tr) { flush(); out.append(h); continue }
            if tr == "---" || tr == "***" || tr == "___" { flush(); out.append(.rule); continue }
            if tr.hasPrefix(">") {
                flush()
                out.append(.quote(String(tr.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let b = bullet(tr, indent: indentLevel(line)) { flush(); out.append(b); continue }
            para.append(line)
        }
        if inCode { out.append(.code(lang, code.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func indentLevel(_ line: String) -> Int {
        var n = 0
        for c in line {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return min(n / 2, 3)
    }

    private static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func heading(_ t: String) -> MDBlock? {
        var n = 0
        for c in t {
            if c == "#" { n += 1 } else { break }
        }
        guard n >= 1, n <= 6, t.dropFirst(n).first == " " else { return nil }
        return .heading(n, String(t.dropFirst(n + 1)))
    }

    private static func bullet(_ t: String, indent: Int) -> MDBlock? {
        for p in ["- ", "* ", "• ", "+ "] where t.hasPrefix(p) {
            var rest = String(t.dropFirst(p.count))
            if rest.hasPrefix("[ ] ") { return .bullet("☐", String(rest.dropFirst(4)), indent) }
            if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
                rest = String(rest.dropFirst(4))
                return .bullet("☑", rest, indent)
            }
            return .bullet("•", rest, indent)
        }
        if let r = t.range(of: "^\\d+[.)、]\\s+", options: .regularExpression) {
            let marker = t[r].trimmingCharacters(in: .whitespaces)
            return .bullet(marker, String(t[r.upperBound...]), indent)
        }
        return nil
    }

    static func attr(_ s: String) -> AttributedString {
        let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: s, options: o)) ?? AttributedString(s)
        // 引用编号 [1] [2] 着色，和下面的「来源」芯片对应
        let plain = String(a.characters)
        if plain.contains("[") {
            for n in 1...30 where plain.contains("[\(n)]") {
                let token = "[\(n)]"
                var from = a.startIndex
                while from < a.endIndex, let r = a[from...].range(of: token) {
                    a[r].foregroundColor = Brand.mint
                    from = r.upperBound
                }
            }
        }
        return a
    }
}

struct MarkdownText: View {
    let text: String

    var body: some View {
        let blocks = MD.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { i in MDBlockView(block: blocks[i]).equatable() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct MDBlockView: View, Equatable {
    let block: MDBlock
    @State private var copied = false

    static func == (a: MDBlockView, b: MDBlockView) -> Bool { a.block == b.block }

    var body: some View {
        switch block {
        case .para(let s):
            Text(MD.attr(s)).font(Brand.body).lineSpacing(6).foregroundStyle(Brand.ink)
        case .heading(let n, let s):
            Text(MD.attr(s))
                .font(.system(size: n == 1 ? 23 : (n == 2 ? 20 : 17.5), weight: .semibold))
                .foregroundStyle(Brand.ink)
                .padding(.top, 6)
        case .bullet(let m, let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(m)
                    .font(Brand.body.weight(m == "•" ? .heavy : .regular))
                    .foregroundStyle(m == "•" || m == "☐" || m == "☑" ? Brand.mint : Brand.sub)
                    .frame(minWidth: 14, alignment: .trailing)
                Text(MD.attr(s)).font(Brand.body).lineSpacing(6).foregroundStyle(Brand.ink)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let s):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Brand.mint.opacity(0.6)).frame(width: 3)
                Text(MD.attr(s)).font(Brand.body).lineSpacing(5).foregroundStyle(Brand.sub)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            MDTable(rows: rows)
        case .code(let lang, let src):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(lang.isEmpty ? "代码" : lang).font(.caption).foregroundStyle(Brand.sub)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = src
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                    }
                    .foregroundStyle(Brand.sub)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(src).font(.system(size: 14, design: .monospaced)).foregroundStyle(Brand.ink).padding(12)
                }
            }
            .background(Brand.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .rule:
            Divider()
        }
    }
}

// 表格：横向可滚动，首行加粗，行间细线
struct MDTable: View {
    let rows: [[String]]

    private var cols: Int { rows.map { $0.count }.max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { c in
                            Text(MD.attr(c < rows[r].count ? rows[r][c] : ""))
                                .font(.system(size: 14.5, weight: r == 0 ? .semibold : .regular))
                                .foregroundStyle(Brand.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(minWidth: 72, alignment: .leading)
                        }
                    }
                    .background(r == 0 ? Brand.codeBg : Color.clear)
                    Divider()
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
