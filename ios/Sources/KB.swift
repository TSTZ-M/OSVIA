import Foundation
import NaturalLanguage
import Accelerate
import PDFKit

final class KB {
    static let shared = KB()
    private let emb = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
    var hasVector: Bool { emb != nil }
    static let textExt: Set<String> = ["txt", "md", "csv", "tsv", "json", "html", "htm", "xml", "log", "yaml", "yml", "swift", "js", "py", "rtf"]

    private func vec(_ s: String) -> [Float]? {
        guard let v = emb?.vector(for: s), !v.isEmpty else { return nil }
        let f = v.map { Float($0) }
        var n: Float = 0
        vDSP_svesq(f, 1, &n, vDSP_Length(f.count))
        let m = max(n.squareRoot(), 1e-6)
        return f.map { $0 / m }
    }

    private func grams(_ s: String) -> Set<String> {
        let c = Array(s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation })
        guard c.count > 1 else { return Set(c.map { String($0) }) }
        return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
    }

    private func chunks(_ t: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for line in t.components(separatedBy: .newlines) {
            let p = line.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if cur.count + p.count > 300 {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
            }
            var s = Substring(p)
            while s.count > 300 {
                out.append(String(s.prefix(300)))
                s = s.dropFirst(300)
            }
            cur += (cur.isEmpty ? "" : "\n") + String(s)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    func add(_ name: String, _ text: String) {
        let id = DB.shared.run("INSERT INTO doc(name,ts) VALUES(?,?)", [name, Date().timeIntervalSince1970])
        for c in chunks(text) {
            let b: Data? = vec(c).map { v in v.withUnsafeBytes { Data($0) } }
            DB.shared.run("INSERT INTO chunk(doc,text,vec) VALUES(?,?,?)", [id, c, b])
        }
    }

    func upsert(_ name: String, _ text: String) {
        DB.shared.run("DELETE FROM chunk WHERE doc IN (SELECT id FROM doc WHERE name=?)", [name])
        DB.shared.run("DELETE FROM doc WHERE name=?", [name])
        add(name, text)
    }

    func delete(_ id: Int) {
        DB.shared.run("DELETE FROM chunk WHERE doc=?", [id])
        DB.shared.run("DELETE FROM doc WHERE id=?", [id])
    }

    func docs() -> [Row] {
        DB.shared.rows("SELECT d.id AS id, d.name AS name, d.ts AS ts, (SELECT COUNT(*) FROM chunk c WHERE c.doc=d.id) AS n FROM doc d ORDER BY d.ts DESC")
    }

    func text(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        if Office.exts.contains(ext) { return Office.text(of: url) }
        guard Self.textExt.contains(ext), let d = try? Data(contentsOf: url) else { return "" }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        var s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: gb) ?? ""
        if ext == "html" || ext == "htm" {
            s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return s
    }

    @discardableResult
    func ingest(_ url: URL) -> Int {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let t = text(of: url)
        if !t.isEmpty { upsert(url.lastPathComponent, t) }
        return t.count
    }

    func search(_ q: String, k: Int = 3) -> [String] {
        let rows = DB.shared.rows("SELECT text, vec FROM chunk")
        guard !rows.isEmpty else { return [] }
        let qg = grams(q)
        let qv = vec(q)
        var scored: [(Double, String)] = []
        for r in rows {
            let t = r.s("text")
            var sc = 0.0
            if !qg.isEmpty { sc = Double(qg.intersection(grams(t)).count) / Double(qg.count) }
            if let qv, let d = r["vec"] as? Data, d.count == qv.count * 4 {
                let v = d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                var dot: Float = 0
                vDSP_dotpr(qv, 1, v, 1, &dot, vDSP_Length(v.count))
                sc = sc * 0.6 + Double(max(dot, 0)) * 0.4
            }
            if sc > 0.12 { scored.append((sc, t)) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(k).map { $0.1 }
    }

    // 只看词面重合的检索：用于「每个问题都自动先查一遍知识库」。
    // 句向量在不相关的句子之间也有不低的相似度，自动带入会塞进一堆无关内容，所以这里不用它。
    private static let stopChars: Set<Character> = ["的", "了", "是", "我", "你", "他", "她", "它", "吗", "呢", "吧", "啊", "么", "和", "与", "在", "有", "不", "这", "那", "个", "请", "帮", "要", "想", "能", "会", "可", "以", "什", "怎", "样", "一", "下"]

    func relevant(_ q: String, k: Int = 3, minScore: Double = 0.25) -> [String] {
        let qg = grams(q).filter { g in !g.contains { Self.stopChars.contains($0) } }
        guard !qg.isEmpty else { return [] }
        let rows = DB.shared.rows("SELECT text FROM chunk")
        guard !rows.isEmpty else { return [] }
        var scored: [(Double, String)] = []
        for r in rows {
            let t = r.s("text")
            let hit = qg.intersection(grams(t)).count
            if hit == 0 { continue }
            let sc = Double(hit) / Double(qg.count)
            if sc >= minScore { scored.append((sc, t)) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(k).map { $0.1 }
    }

    // 附在问题后面的知识库资料；没有明显相关的内容就返回空串
    func context(_ q: String) -> String {
        let hits = relevant(q)
        if hits.isEmpty { return "" }
        return "\n\n（用户知识库里可能相关的资料，相关才使用，不相关就忽略：\n" + hits.map { "- " + String($0.prefix(300)) }.joined(separator: "\n") + "）"
    }
}
