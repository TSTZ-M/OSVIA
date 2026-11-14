import SwiftUI

// MARK: 全球主流 AI 的入口：一键跳转 + 把提示词带过去
// 带预填参数的（?q=）直接把提示词送进输入框；没有的，提示词也已复制到剪贴板，到那边粘贴发送即可。
struct AIService: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String      // 国际 / 中国 / 其他地区
    let icon: String
    let web: String
    var prefill = ""       // 含 {q} 的网址模板；没有就留空

    init(_ id: String, _ name: String, _ group: String, _ icon: String, _ web: String, prefill: String = "") {
        self.id = id
        self.name = name
        self.group = group
        self.icon = icon
        self.web = web
        self.prefill = prefill
    }
}

@MainActor
enum Jump {
    static let groups = ["全部", "国际", "中国", "其他地区"]

    static let services: [AIService] = [
        AIService("chatgpt", "ChatGPT", "国际", "bubble.left.and.text.bubble.right", "https://chatgpt.com/", prefill: "https://chatgpt.com/?q={q}"),
        AIService("claude", "Claude", "国际", "sparkle", "https://claude.ai/new", prefill: "https://claude.ai/new?q={q}"),
        AIService("gemini", "Gemini", "国际", "star.circle", "https://gemini.google.com/app"),
        AIService("grok", "Grok", "国际", "bolt", "https://grok.com/", prefill: "https://grok.com/?q={q}"),
        AIService("copilot", "Microsoft Copilot", "国际", "airplane", "https://copilot.microsoft.com/", prefill: "https://copilot.microsoft.com/?q={q}"),
        AIService("perplexity", "Perplexity", "国际", "magnifyingglass.circle", "https://www.perplexity.ai/", prefill: "https://www.perplexity.ai/search?q={q}"),
        AIService("meta", "Meta AI", "国际", "infinity", "https://www.meta.ai/"),
        AIService("mistral", "Le Chat (Mistral)", "国际", "wind", "https://chat.mistral.ai/chat", prefill: "https://chat.mistral.ai/chat?q={q}"),
        AIService("poe", "Poe", "国际", "p.circle", "https://poe.com/"),
        AIService("you", "You.com", "国际", "y.circle", "https://you.com/", prefill: "https://you.com/search?q={q}&tbm=youchat"),
        AIService("hugging", "HuggingChat", "国际", "face.smiling", "https://huggingface.co/chat/", prefill: "https://huggingface.co/chat/?q={q}"),
        AIService("pi", "Pi", "国际", "heart.circle", "https://pi.ai/"),
        AIService("character", "Character.AI", "国际", "person.2.circle", "https://character.ai/"),
        AIService("duck", "Duck.ai", "国际", "bird", "https://duck.ai/"),
        AIService("genspark", "Genspark", "国际", "sparkles", "https://www.genspark.ai/"),
        AIService("deepseek", "DeepSeek 深度求索", "中国", "water.waves", "https://chat.deepseek.com/"),
        AIService("kimi", "Kimi", "中国", "moon.stars", "https://www.kimi.com/"),
        AIService("doubao", "豆包", "中国", "bubbles.and.sparkles", "https://www.doubao.com/chat/"),
        AIService("qwen", "通义千问 Qwen", "中国", "cloud", "https://tongyi.aliyun.com/qianwen/"),
        AIService("yuanbao", "腾讯元宝", "中国", "diamond", "https://yuanbao.tencent.com/"),
        AIService("yiyan", "文心一言", "中国", "paintbrush", "https://yiyan.baidu.com/"),
        AIService("glm", "智谱清言", "中国", "brain", "https://chatglm.cn/"),
        AIService("spark", "讯飞星火", "中国", "flame", "https://xinghuo.xfyun.cn/"),
        AIService("minimax", "MiniMax 海螺", "中国", "waveform", "https://chat.minimaxi.com/"),
        AIService("step", "阶跃 跃问", "中国", "stairs", "https://yuewen.cn/"),
        AIService("baichuan", "百小应", "中国", "leaf", "https://ying.baichuan-ai.com/"),
        AIService("tiangong", "天工 AI", "中国", "building.columns", "https://www.tiangong.cn/"),
        AIService("clova", "Naver CLOVA X", "其他地区", "n.circle", "https://clova-x.naver.com/"),
        AIService("alice", "Yandex Alice", "其他地区", "a.circle", "https://alice.yandex.ru/"),
        AIService("giga", "GigaChat", "其他地区", "g.circle", "https://giga.chat/")
    ]

    // 只保留不会被当成查询分隔的字符，其余（含中文）全部百分号编码
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    // 能预填就返回带提示词的网址（提示词太长时不预填，避免被服务器拒绝）
    static func prefilledURL(_ s: AIService, prompt: String) -> URL? {
        guard !s.prefill.isEmpty, let enc = prompt.addingPercentEncoding(withAllowedCharacters: unreserved), enc.count <= 6000 else { return nil }
        return URL(string: s.prefill.replacingOccurrences(of: "{q}", with: enc))
    }

    static func url(for s: AIService, prompt: String) -> URL? {
        prefilledURL(s, prompt: prompt) ?? URL(string: s.web)
    }

    // 提示词一律先复制到剪贴板（没有预填参数、或提示词太长的 AI，到那边粘贴即可），再打开。返回是否已预填
    @discardableResult
    static func open(_ s: AIService, prompt: String) -> Bool {
        UIPasteboard.general.string = prompt
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let pre = prefilledURL(s, prompt: prompt)
        guard let u = pre ?? URL(string: s.web) else { return false }
        UIApplication.shared.open(u)
        return pre != nil
    }

    // 任意网址（支持「全球每一个 AI」：只要是网页就能跳转）
    @discardableResult
    static func openCustom(_ raw: String, prompt: String) -> Bool {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), u.host != nil else { return false }
        UIPasteboard.general.string = prompt
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.open(u)
        return true
    }
}
