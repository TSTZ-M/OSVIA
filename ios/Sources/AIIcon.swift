import SwiftUI
import UIKit

// MARK: 各 AI 的应用图标
// 运行时从各自的来源加载并缓存到本机：App Store 上的应用图标 → 官网触摸图标 → 站点图标。加载前和失败时显示原来的占位图标。
struct AppLookup {
    let term: String
    let key: String
    let country: String
}

@MainActor
final class IconStore {
    static let shared = IconStore()

    // App Store 搜索词、用来核对结果名称的关键字、所在商店区域
    static let lookup: [String: AppLookup] = [
        "chatgpt": AppLookup(term: "ChatGPT", key: "chatgpt", country: "us"),
        "claude": AppLookup(term: "Claude by Anthropic", key: "claude", country: "us"),
        "gemini": AppLookup(term: "Google Gemini", key: "gemini", country: "us"),
        "grok": AppLookup(term: "Grok", key: "grok", country: "us"),
        "copilot": AppLookup(term: "Microsoft Copilot", key: "copilot", country: "us"),
        "perplexity": AppLookup(term: "Perplexity", key: "perplexity", country: "us"),
        "meta": AppLookup(term: "Meta AI", key: "meta ai", country: "us"),
        "mistral": AppLookup(term: "Le Chat Mistral AI", key: "le chat", country: "us"),
        "poe": AppLookup(term: "Poe", key: "poe", country: "us"),
        "you": AppLookup(term: "You.com", key: "you.com", country: "us"),
        "character": AppLookup(term: "Character AI", key: "character", country: "us"),
        "genspark": AppLookup(term: "Genspark", key: "genspark", country: "us"),
        "deepseek": AppLookup(term: "DeepSeek", key: "deepseek", country: "cn"),
        "kimi": AppLookup(term: "Kimi", key: "kimi", country: "cn"),
        "doubao": AppLookup(term: "豆包", key: "豆包", country: "cn"),
        "qwen": AppLookup(term: "通义", key: "通义", country: "cn"),
        "yuanbao": AppLookup(term: "腾讯元宝", key: "元宝", country: "cn"),
        "yiyan": AppLookup(term: "文心一言", key: "文心", country: "cn"),
        "glm": AppLookup(term: "智谱清言", key: "智谱", country: "cn"),
        "spark": AppLookup(term: "讯飞星火", key: "星火", country: "cn"),
        "minimax": AppLookup(term: "海螺AI", key: "海螺", country: "cn"),
        "step": AppLookup(term: "跃问", key: "跃问", country: "cn"),
        "baichuan": AppLookup(term: "百小应", key: "百小应", country: "cn"),
        "tiangong": AppLookup(term: "天工AI", key: "天工", country: "cn"),
        "clova": AppLookup(term: "CLOVA X", key: "clova", country: "kr"),
        "alice": AppLookup(term: "Алиса", key: "алис", country: "ru"),
        "giga": AppLookup(term: "GigaChat", key: "gigachat", country: "ru"),
        "manus": AppLookup(term: "Manus", key: "manus", country: "us"),
        "cue": AppLookup(term: "Cue personal agent", key: "cue", country: "us"),
        "comet": AppLookup(term: "Comet Perplexity", key: "comet", country: "us"),
        "lovable": AppLookup(term: "Lovable", key: "lovable", country: "us"),
        "replit": AppLookup(term: "Replit", key: "replit", country: "us"),
        "cursor": AppLookup(term: "Cursor", key: "cursor", country: "us"),
        "lindy": AppLookup(term: "Lindy", key: "lindy", country: "us"),
        "phind": AppLookup(term: "Phind", key: "phind", country: "us"),
        "felo": AppLookup(term: "Felo", key: "felo", country: "us"),
        "brave": AppLookup(term: "Brave Private Web Browser", key: "brave", country: "us"),
        "monica": AppLookup(term: "Monica AI", key: "monica", country: "us"),
        "replika": AppLookup(term: "Replika", key: "replika", country: "us"),
        "talkie": AppLookup(term: "Talkie AI", key: "talkie", country: "us"),
        "venice": AppLookup(term: "Venice AI", key: "venice", country: "us"),
        "lumo": AppLookup(term: "Lumo Proton", key: "lumo", country: "us"),
        "notebooklm": AppLookup(term: "NotebookLM", key: "notebooklm", country: "us"),
        "kagi": AppLookup(term: "Kagi Search", key: "kagi", country: "us"),
        "coze": AppLookup(term: "扣子", key: "扣子", country: "cn"),
        "metaso": AppLookup(term: "秘塔AI搜索", key: "秘塔", country: "cn"),
        "baiduai": AppLookup(term: "百度", key: "百度", country: "cn"),
        "quark": AppLookup(term: "夸克", key: "夸克", country: "cn"),
        "nano": AppLookup(term: "纳米AI", key: "纳米", country: "cn"),
        "xingye": AppLookup(term: "星野", key: "星野", country: "cn"),
        "hunyuan": AppLookup(term: "腾讯混元", key: "混元", country: "cn"),
        "sensechat": AppLookup(term: "商量", key: "商量", country: "cn"),
        "xiaoyi": AppLookup(term: "小艺", key: "小艺", country: "cn"),
        "skywork": AppLookup(term: "天工超级智能体", key: "天工", country: "cn")
    ]

    private let mem = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var failed = Set<String>()
    private let dir: URL

    private init() {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("aiicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
    }

    func image(for s: AIService) async -> UIImage? {
        let key = s.id as NSString
        if let i = mem.object(forKey: key) { return i }
        let file = dir.appendingPathComponent(s.id + ".png")
        if let d = try? Data(contentsOf: file), let i = UIImage(data: d) {
            mem.setObject(i, forKey: key)
            return i
        }
        if failed.contains(s.id) { return nil }
        if let t = inflight[s.id] { return await t.value }
        let t = Task { await self.fetch(s) }
        inflight[s.id] = t
        let img = await t.value
        inflight[s.id] = nil
        if let img {
            mem.setObject(img, forKey: key)
            if let png = img.pngData() { try? png.write(to: file) }
        } else {
            failed.insert(s.id)
        }
        return img
    }

    private func fetch(_ s: AIService) async -> UIImage? {
        if let l = Self.lookup[s.id], let u = await storeIcon(l), let img = await download(u, minPx: 100) { return img }
        guard let host = URL(string: s.web)?.host else { return nil }
        let urls = ["https://\(host)/apple-touch-icon.png", "https://www.google.com/s2/favicons?domain=\(host)&sz=128", "https://\(host)/favicon.ico"]
        for u in urls {
            if let url = URL(string: u), let img = await download(url, minPx: 40) { return img }
        }
        return nil
    }

    // 在 App Store 里按名字找到这个 AI 的应用，取它的图标地址
    private func storeIcon(_ l: AppLookup) async -> URL? {
        let term = l.term.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? l.term
        guard let u = URL(string: "https://itunes.apple.com/search?term=\(term)&entity=software&country=\(l.country)&limit=6") else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 8
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let results = j["results"] as? [[String: Any]] else { return nil }
        let key = l.key.lowercased()
        for item in results {
            let name = ((item["trackName"] as? String) ?? "").lowercased()
            guard name.contains(key) else { continue }
            if let s = (item["artworkUrl512"] as? String) ?? (item["artworkUrl100"] as? String), let url = URL(string: s) { return url }
        }
        return nil
    }

    private func download(_ url: URL, minPx: CGFloat) async -> UIImage? {
        var r = URLRequest(url: url)
        r.timeoutInterval = 8
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              d.count > 200, d.count < 3_000_000, let img = UIImage(data: d) else { return nil }
        return img.size.width * img.scale >= minPx ? img : nil
    }
}

struct AIIcon: View {
    let service: AIService
    var size: CGFloat = 32
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            if let img {
                Color.white
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Brand.mint.opacity(0.14)
                Image(systemName: service.icon)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Brand.mint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .task(id: service.id) {
            let i = await IconStore.shared.image(for: service)
            withAnimation(.easeOut(duration: 0.2)) { img = i }
        }
    }
}
