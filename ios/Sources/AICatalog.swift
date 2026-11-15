import SwiftUI

// MARK: 全球主流 AI 的入口：一键跳转 + 把提示词带过去
// 带预填参数的（?q=）直接把提示词送进输入框；没有的，提示词也已复制到剪贴板，到那边粘贴发送即可。
struct AIService: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String      // 对话 / 智能体 / 搜索 / 国内 / 陪伴 / 其他地区
    let icon: String
    let web: String
    var prefill = ""       // 含 {q} 的网址模板；没有就留空
    var tags = ""          // 搜索用的别名与关键词（小写，空格分隔）

    init(_ id: String, _ name: String, _ group: String, _ icon: String, _ web: String, prefill: String = "", tags: String = "") {
        self.id = id
        self.name = name
        self.group = group
        self.icon = icon
        self.web = web
        self.prefill = prefill
        self.tags = tags
    }

    func matches(_ q: String) -> Bool {
        let k = q.trimmingCharacters(in: .whitespaces).lowercased()
        if k.isEmpty { return true }
        return (name + " " + id + " " + tags).lowercased().contains(k)
    }
}

@MainActor
enum Jump {
    static let groups = ["全部", "对话", "智能体", "搜索", "国内", "陪伴", "其他地区"]

    static let services: [AIService] = [
        // 对话助手
        AIService("chatgpt", "ChatGPT", "对话", "bubble.left.and.text.bubble.right", "https://chatgpt.com/", prefill: "https://chatgpt.com/?q={q}", tags: "openai gpt"),
        AIService("claude", "Claude", "对话", "sparkle", "https://claude.ai/new", prefill: "https://claude.ai/new?q={q}", tags: "anthropic"),
        AIService("gemini", "Gemini", "对话", "star.circle", "https://gemini.google.com/app", tags: "google bard"),
        AIService("grok", "Grok", "对话", "bolt", "https://grok.com/", prefill: "https://grok.com/?q={q}", tags: "xai x.ai twitter"),
        AIService("copilot", "Microsoft Copilot", "对话", "airplane", "https://copilot.microsoft.com/", prefill: "https://copilot.microsoft.com/?q={q}", tags: "bing microsoft"),
        AIService("meta", "Meta AI", "对话", "infinity", "https://www.meta.ai/", tags: "llama facebook"),
        AIService("mistral", "Le Chat (Mistral)", "对话", "wind", "https://chat.mistral.ai/chat", prefill: "https://chat.mistral.ai/chat?q={q}", tags: "mistral lechat"),
        AIService("poe", "Poe", "对话", "p.circle", "https://poe.com/", tags: "bot bots quora 机器人"),
        AIService("hugging", "HuggingChat", "对话", "face.smiling", "https://huggingface.co/chat/", prefill: "https://huggingface.co/chat/?q={q}", tags: "hugging face 开源"),
        AIService("duck", "Duck.ai", "对话", "bird", "https://duck.ai/", tags: "duckduckgo 隐私"),
        AIService("venice", "Venice", "对话", "theatermasks", "https://venice.ai/chat", tags: "隐私 无审查"),
        AIService("cohere", "Cohere Coral", "对话", "c.circle", "https://coral.cohere.com/", tags: "command"),
        AIService("lumo", "Lumo (Proton)", "对话", "lock.shield", "https://lumo.proton.me/", tags: "proton 隐私"),
        AIService("qwenchat", "Qwen Chat", "对话", "q.circle", "https://chat.qwen.ai/", tags: "通义 alibaba 阿里"),
        AIService("zai", "Z.ai (GLM)", "对话", "z.circle", "https://chat.z.ai/", tags: "智谱 glm zhipu"),
        AIService("aistudio", "Google AI Studio", "对话", "wand.and.stars", "https://aistudio.google.com/", tags: "gemini 开发者"),
        AIService("notebooklm", "NotebookLM", "对话", "book.closed", "https://notebooklm.google.com/", tags: "google 笔记 资料"),
        AIService("monica", "Monica", "对话", "m.circle", "https://monica.im/", tags: "助手 插件"),
        AIService("sider", "Sider", "对话", "s.circle", "https://sider.ai/", tags: "侧边栏 插件"),
        // 智能体
        AIService("manus", "Manus", "智能体", "hand.raised", "https://manus.im/", tags: "agent 智能体 meta 通用"),
        AIService("cue", "Cue", "智能体", "c.square", "https://cue.im/", tags: "agent 智能体 manus 个人助理"),
        AIService("genspark", "Genspark", "智能体", "sparkles", "https://www.genspark.ai/", prefill: "https://www.genspark.ai/search?query={q}", tags: "agent super 超级智能体"),
        AIService("comet", "Perplexity Comet", "智能体", "safari", "https://www.perplexity.ai/comet", tags: "agent browser 浏览器"),
        AIService("devin", "Devin", "智能体", "hammer", "https://devin.ai/", tags: "agent 编程 cognition"),
        AIService("codex", "ChatGPT Codex", "智能体", "chevron.left.forwardslash.chevron.right", "https://chatgpt.com/codex", tags: "openai agent 编程"),
        AIService("claudecode", "Claude Code", "智能体", "terminal", "https://claude.ai/code", tags: "anthropic agent 编程"),
        AIService("jules", "Jules", "智能体", "j.circle", "https://jules.google/", tags: "google agent 编程"),
        AIService("lovable", "Lovable", "智能体", "heart", "https://lovable.dev/", tags: "agent 建站 应用"),
        AIService("bolt", "Bolt", "智能体", "bolt.horizontal", "https://bolt.new/", tags: "agent 建站 应用"),
        AIService("v0", "v0", "智能体", "v.circle", "https://v0.app/", tags: "vercel agent 界面"),
        AIService("replit", "Replit Agent", "智能体", "r.circle", "https://replit.com/", tags: "agent 编程 应用"),
        AIService("cursor", "Cursor", "智能体", "cursorarrow.rays", "https://cursor.com/", tags: "agent 编程 编辑器"),
        AIService("flowith", "Flowith", "智能体", "scribble", "https://flowith.io/", tags: "agent 画布"),
        AIService("skywork", "Skywork 天工超级智能体", "智能体", "building.columns", "https://skywork.ai/", tags: "agent 昆仑万维 文档 幻灯片"),
        AIService("minimaxagent", "MiniMax Agent", "智能体", "waveform.badge.magnifyingglass", "https://agent.minimax.io/", tags: "agent 智能体 海螺"),
        AIService("lindy", "Lindy", "智能体", "l.circle", "https://www.lindy.ai/", tags: "agent 邮件 日程 助理"),
        AIService("dify", "Dify", "智能体", "point.3.connected.trianglepath.dotted", "https://cloud.dify.ai/", tags: "agent 工作流 搭建"),
        AIService("cozespace", "扣子空间 Coze Space", "智能体", "square.grid.2x2", "https://space.coze.cn/", tags: "agent 智能体 字节 bot"),
        AIService("coze", "扣子 Coze", "智能体", "cube", "https://www.coze.cn/", tags: "bot bots 机器人 智能体 字节 agent"),
        AIService("yuanqi", "腾讯元器", "智能体", "y.square", "https://yuanqi.tencent.com/", tags: "bot 智能体 腾讯 agent"),
        // AI 搜索
        AIService("perplexity", "Perplexity", "搜索", "magnifyingglass.circle", "https://www.perplexity.ai/", prefill: "https://www.perplexity.ai/search?q={q}", tags: "search 搜索"),
        AIService("you", "You.com", "搜索", "y.circle", "https://you.com/", prefill: "https://you.com/search?q={q}&tbm=youchat", tags: "search"),
        AIService("googleai", "Google AI 模式", "搜索", "g.circle.fill", "https://www.google.com/search?udm=50", prefill: "https://www.google.com/search?udm=50&q={q}", tags: "google ai mode search 搜索"),
        AIService("phind", "Phind", "搜索", "p.square", "https://www.phind.com/", prefill: "https://www.phind.com/search?q={q}", tags: "编程 开发者 search"),
        AIService("felo", "Felo", "搜索", "f.circle", "https://felo.ai/", prefill: "https://felo.ai/search?q={q}", tags: "search 多语言"),
        AIService("brave", "Brave Leo / Ask", "搜索", "shield", "https://search.brave.com/ask", prefill: "https://search.brave.com/ask?q={q}", tags: "brave leo search 隐私"),
        AIService("kagi", "Kagi Assistant", "搜索", "k.circle", "https://kagi.com/assistant", tags: "search 付费"),
        AIService("metaso", "秘塔 AI 搜索", "搜索", "m.square", "https://metaso.cn/", prefill: "https://metaso.cn/?q={q}", tags: "search 搜索"),
        AIService("baiduai", "百度 AI 搜索", "搜索", "b.circle", "https://chat.baidu.com/", prefill: "https://chat.baidu.com/search?word={q}", tags: "search 搜索 文心"),
        AIService("quark", "夸克 AI", "搜索", "q.square", "https://www.quark.cn/", tags: "search 搜索 阿里"),
        AIService("nano", "纳米 AI 搜索", "搜索", "n.square", "https://www.n.cn/", tags: "search 搜索 360"),
        // 国内
        AIService("deepseek", "DeepSeek 深度求索", "国内", "water.waves", "https://chat.deepseek.com/"),
        AIService("kimi", "Kimi", "国内", "moon.stars", "https://www.kimi.com/", tags: "月之暗面 moonshot"),
        AIService("doubao", "豆包", "国内", "bubbles.and.sparkles", "https://www.doubao.com/chat/", tags: "字节 bytedance"),
        AIService("qwen", "通义千问 Qwen", "国内", "cloud", "https://tongyi.aliyun.com/qianwen/", tags: "阿里 千问 qianwen"),
        AIService("yuanbao", "腾讯元宝", "国内", "diamond", "https://yuanbao.tencent.com/", tags: "腾讯 混元 hunyuan"),
        AIService("yiyan", "文心一言", "国内", "paintbrush", "https://yiyan.baidu.com/", tags: "百度 ernie"),
        AIService("glm", "智谱清言", "国内", "brain", "https://chatglm.cn/", tags: "chatglm zhipu glm"),
        AIService("spark", "讯飞星火", "国内", "flame", "https://xinghuo.xfyun.cn/", tags: "科大讯飞 iflytek"),
        AIService("minimax", "MiniMax 海螺", "国内", "waveform", "https://chat.minimaxi.com/", tags: "hailuo"),
        AIService("step", "阶跃 跃问", "国内", "stairs", "https://yuewen.cn/", tags: "stepfun 阶跃星辰"),
        AIService("baichuan", "百小应", "国内", "leaf", "https://ying.baichuan-ai.com/", tags: "百川"),
        AIService("tiangong", "天工 AI", "国内", "building.columns", "https://www.tiangong.cn/", tags: "昆仑万维"),
        AIService("sensechat", "商量 SenseChat", "国内", "eye", "https://chat.sensetime.com/", tags: "商汤 sensetime"),
        AIService("hunyuan", "腾讯混元", "国内", "circle.hexagongrid", "https://hunyuan.tencent.com/", tags: "腾讯 hunyuan"),
        AIService("xiaoyi", "华为小艺", "国内", "mic", "https://xiaoyi.huawei.com/", tags: "华为 huawei"),
        // 陪伴 / 角色
        AIService("pi", "Pi", "陪伴", "heart.circle", "https://pi.ai/", tags: "inflection 陪伴"),
        AIService("character", "Character.AI", "陪伴", "person.2.circle", "https://character.ai/", tags: "角色 bot 机器人"),
        AIService("replika", "Replika", "陪伴", "person.crop.circle.badge.checkmark", "https://replika.com/", tags: "陪伴 伙伴"),
        AIService("talkie", "Talkie", "陪伴", "t.circle", "https://www.talkie-ai.com/", tags: "角色 陪伴 minimax"),
        AIService("xingye", "星野", "陪伴", "star", "https://www.xingyeai.com/", tags: "角色 陪伴 minimax"),
        // 其他地区
        AIService("clova", "Naver CLOVA X", "其他地区", "n.circle", "https://clova-x.naver.com/", tags: "韩国 naver"),
        AIService("alice", "Yandex Alice", "其他地区", "a.circle", "https://alice.yandex.ru/", tags: "俄罗斯 yandex алиса"),
        AIService("giga", "GigaChat", "其他地区", "g.circle", "https://giga.chat/", tags: "俄罗斯 sber"),
        AIService("sarvam", "Sarvam", "其他地区", "s.square", "https://www.sarvam.ai/", tags: "印度 india"),
        AIService("krutrim", "Krutrim", "其他地区", "k.square", "https://www.olakrutrim.com/", tags: "印度 india ola"),
        AIService("alephalpha", "Aleph Alpha", "其他地区", "a.square", "https://aleph-alpha.com/", tags: "德国 欧洲")
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
