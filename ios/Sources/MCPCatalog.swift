import SwiftUI

// MARK: 热门 MCP 连接器目录：全部是官方远程服务（Streamable HTTP），按用途分类
struct MCPApp: Identifiable {
    enum Auth { case none, oauth, key }

    let name: String          // 添加后的服务名
    let url: String
    let about: String
    let domain: String        // 取品牌图标用
    var symbol = "puzzlepiece.extension"
    var auth: Auth = .oauth
    var cat = "dev"
    var hot = false
    var label = ""            // 图标下方显示的短名；空则用 name
    var keyHint = ""          // 需要密钥时的获取说明
    var keyPage = ""          // 获取密钥的网页
    var keyQuery = ""         // 密钥放在地址的哪个参数里（空表示作为 Bearer 令牌）

    var id: String { url }
    var shortName: String { label.isEmpty ? name : label }
}

enum MCPCatalog {
    static let categories: [(id: String, title: String, icon: String)] = [
        ("hot", "热门", "flame"),
        ("dev", "开发", "chevron.left.forwardslash.chevron.right"),
        ("work", "办公协作", "square.grid.2x2"),
        ("design", "设计建站", "paintpalette"),
        ("data", "搜索与数据", "magnifyingglass"),
        ("biz", "支付与客户", "creditcard"),
        ("more", "自动化与地图", "bolt")
    ]

    static let all: [MCPApp] = [
        // 开发
        MCPApp(name: "GitHub", url: "https://api.githubcopilot.com/mcp/", about: "仓库、Issue、PR、代码搜索", domain: "github.com", symbol: "chevron.left.forwardslash.chevron.right", cat: "dev", hot: true),
        MCPApp(name: "DeepWiki", url: "https://mcp.deepwiki.com/mcp", about: "读懂任意 GitHub 仓库：结构、文档、问答", domain: "deepwiki.com", auth: .none, cat: "dev", hot: true),
        MCPApp(name: "Context7", url: "https://mcp.context7.com/mcp", about: "查询各种开发库的最新文档", domain: "context7.com", auth: .none, cat: "dev", hot: true),
        MCPApp(name: "Microsoft Learn", url: "https://learn.microsoft.com/api/mcp", about: "检索微软官方技术文档与示例代码", domain: "microsoft.com", auth: .none, cat: "dev", label: "MS Learn"),
        MCPApp(name: "Cloudflare Docs", url: "https://docs.mcp.cloudflare.com/mcp", about: "检索 Cloudflare 官方文档", domain: "cloudflare.com", auth: .none, cat: "dev", label: "CF 文档"),
        MCPApp(name: "Cloudflare", url: "https://mcp.cloudflare.com/mcp", about: "管理 Workers、D1、KV、R2 等 Cloudflare 资源", domain: "cloudflare.com", cat: "dev", hot: true),
        MCPApp(name: "Sentry", url: "https://mcp.sentry.dev/mcp", about: "查看线上错误、堆栈和问题趋势", domain: "sentry.io", cat: "dev", hot: true),
        MCPApp(name: "Vercel", url: "https://mcp.vercel.com", about: "项目、部署与日志", domain: "vercel.com", cat: "dev", hot: true),
        MCPApp(name: "Netlify", url: "https://netlify-mcp.netlify.app/mcp", about: "站点与部署管理", domain: "netlify.com", cat: "dev"),
        MCPApp(name: "Supabase", url: "https://mcp.supabase.com/mcp", about: "数据库、存储与项目管理", domain: "supabase.com", cat: "dev", hot: true),
        MCPApp(name: "Neon", url: "https://mcp.neon.tech/mcp", about: "Postgres 数据库与分支", domain: "neon.tech", cat: "dev"),
        MCPApp(name: "Prisma", url: "https://mcp.prisma.io/mcp", about: "Prisma Postgres 数据库管理", domain: "prisma.io", cat: "dev"),
        MCPApp(name: "Hugging Face", url: "https://huggingface.co/mcp", about: "搜索模型、数据集、论文和 Spaces", domain: "huggingface.co", auth: .none, cat: "dev", hot: true, label: "HF"),
        MCPApp(name: "GitMCP", url: "https://gitmcp.io/docs", about: "读任意 GitHub 项目的文档（gitmcp.io/用户/仓库 可指定仓库）", domain: "gitmcp.io", auth: .none, cat: "dev"),
        MCPApp(name: "Astro Docs", url: "https://mcp.docs.astro.build/mcp", about: "检索 Astro 官方文档", domain: "astro.build", auth: .none, cat: "dev"),
        MCPApp(name: "AWS Knowledge", url: "https://knowledge-mcp.global.api.aws", about: "检索 AWS 官方文档与最佳实践", domain: "aws.amazon.com", auth: .none, cat: "dev", label: "AWS"),
        MCPApp(name: "Postman", url: "https://mcp.postman.com/mcp", about: "接口集合、请求与测试", domain: "postman.com", cat: "dev"),
        MCPApp(name: "Resend", url: "https://mcp.resend.com/mcp", about: "发送邮件、管理域名与联系人", domain: "resend.com", cat: "dev"),
        MCPApp(name: "PostHog", url: "https://mcp.posthog.com/mcp", about: "产品分析、事件与功能开关", domain: "posthog.com", cat: "dev"),

        // 办公协作
        MCPApp(name: "Notion", url: "https://mcp.notion.com/mcp", about: "搜索、读取、创建你的 Notion 页面和数据库", domain: "notion.so", cat: "work", hot: true),
        MCPApp(name: "Linear", url: "https://mcp.linear.app/mcp", about: "查看和创建 Linear 的任务、项目", domain: "linear.app", cat: "work", hot: true),
        MCPApp(name: "Slack", url: "https://mcp.slack.com/mcp", about: "搜索消息、读取频道、发送消息", domain: "slack.com", cat: "work", hot: true),
        MCPApp(name: "Atlassian（Jira / Confluence）", url: "https://mcp.atlassian.com/v2/mcp", about: "Jira 工单与 Confluence 文档", domain: "atlassian.com", cat: "work", label: "Atlassian"),
        MCPApp(name: "Asana", url: "https://mcp.asana.com/v2/mcp", about: "任务与项目管理", domain: "asana.com", cat: "work"),
        MCPApp(name: "Airtable", url: "https://mcp.airtable.com/mcp", about: "读写 Airtable 的表格与记录", domain: "airtable.com", cat: "work", hot: true),
        MCPApp(name: "monday.com", url: "https://mcp.monday.com/mcp", about: "看板、任务与进度", domain: "monday.com", cat: "work"),
        MCPApp(name: "ClickUp", url: "https://mcp.clickup.com/mcp", about: "任务、文档与团队协作", domain: "clickup.com", cat: "work"),
        MCPApp(name: "Todoist", url: "https://ai.todoist.net/mcp", about: "待办清单与项目", domain: "todoist.com", cat: "work"),
        MCPApp(name: "Box", url: "https://mcp.box.com", about: "搜索和读取 Box 里的文件", domain: "box.com", cat: "work"),
        MCPApp(name: "Miro", url: "https://mcp.miro.com", about: "白板与脑图", domain: "miro.com", cat: "work"),
        MCPApp(name: "Calendly", url: "https://mcp.calendly.com", about: "日程预约与可用时间", domain: "calendly.com", cat: "work"),
        MCPApp(name: "Fireflies", url: "https://api.fireflies.ai/mcp", about: "会议录音的转写与纪要", domain: "fireflies.ai", cat: "work"),

        // 设计建站
        MCPApp(name: "Figma", url: "https://mcp.figma.com/mcp", about: "读取设计稿、组件与变量", domain: "figma.com", cat: "design", hot: true),
        MCPApp(name: "Canva", url: "https://mcp.canva.com/mcp", about: "搜索、创建和编辑 Canva 设计", domain: "canva.com", cat: "design", hot: true),
        MCPApp(name: "Webflow", url: "https://mcp.webflow.com/mcp", about: "站点、页面与 CMS 内容", domain: "webflow.com", cat: "design"),
        MCPApp(name: "Wix", url: "https://mcp.wix.com/mcp", about: "Wix 站点与内容管理", domain: "wix.com", cat: "design"),

        // 搜索与数据
        MCPApp(name: "Exa", url: "https://mcp.exa.ai/mcp", about: "面向 AI 的网页搜索与内容抓取", domain: "exa.ai", auth: .none, cat: "data", hot: true),
        MCPApp(name: "Mixpanel", url: "https://mcp.mixpanel.com/mcp", about: "产品数据分析与漏斗", domain: "mixpanel.com", cat: "data"),
        MCPApp(name: "Amplitude", url: "https://mcp.amplitude.com/mcp", about: "用户行为分析", domain: "amplitude.com", cat: "data"),
        MCPApp(name: "Apify", url: "https://mcp.apify.com", about: "网页抓取与上千个现成的自动化爬虫", domain: "apify.com", auth: .key, cat: "data",
               keyHint: "在 Apify 控制台 → 设置 → 集成 里复制个人 API Token。", keyPage: "https://console.apify.com/settings/integrations"),

        // 支付与客户
        MCPApp(name: "Stripe", url: "https://mcp.stripe.com", about: "查询收款、客户和订阅", domain: "stripe.com", cat: "biz", hot: true),
        MCPApp(name: "PayPal", url: "https://mcp.paypal.com/mcp", about: "订单、发票与交易", domain: "paypal.com", cat: "biz"),
        MCPApp(name: "HubSpot", url: "https://mcp.hubspot.com", about: "客户与销售数据", domain: "hubspot.com", cat: "biz"),
        MCPApp(name: "Intercom", url: "https://mcp.intercom.com/mcp", about: "客服会话与用户资料", domain: "intercom.com", cat: "biz"),

        // 自动化与地图
        MCPApp(name: "Zapier", url: "https://mcp.zapier.com/api/mcp/mcp", about: "连接 7000+ 应用的自动化动作", domain: "zapier.com", auth: .key, cat: "more",
               keyHint: "打开 Zapier MCP 页面，新建服务器后复制 API 密钥。", keyPage: "https://mcp.zapier.com"),
        MCPApp(name: "高德地图", url: "https://mcp.amap.com/mcp", about: "地点搜索、路线规划、天气、地理编码", domain: "amap.com", symbol: "map", auth: .key, cat: "more", hot: true,
               keyHint: "在高德开放平台创建「Web 服务」类型的 Key，粘贴到这里。", keyPage: "https://console.amap.com/dev/key/app", keyQuery: "key")
    ]

    static func apps(in cat: String) -> [MCPApp] {
        cat == "hot" ? all.filter { $0.hot } : all.filter { $0.cat == cat }
    }

    static func find(url: String) -> MCPApp? { all.first { $0.url == url } }

    // 用户自己添加的服务：按地址里的注册域名取图标
    static func domain(forURL u: String) -> String {
        if let a = find(url: u) { return a.domain }
        guard let h = URL(string: u)?.host else { return "" }
        return SenderID.domain("x@" + h)
    }

    // 「Atlassian（Jira / Confluence）」→「Atlassian」
    static func short(_ name: String) -> String {
        if let a = all.first(where: { $0.name == name }) { return a.shortName }
        var n = name
        for sep in ["（", "(", " - ", " · "] { if let r = n.range(of: sep) { n = String(n[..<r.lowerBound]) } }
        return n.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: 品牌图标：取官网图标（本机缓存），取不到用彩色底 + 符号 / 首字母
struct BrandIcon: View {
    let domain: String
    let name: String
    var symbol = ""
    var size: CGFloat = 56
    @State private var img: UIImage?

    var body: some View {
        let logo = img ?? (domain.isEmpty ? nil : SenderLogos.shared.cached(domain))
        let shape = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
        ZStack {
            if let logo {
                Color.white
                if logo.size.width * logo.scale >= 150 {
                    Image(uiImage: logo).resizable().scaledToFill()
                } else {
                    Image(uiImage: logo).resizable().scaledToFit().padding(size * 0.2)
                }
            } else {
                let c = SenderID.colors(name)
                LinearGradient(colors: [c.0, c.1], startPoint: .top, endPoint: .bottom)
                if !symbol.isEmpty, symbol != "puzzlepiece.extension" {
                    Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text(verbatim: SenderID.initials(name, ""))
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .task(id: domain) {
            if img == nil, !domain.isEmpty { img = await SenderLogos.shared.image(for: domain, force: true) }
        }
    }
}
