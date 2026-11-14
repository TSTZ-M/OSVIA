import Foundation

// 英文译文表的补充（新增界面文字）。L10n 查表时使用「主表 + 补充表」合并后的结果。
extension L10nTable {
    static let all: [String: String] = {
        var d = en
        for line in (extraRaw + "\n" + extraRaw2).split(separator: "\n", omittingEmptySubsequences: true) {
            guard let r = line.range(of: " ⇒ ") else { continue }
            let k = String(line[..<r.lowerBound]).replacingOccurrences(of: "\\n", with: "\n")
            let v = String(line[r.upperBound...]).replacingOccurrences(of: "\\n", with: "\n")
            if d[k] == nil { d[k] = v }
        }
        return d
    }()

    static let extraRaw = #"""
本地大模型 ⇒ Local LLM
使用本地大模型回答 ⇒ Answer with the local LLM
Apple 自带的模型很弱。这里可以把更强的开源大模型下载到手机，之后完全离线、免费运行。首次下载需要联网，下载时请保持 App 在前台并连接 Wi‑Fi。 ⇒ Apple’s built-in model is weak. Here you can download a stronger open-source LLM to your phone and run it completely offline for free. The first download needs internet; keep the app in the foreground and use Wi‑Fi.
选择模型 ⇒ Choose a model
下载线路 ⇒ Download source
自动使用国内镜像 hf-mirror.com；失败时改用 huggingface.co。 ⇒ Uses the hf-mirror.com mirror first and falls back to huggingface.co.
已就绪 ⇒ Ready
未下载本地模型 ⇒ No local model downloaded
正在下载 {}% ⇒ Downloading {}%
正在载入… ⇒ Loading…
下载失败：{} ⇒ Download failed: {}
大小约 {} GB ⇒ About {} GB
使用这个模型 ⇒ Use this model
删除模型 ⇒ Delete model
取消下载 ⇒ Cancel download
下载 ⇒ Download
轻量，速度快，占内存少 ⇒ Light and fast, low memory use
推荐：中文好，速度与质量均衡 ⇒ Recommended: good Chinese, balanced speed and quality
更强，占用内存更大 ⇒ Stronger, uses more memory
本地模型还没下载，请先到 设置 → 本地大模型 下载。 ⇒ The local model isn’t downloaded yet. Go to Settings → Local LLM to download one.
没有找到模型文件，请检查网络 ⇒ No model files found. Check your network
正在载入本地模型… ⇒ Loading the local model…
本地模型出错：{} ⇒ Local model error: {}
本地模型 ⇒ Local model
已启用：{} ⇒ On: {}
未启用 ⇒ Not enabled
"""#
}
