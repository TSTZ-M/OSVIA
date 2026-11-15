import Foundation

// 英文译文表的第二份补充：AI 记忆、MCP 服务、回答过程、新的对话页文字。格式：中文 ⇒ English，{} 是占位符。
extension L10nTable {
    static let extraRaw2 = #"""
今天有什么重要的科技新闻？ ⇒ What’s the important tech news today?
房贷 120 万，30 年，利率 3.1%，月供多少？ ⇒ Mortgage of 1.2 million over 30 years at 3.1% — what’s the monthly payment?
明早十点叫我起床 ⇒ Wake me up at 10 tomorrow morning
一周后下午三点提醒我交报告 ⇒ Remind me to hand in the report at 3 pm in a week
拒绝 ⇒ Deny
允许 ⇒ Allow
能联网查证、读网页、精确计算，记得你的偏好，还能连接 MCP 工具。 ⇒ I can search the web to verify facts, read pages, calculate precisely, remember your preferences, and connect to MCP tools.
AI 记忆 ⇒ AI Memory
已记住 {} 条 ⇒ {} remembered
从其他 AI 带来你的记忆 ⇒ Bring your memory from other AIs
MCP 服务 ⇒ MCP Servers
已启用 {} 个 ⇒ {} enabled
连接外部工具与数据 ⇒ Connect external tools and data
试试这样说 ⇒ Try saying
AI 记忆中心 ⇒ AI Memory Hub
导入其他 AI 的记忆，让助理越用越懂你 ⇒ Import memory from other AIs so your assistant knows you better over time
连接外部工具与数据，让助理能做更多事 ⇒ Connect external tools and data so your assistant can do more
个人 ⇒ Personal
偏好 ⇒ Preferences
工作 ⇒ Work
项目 ⇒ Projects
人际 ⇒ People
其他 ⇒ Other
复制导出提示词，跳转到其他 AI ⇒ Copy the export prompt and jump to another AI
ChatGPT、Claude、Gemini、豆包、Kimi 等 30 个主流 AI，也能填任意网址 ⇒ 30 major AIs including ChatGPT, Claude, Gemini, Doubao and Kimi — or any URL
选择要导出记忆的 AI ⇒ Choose an AI to export memory from
点一个 AI：导出提示词会自动复制并打开它。在那边发送，等它输出一个代码块，复制回复，再回来点「粘贴并导入」。 ⇒ Tap an AI: the export prompt is copied and the AI opens. Send it there, wait for the code block, copy the reply, then come back and import it.
粘贴那个 AI 的回复并导入 ⇒ Paste that AI’s reply and import
自动识别列表、Markdown、JSON，导入前可逐条确认 ⇒ Lists, Markdown and JSON are recognized; review each item before importing
从其他 AI 带来记忆 ⇒ Bring memory from other AIs
也适用于任何没有预设的 AI：复制提示词，去那里发送，再把回复粘贴回来。 ⇒ Works with any AI not in the list: copy the prompt, send it there, then paste the reply back.
粘贴或输入文字 ⇒ Paste or type text
选择文件 ⇒ Choose a file
手动添加一条 ⇒ Add one manually
手动导入 ⇒ Manual import
手动 ⇒ Manual
支持 txt、md、json，也支持 ChatGPT、Claude 的对话记录导出（conversations.json，ChatGPT 导出的 zip 需先解压）。 ⇒ Supports txt, md and json, plus chat exports from ChatGPT and Claude (conversations.json — unzip a ChatGPT export first).
管理 ⇒ Manage
全部记忆 ⇒ All memories
带着记忆去其他 AI ⇒ Take your memory to another AI
把你的背景与偏好整理成一段介绍，复制并打开选中的 AI，粘贴发送后它就了解你了。 ⇒ Your background and preferences are packed into a short intro, copied, and the chosen AI opens. Paste and send it so the AI knows you.
带去其他 AI ⇒ Take to another AI
导出为文本 ⇒ Export as text
正在整理… ⇒ Tidying up…
AI 整理（合并重复、修正分类） ⇒ AI tidy-up (merge duplicates, fix categories)
已撤销上次整理 ⇒ Last tidy-up undone
没有可撤销的整理 ⇒ Nothing to undo
撤销上次整理 ⇒ Undo last tidy-up
清空所有记忆 ⇒ Clear all memories
清空所有记忆？此操作无法撤销。 ⇒ Clear all memories? This can’t be undone.
清空 ⇒ Clear
已清空 ⇒ Cleared
进化记录 ⇒ Evolution log
记忆只保存在这台手机上。使用云端大脑时，与当前问题相关的记忆会随对话一起发给你配置的服务。 ⇒ Memories are stored only on this phone. With a cloud brain, memories relevant to the question are sent along with the conversation to the service you configured.
已导入 {} 条 ⇒ Imported {}
，{} 条已存在，已跳过 ⇒ , {} already existed and were skipped
这个文件里没有可识别的文字 ⇒ No readable text in this file
正在读取… ⇒ Reading…
条记忆，每次对话都会自然地用上 ⇒ memories, used naturally in every conversation
剪贴板是空的：先去那个 AI 复制它的回复 ⇒ The clipboard is empty — copy that AI’s reply first
其他 AI ⇒ Other AI
查看将发送的内容 ⇒ View what will be sent
已复制，可以粘贴到任何地方 ⇒ Copied — paste it anywhere
只复制，不跳转 ⇒ Copy only, don’t jump
其他 AI 的网址，例如 chat.example.com ⇒ URL of another AI, e.g. chat.example.com
打开 ⇒ Open
已复制提示词并打开。到输入框长按粘贴并发送 ⇒ Prompt copied and page opened. Long-press the input box to paste and send
网址不正确 ⇒ That URL isn’t valid
已打开 {}，提示词已填好，直接发送即可 ⇒ {} opened with the prompt filled in — just send it
已复制提示词。打开 {} 后，在输入框长按粘贴并发送 ⇒ Prompt copied. In {}, long-press the input box to paste and send
确认导入 ⇒ Confirm import
导入记忆 ⇒ Import memories
导入 {} 条 ⇒ Import {}
来源 ⇒ Source
例如 ChatGPT ⇒ e.g. ChatGPT
检测到对话记录：找到你发出的 {} 条消息。会用 AI 从中提炼关于你的长期信息，再让你逐条确认。 ⇒ Chat export detected: found {} messages from you. AI will distill long-term facts about you, then you confirm each one.
粘贴其他 AI 导出的记忆，或直接写：每条一行 ⇒ Paste memories exported from another AI, or type one per line
每行一条，可带 [类别] 前缀；Markdown 列表、JSON 也行。 ⇒ One per line, optionally prefixed with [category]; Markdown lists and JSON work too.
直接解析 ⇒ Parse directly
正在提炼… ⇒ Distilling…
正在提炼 {}/{}… ⇒ Distilling {}/{}…
AI 提炼（去重、去闲聊、归类） ⇒ AI distill (dedupe, drop small talk, categorize)
识别出 {} 条，已选 {} 条 ⇒ {} found, {} selected
全不选 ⇒ Select none
全选 ⇒ Select all
已存在的相似记忆会自动跳过。 ⇒ Similar memories that already exist are skipped automatically.
没有识别出可导入的内容，可以试试「AI 提炼」 ⇒ Nothing recognizable to import — try “AI distill”
需要先在设置里配置云端大脑或下载本地模型，才能 AI 提炼 ⇒ Set up a cloud brain or download a local model in Settings to use AI distill
没有提炼出可保留的内容 ⇒ Nothing worth keeping was found
还没有记忆。去「AI 记忆」导入，或在对话里说「记住……」。 ⇒ No memories yet. Import in “AI Memory”, or say “remember…” in chat.
没有匹配的记忆 ⇒ No matching memories
搜索记忆 ⇒ Search memories
取消置顶 ⇒ Unpin
置顶 ⇒ Pin
例如：我是 iOS 工程师，常用 SwiftUI ⇒ e.g. I’m an iOS engineer and use SwiftUI daily
类别 ⇒ Category
置顶（每次对话都会带上） ⇒ Pin (included in every conversation)
删除这条记忆 ⇒ Delete this memory
添加记忆 ⇒ Add memory
编辑记忆 ⇒ Edit memory
记忆还不多，不需要整理。 ⇒ Not many memories yet — no need to tidy up.
需要先配置云端大脑或本地模型。 ⇒ Set up a cloud brain or a local model first.
模型没有返回结果，稍后再试。 ⇒ The model returned nothing. Try again later.
整理结果异常，已放弃，原有记忆没有改动。 ⇒ The result looked wrong, so it was discarded. Your memories are unchanged.
整理完成：{} 条 → {} 条。可在下方撤销。 ⇒ Tidy-up done: {} → {}. You can undo it below.
MCP 让助理连接外部工具和数据：查官方文档、读代码仓库、调用你自己的服务。添加后，助理会在需要时自动使用；会改变外部状态的工具，每次都会先问你。 ⇒ MCP lets the assistant connect to external tools and data: look up official docs, read code repositories, call your own services. Once added, it is used automatically when needed; tools that change external state always ask you first.
还没有服务器。从下面挑一个，或添加自己的。 ⇒ No servers yet. Pick one below or add your own.
已添加 ⇒ Added
推荐（无需登录） ⇒ Recommended (no sign-in)
都是只读的文档与检索服务，添加后即可使用。 ⇒ Read-only documentation and search services that work right after adding.
添加 ⇒ Add
添加自定义服务器 ⇒ Add a custom server
支持 Streamable HTTP（新旧版本协议自动适配）。需要登录的服务请填访问令牌；暂不支持 OAuth 网页登录和旧式 SSE 地址。 ⇒ Supports Streamable HTTP (old and new protocol versions are detected automatically). For services that need sign-in, enter an access token; OAuth web sign-in and legacy SSE URLs aren’t supported yet.
已停用 ⇒ Disabled
{} 个工具 ⇒ {} tools
未连接 ⇒ Not connected
已连接 {} ⇒ Connected to {}
{} 已添加，但连接失败：{} ⇒ {} was added but the connection failed: {}
名称（可选） ⇒ Name (optional)
服务器地址，如 https://example.com/mcp ⇒ Server URL, e.g. https://example.com/mcp
服务器 ⇒ Server
必须是 https 开头的 Streamable HTTP 地址，通常以 /mcp 结尾。 ⇒ Must be an https Streamable HTTP URL, usually ending in /mcp.
访问令牌（可选） ⇒ Access token (optional)
其他请求头，每行一个，如 X-Api-Key: … ⇒ Other headers, one per line, e.g. X-Api-Key: …
授权 ⇒ Authorization
令牌会加上 Bearer 前缀作为 Authorization 发送，并保存在系统钥匙串里。 ⇒ The token is sent as an Authorization Bearer header and stored in the system Keychain.
自动允许所有工具 ⇒ Auto-allow all tools
关闭时，会改变外部状态的工具每次调用前都会先问你；声明为只读的工具不需要确认。 ⇒ When off, tools that change external state ask you before every call; tools declared read-only don’t need confirmation.
关闭「自动允许」时，会改变外部状态的工具每次调用前都会先问你；声明为只读的工具不需要确认。 ⇒ When “Auto-allow” is off, tools that change external state ask you before every call; tools declared read-only don’t need confirmation.
正在连接… ⇒ Connecting…
连接并保存 ⇒ Connect and save
添加服务器 ⇒ Add server
没能获取工具列表。 ⇒ Couldn’t get the tool list.
启用 ⇒ Enable
连接 ⇒ Connection
重新连接并刷新工具 ⇒ Reconnect and refresh tools
访问授权 ⇒ Access
访问令牌 ⇒ Access token
其他请求头，每行一个 ⇒ Other headers, one per line
保存并重新连接 ⇒ Save and reconnect
工具（{}） ⇒ Tools ({})
还没有获取到工具 ⇒ No tools yet
只读 ⇒ Read-only
删除这个服务器 ⇒ Delete this server
删除这个服务器？ ⇒ Delete this server?
已连接，{} 个工具可用 ⇒ Connected — {} tools available
读懂任意 GitHub 仓库：结构、文档、问答 ⇒ Understand any GitHub repo: structure, docs, Q&A
检索微软官方技术文档与示例代码 ⇒ Search official Microsoft docs and code samples
检索 Cloudflare 官方文档 ⇒ Search official Cloudflare docs
查询各种开发库的最新文档 ⇒ Up-to-date docs for all kinds of libraries
请填写 https 开头的服务器地址。 ⇒ Enter a server URL starting with https.
已经有同名的服务器了。 ⇒ A server with that name already exists.
服务器地址不正确。 ⇒ The server URL isn’t valid.
已连接，但服务器没有提供任何工具。 ⇒ Connected, but the server offers no tools.
服务器不支持新版协议 ⇒ The server doesn’t support the new protocol
服务器要求额外的交互输入，本应用暂不支持。 ⇒ The server needs extra interactive input, which isn’t supported yet.
服务器拒绝了请求（HTTP 400/404/405）。 ⇒ The server rejected the request (HTTP 400/404/405).
会话已失效，重新连接失败。 ⇒ The session expired and reconnecting failed.
没有收到响应 ⇒ No response received
未知错误 ⇒ Unknown error
MCP 错误： ⇒ MCP error: 
服务器没有返回有效的 MCP 响应。 ⇒ The server didn’t return a valid MCP response.
正在回答 ⇒ Answering
正在整理回答 ⇒ Composing the answer
秒 ⇒ s
已完成 {} 个步骤 ⇒ Done in {} steps
回忆 ⇒ Recall
用到 {} 条相关记忆 ⇒ Used {} relevant memories
联网搜索 ⇒ Web search
{} 条结果 ⇒ {} results
没有结果 ⇒ No results
读取网页 ⇒ Reading page
没读到内容 ⇒ Nothing readable
查询记忆 ⇒ Searching memory
{} 条 ⇒ {} items
写入记忆 ⇒ Saving memory
计算 ⇒ Calculating
查看当前时间 ⇒ Checking the time
运行技能 ⇒ Running skill
调用连接器 ⇒ Calling connector
查看 MCP 工具 ⇒ Browsing MCP tools
调用 MCP ⇒ Calling MCP
设置闹钟 ⇒ Setting alarm
添加提醒 ⇒ Adding reminder
添加日程 ⇒ Adding event
允许调用外部工具？ ⇒ Allow this external tool call?
好的，已经记住了。 ⇒ Got it — remembered.
这个我已经记过了。 ⇒ I already remembered that.
云端出错： ⇒ Cloud error: 
这次没能完成，可以点「重新生成」。 ⇒ Couldn’t finish this time. Tap “Regenerate”.
这次没能完成，可以换个说法再试。 ⇒ Couldn’t finish this time. Try rephrasing.
代码 ⇒ Code
已复制 ⇒ Copied
国际 ⇒ International
中国 ⇒ China
其他地区 ⇒ Other regions
制定计划 ⇒ Making a plan
查询天气 ⇒ Checking weather
运行代码 ⇒ Running code
创建技能 ⇒ Creating skill
调用接口 ⇒ Calling API
生成文件 ⇒ Creating file
读取文件 ⇒ Reading file
查看工作区 ⇒ Viewing workspace
删除文件 ⇒ Deleting file
查看日程 ⇒ Checking schedule
设置倒计时 ⇒ Setting timer
地图导航 ⇒ Map directions
地图搜索 ⇒ Map search
打开应用 ⇒ Opening app
打开网页 ⇒ Opening web page
短信草稿 ⇒ Message draft
邮件草稿 ⇒ Email draft
拨号 ⇒ Dialing
运行快捷指令 ⇒ Running shortcut
查看设备状态 ⇒ Checking device status
打开手电筒 ⇒ Turning on flashlight
关闭手电筒 ⇒ Turning off flashlight
复制到剪贴板 ⇒ Copying to clipboard
没找到这个地点 ⇒ Couldn’t find that place
没有安装或无法打开 ⇒ Not installed or can’t be opened
没有结果 ⇒ No results
允许发送网络请求？ ⇒ Allow this network request?
允许删除文件？ ⇒ Allow deleting this file?
允许运行快捷指令？ ⇒ Allow running this shortcut?
{} 个文件 ⇒ {} files
未来 {} 天 ⇒ Next {} days
邮箱 ⇒ Mail
需要你处理 ⇒ Needs your attention
了解即可 ⇒ For your information
通知 ⇒ Notifications
订阅与营销 ⇒ Newsletters & promotions
需要处理 ⇒ To handle
未读 ⇒ Unread
已分拣 ⇒ Sorted
紧急 ⇒ Urgent
待回复 ⇒ Awaiting reply
订阅 ⇒ Newsletter
了解 ⇒ FYI
连接你的邮箱，助理帮你盯收件箱： ⇒ Connect your mailbox and let the assistant watch your inbox:
按紧急程度分拣，每封一句话摘要 ⇒ Sorted by urgency, one-line summary for each
按你的意思起草回复，确认后才发送 ⇒ Drafts replies your way; sends only after you confirm
订阅和营销邮件自动归档（可选） ⇒ Auto-files newsletters and promotions (optional)
直接在对话里说：「看看有什么要紧邮件」 ⇒ Or just say in chat: “Check my important emails”
添加邮箱 ⇒ Add mailbox
支持 Gmail、iCloud、QQ、网易 163 / 126 / yeah、阿里、新浪、139、Yahoo、Zoho、Fastmail，以及任何支持 IMAP 的邮箱。使用「应用专用密码 / 授权码」登录，不会接触你的登录密码。 ⇒ Works with Gmail, iCloud, QQ, NetEase 163 / 126 / yeah, Aliyun, Sina, 139, Yahoo, Zoho, Fastmail and any IMAP mailbox. Sign in with an app-specific password / authorization code — your real password is never used.
收件箱里还没有同步到邮件。下拉刷新试试。 ⇒ No mail synced yet. Pull down to refresh.
邮箱账号与自动处理 ⇒ Accounts & auto-processing
分拣和摘要会把每封邮件开头的内容发给你设置的 AI 模型；想完全留在本机，请在设置里使用本机模型。 ⇒ Sorting and summaries send the beginning of each email to the AI model you configured. To keep everything on this device, use the on-device model in Settings.
（无主题） ⇒ (No subject)
建议： ⇒ Suggestion: 
正在读取邮件… ⇒ Loading email…
（这封邮件没有可显示的文字内容） ⇒ (This email has no displayable text)
删除这封邮件？ ⇒ Delete this email?
收件人 ⇒ To
主题 ⇒ Subject
想怎么回？一句话，如「同意，周四下午可以」 ⇒ How to reply? One line, e.g. “Yes, Thursday afternoon works”
AI 起草回复 ⇒ Draft reply with AI
正在起草… ⇒ Drafting…
原邮件的内容会发给你设置的 AI 模型。起草的内容请先看一遍再发。 ⇒ The original email is sent to your configured AI model. Review the draft before sending.
正文 ⇒ Body
回复 ⇒ Reply
发送 ⇒ Send
发送给 {}？ ⇒ Send to {}?
{} 之前没有和你往来过，请确认地址无误。 ⇒ You haven’t corresponded with {} before. Please double-check the address.
没能起草。请检查 AI 模型设置后再试，或直接手写。 ⇒ Couldn’t draft. Check your AI model settings and try again, or write it yourself.
收件人地址不正确。 ⇒ The recipient address isn’t valid.
自动处理 ⇒ Auto-process
上次同步 ⇒ Last synced
还没有 ⇒ Never
移除这个邮箱 ⇒ Remove this mailbox
开启「自动处理」后，每次打开 OSVIA（系统允许时也会在后台）会：把订阅与营销邮件标为已读并归到「OSVIA-Newsletters」文件夹；紧急和待回复的邮件发通知。不会自动回复、删除或发送任何邮件。iOS 不允许应用一直在后台运行，所以后台处理只是尽力而为。 ⇒ With “Auto-process” on, each time you open OSVIA (and in the background when the system allows) it marks newsletters and promotions as read and files them into the “OSVIA-Newsletters” folder, and notifies you of urgent mail and mail awaiting a reply. It never replies to, deletes or sends any mail automatically. iOS doesn’t let apps run in the background continuously, so background processing is best-effort.
自动处理记录 ⇒ Auto-processing log
邮箱账号 ⇒ Mail accounts
移除这个邮箱？ ⇒ Remove this mailbox?
移除 ⇒ Remove
只会删除这台设备上保存的账号和缓存，邮箱里的邮件不受影响。 ⇒ Only the account and cache stored on this device are removed. Mail in your mailbox is not affected.
邮箱地址 ⇒ Email address
显示名称（可选，写在发出的邮件上） ⇒ Display name (optional, shown on sent mail)
没有这个邮箱的预设，请在下面手动填写服务器（在邮箱网页的设置里能找到 IMAP / SMTP 服务器地址）。 ⇒ No preset for this mailbox. Enter the servers below (IMAP / SMTP addresses are in your mailbox’s web settings).
密码 / 授权码 ⇒ Password / authorization code
只保存在这台设备的系统钥匙串里，只用来连接你的邮箱服务器。 ⇒ Stored only in this device’s Keychain and used only to connect to your mail server.
IMAP 服务器，如 imap.example.com ⇒ IMAP server, e.g. imap.example.com
SMTP 服务器，如 smtp.example.com ⇒ SMTP server, e.g. smtp.example.com
SMTP 端口（465 或 587） ⇒ SMTP port (465 or 587)
服务器 ⇒ Servers
IMAP 使用 993 端口（SSL）。SMTP 465 为 SSL，587 为 STARTTLS。 ⇒ IMAP uses port 993 (SSL). SMTP 465 is SSL, 587 is STARTTLS.
正在连接… ⇒ Connecting…
连接并保存 ⇒ Connect and save
邮箱地址不正确。 ⇒ The email address isn’t valid.
打开 {} 的设置页 ⇒ Open {} settings
应用专用密码 ⇒ App-specific password
应用密码 ⇒ App password
授权码 ⇒ Authorization code
登录密码或授权码 ⇒ Password or authorization code
查看邮件 ⇒ Checking mail
阅读邮件 ⇒ Reading email
搜索邮件 ⇒ Searching mail
标为已读 ⇒ Marking as read
标为未读 ⇒ Marking as unread
加星标 ⇒ Starring
取消星标 ⇒ Removing star
归档邮件 ⇒ Archiving email
删除邮件 ⇒ Deleting email
移到垃圾邮件 ⇒ Moving to spam
整理邮件 ⇒ Organizing email
发送邮件 ⇒ Sending email
发送这封邮件？ ⇒ Send this email?
{} 封 ⇒ {} emails
打开 OSVIA 查看 ⇒ Open OSVIA to view
紧急邮件 ·  ⇒ Urgent mail · 
待回复 ·  ⇒ Awaiting reply · 
做一份本周学习计划，导出成 PDF ⇒ Make a study plan for this week and export it as a PDF
看看有什么要紧的邮件，该回的帮我起草 ⇒ Check my important emails and draft replies where needed
Gmail ⇒ Gmail
先在 Google 账号里开启两步验证，再生成「应用专用密码」（16 位），填到下面。 ⇒ Turn on 2-Step Verification in your Google account, then generate a 16-character “App password” and enter it below.
登录 Apple 账户 → 登录与安全 → 应用专用密码，生成一个填到下面。 ⇒ Sign in to your Apple Account → Sign-In & Security → App-Specific Passwords, generate one and enter it below.
微软正在逐步停用个人邮箱的密码登录。如果提示登录失败，说明你的账号已强制使用 OAuth，暂时无法连接。 ⇒ Microsoft is phasing out password sign-in for personal mailboxes. If login fails, your account requires OAuth, which isn’t supported yet.
网页版 QQ 邮箱 → 设置 → 账号 → 开启「IMAP/SMTP 服务」，按提示生成授权码。 ⇒ QQ Mail web → Settings → Account → turn on “IMAP/SMTP service” and generate an authorization code.
网页版 → 设置 → POP3/SMTP/IMAP → 开启 IMAP，并设置「客户端授权码」。 ⇒ Web mail → Settings → POP3/SMTP/IMAP → turn on IMAP and set a “client authorization code”.
确认邮箱已开启 IMAP；若开启了二次验证，请使用授权码。 ⇒ Make sure IMAP is enabled; if two-step verification is on, use an authorization code.
网页版 → 设置 → 客户端 POP/IMAP/SMTP，开启 IMAP 并获取授权码。 ⇒ Web mail → Settings → Client POP/IMAP/SMTP, turn on IMAP and get an authorization code.
网页版 → 设置 → 邮箱设置 → 客户端设置，开启 IMAP 并获取授权码。 ⇒ Web mail → Settings → Mailbox settings → Client settings, turn on IMAP and get an authorization code.
Yahoo 账号安全页 → 生成应用密码，填到下面。 ⇒ Yahoo account security page → generate an app password and enter it below.
Zoho 账号 → 安全 → 应用专用密码，并确认已开启 IMAP。 ⇒ Zoho account → Security → App-Specific Passwords, and make sure IMAP is enabled.
设置 → 密码与安全 → 应用密码，权限选「邮件（IMAP/SMTP）」。 ⇒ Settings → Password & Security → App passwords, choose “Mail (IMAP/SMTP)” access.
登录被拒绝：请确认填的是「应用专用密码 / 授权码」而不是登录密码，并且已在邮箱设置里开启 IMAP。 ⇒ Login rejected: make sure you entered an app-specific password / authorization code (not your login password) and that IMAP is enabled in your mailbox settings.
服务器认为这是不安全的登录。请在邮箱网页设置里开启 IMAP 并使用授权码。 ⇒ The server considers this login unsafe. Enable IMAP in your mailbox web settings and use an authorization code.
服务器断开了连接 ⇒ The server closed the connection
智能体 ⇒ Agents
国内 ⇒ China
陪伴 ⇒ Companions
搜索 AI、智能体、Bot… ⇒ Search AIs, agents, bots…
没有找到。可以在下面输入网址直接打开任意 AI。 ⇒ No match. Enter a URL below to open any AI directly.
刚才复制的内容可以一键导入 ⇒ What you just copied can be imported in one tap
正在导入… ⇒ Importing…
助理已读取这些记忆，并更新了对你的理解，下次对话就会用上。 ⇒ Your assistant has read these memories and updated its understanding of you. It will use them from the next chat.
撤销这次导入 ⇒ Undo this import
① 选一个 AI，我会复制导出指令并打开它，你在那边发送\n② 复制它的回复，回来点「粘贴」，自动导入 ⇒ ① Pick an AI — I copy the export prompt and open it; send it there\n② Copy its reply, come back and tap Paste to import automatically
选择 AI 导出 ⇒ Pick an AI to export from
点一个 AI：导出指令会自动复制并打开它。在那边发送，等它输出，复制回复，再回到这里。 ⇒ Tap an AI: the export prompt is copied and the AI opens. Send it there, wait for the reply, copy it, then come back here.
粘贴即导入：自动识别列表、Markdown、JSON，杂乱文字会用 AI 提炼；已有的相似内容自动跳过，导入后可撤销。也适用于没有预设的 AI。 ⇒ Paste to import: lists, Markdown and JSON are detected automatically, messy text is distilled by AI, similar existing items are skipped, and you can undo. Works for AIs not in the list too.
助理眼中的你 ⇒ How your assistant sees you
根据记忆重新生成 ⇒ Regenerate from memory
由你的记忆自动总结，每次对话都会带上。 ⇒ Summarized from your memory and included in every chat.
更多方式 ⇒ More ways
这些内容都已经在记忆里了 ⇒ All of this is already in memory
没有识别出可导入的内容。 ⇒ No importable content was recognized.
需要先在设置里配置云端大脑或下载本地模型，才能从对话记录里提炼。 ⇒ Set up a cloud brain or download a local model in Settings first to distill from chat history.
载入 {} 条记忆，{} 条与问题相关 ⇒ Loaded {} memories, {} relevant to the question
根据 {} 条记忆更新了助理对你的理解 ⇒ Updated the assistant’s understanding of you from {} memories
没有精确匹配，以下是关于用户的概览： ⇒ No exact match; here is an overview of the user:
诊断 ⇒ Diagnostics
诊断连接 ⇒ Test connection
诊断结果 ⇒ Test results
复制全部 ⇒ Copy all
清除记录 ⇒ Clear records
上次异常退出 ⇒ Last abnormal exit
最近记录 ⇒ Recent records
（没有记录） ⇒ (no records)
有记录 ⇒ Has records
遇到闪退或异常时，这里会留下线索。点「复制全部」发给开发者，就能快速定位问题。系统的崩溃报告通常在崩溃后一天内送达。 ⇒ When a crash or problem happens, clues are left here. Tap Copy all and send it to the developer to pinpoint the issue. System crash reports usually arrive within a day.
收件箱 {} 封 · 已同步 {} 封 · 新增 {} 封 ⇒ Inbox {} · synced {} · new {}
"""#
}
