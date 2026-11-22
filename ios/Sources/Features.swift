import Foundation

// MARK: 不需要模型的确定性回答：能力介绍、屏幕翻译、天气、运行已有技能
// 小模型被问「你能做什么」时容易胡说，天气更不能让它编，这里直接给出真实的内容。
@MainActor
enum Features {
    static let intro = """
    我是 OSVIA，住在你 iPhone 里的个人助理。能直接帮你：
    - 闹钟、提醒、日程：说「明早七点叫我起床」「10月30日下午三点开会」「每周一下午三点提醒我开会」
    - 天气：说「北京天气」「明天要带伞吗」，查过一次后只说「天气」就行
    - 联网搜索、读网页：问最新消息、价格，或发一个链接让我总结
    - 屏幕翻译：截屏后说「翻译屏幕」，译文贴回原图；工具箱里有一键用法
    - 网页文字：发网址说「提取文字」，去掉广告只留正文，可翻译、导出
    - 图片：识别文字（多张、扫描 PDF 也行）、翻译图片并贴回原位、本机去水印、抠图换证件照底色、自动打码手机号身份证人脸、压缩到指定大小
    - 音视频：录音/视频转文字并生成字幕、剪切、转 GIF、变速、合并、截取画面
    - 文件：文档扫描成可搜索 PDF、PDF 合并拆分压缩加密、二维码读取与生成、zip 打包解压
    - 文档互转：Word、Excel、PDF、Markdown、网页、CSV、JSON、图片互相转换；发文件后点输入框上的按钮就行
    - 视频与音频：去水印、提取音频、去除声音、压缩、转 m4a / wav
    - 知识库与记忆：说「记住……」，以后提问时我会自动翻一翻
    - 脚本技能：一句话做一个处理文字的小脚本，在 工具箱 → 脚本技能 里使用
    做不到的事：操作别的 App、代替你点击屏幕、在后台常驻运行。
    想让回答更聪明：设置 → 云端大脑，填一个免费密钥。
    """

    private static func toolRoute(_ s: String, _ low: String) -> ToolRequest? {
        func has(_ k: [String]) -> Bool { k.contains { low.contains($0) } }
        // 带网址 + 要正文
        if let u = Agent.firstURL(in: s), has(["提取文字", "提取正文", "提取网页", "提取内容", "网页文字", "抓取正文", "抓取网页", "网页正文", "全文"]), !has(["总结", "摘要", "翻译", "summar"]) {
            return ToolRequest(kind: .web, text: u.absoluteString)
        }
        guard s.count <= 10 else { return nil }
        if has(["视频去水印", "去视频水印"]) { return ToolRequest(kind: .wmVideo) }
        if has(["去水印", "去除水印", "去掉水印", "消除水印"]) { return ToolRequest(kind: .wmImage) }
        if has(["提取音频"]) { return ToolRequest(kind: .audio) }
        if has(["去除声音", "去掉声音", "视频静音", "视频去声音"]) { return ToolRequest(kind: .mute) }
        if has(["提取网页", "网页提取", "网页文字"]) { return ToolRequest(kind: .web) }
        if has(["表格识别", "识别表格", "提取表格", "图片转表格", "图片转excel", "图片转 excel", "表格转excel", "表格转 excel", "pdf转表格", "pdf 转表格"]) { return ToolRequest(kind: .table, files: Agent.shared.attachments.map { $0.url }) }
        if has(["识别文字", "图片转文字", "提取图片文字", "图片文字"]) { return ToolRequest(kind: .ocr) }
        if has(["格式转换", "文件转换", "转换格式"]) { return ToolRequest(kind: .convert) }
        let files = Agent.shared.attachments.map { $0.url }
        let hasAV = files.contains { Convert.vidExt.contains($0.pathExtension.lowercased()) || Convert.audExt.contains($0.pathExtension.lowercased()) }
        if has(["录音转文字", "语音转文字", "视频转文字", "音频转文字", "生成字幕", "视频字幕", "转写"]) || (hasAV && has(["转文字", "字幕"])) { return ToolRequest(kind: .transcribe, files: files) }
        if has(["剪视频", "视频剪辑", "剪切视频", "视频剪切", "转gif", "转 gif", "视频变速", "合并视频", "剪切音频", "音频剪切", "合并音频", "截取画面"]) { return ToolRequest(kind: .media, files: files) }
        if has(["扫描文档", "文档扫描", "扫描文件", "扫描件", "扫描成pdf", "扫描成 pdf"]) { return ToolRequest(kind: .scan) }
        if has(["二维码", "扫码", "条形码", "条码"]) { return ToolRequest(kind: .qr, files: files) }
        if has(["抠图", "去背景", "去除背景", "换背景", "证件照", "换底色"]) { return ToolRequest(kind: .cutout, files: files) }
        if has(["打码", "遮挡隐私", "隐私打码", "马赛克"]) { return ToolRequest(kind: .redact, files: files) }
        if has(["pdf工具", "pdf 工具", "合并pdf", "合并 pdf", "拆分pdf", "拆分 pdf", "压缩pdf", "压缩 pdf", "pdf加密", "pdf 加密", "pdf加页码"]) { return ToolRequest(kind: .pdf, files: files) }
        if has(["图片处理", "压缩图片", "图片压缩", "缩小图片", "改图片大小", "清除位置", "去除exif", "去除 exif"]) { return ToolRequest(kind: .imageEdit, files: files) }
        if has(["翻译图片", "图片翻译"]) { return ToolRequest(kind: .translateImage) }
        return nil
    }

    static func route(_ t: String) async -> String? {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = s.lowercased()

        // 屏幕翻译：打开页面并自动翻译相册里最新的一张截图
        let tr = ["屏幕翻译", "翻译屏幕", "翻译截图", "翻译这张截图", "翻译最新截图", "翻译当前屏幕", "翻译一下屏幕"]
        if s.count <= 16 && tr.contains(where: { s.contains($0) }) {
            ScreenTranslator.shared.request(data: nil)
            return "已打开屏幕翻译，正在翻译相册里最新的一张截图。先截屏再说这句话效果最好。"
        }

        // 动手工具：说一句就打开对应的工具页
        if let k = Self.toolRoute(s, low) {
            AppState.shared.tool = k
            return "已打开「\(k.kind.title)」。"
        }

        // 能力介绍（只匹配简短的提问，避免抢走正常的长问题）
        let asks = ["你能做什么", "你会什么", "你可以做什么", "你有什么功能", "你能干什么", "你在干什么", "你是谁", "怎么用", "如何使用", "使用说明", "功能介绍",
                    "他可以做什么", "它可以做什么", "what can you do", "who are you"]
        if s.count <= 14 && asks.contains(where: { low.contains($0) }) { return intro }

        // 天气：直接查，不交给模型；查不到时返回 nil，后面走联网搜索
        if let w = await Weather.route(s) { return w }

        // 运行已有技能：「运行 XX」「运行 XX 内容……」
        let verbs = ["运行", "执行", "使用", "用"]
        if let v = verbs.first(where: { s.hasPrefix($0) }) {
            for row in Skills.list() {
                let name = row.s("name")
                guard !name.isEmpty, s.hasPrefix(v + name) || s.hasPrefix(v + " " + name) else { continue }
                var input = String(s.dropFirst(v.count)).trimmingCharacters(in: .whitespaces)
                input = String(input.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ，,：:\n"))
                let r = await Skills.runAsync(name, input)
                return r.0 ? r.1 : "技能「\(name)」运行失败：\(r.1)"
            }
        }
        return nil
    }
}
