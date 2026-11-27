// OSVIA 网页版（原生 JS，无依赖）。所有来自用户或服务器的文字都用 textContent 写入，避免注入。
"use strict";

// ---------- 多语言：键是中文原文，没有译文就显示原文 ----------
const EN = {
  "登录": "Sign in", "注册": "Sign up", "邮箱": "Email", "密码": "Password", "确认密码": "Confirm password",
  "支持 Gmail、Outlook、iCloud、QQ、网易等任意邮箱。": "Works with any email: Gmail, Outlook, iCloud, Yahoo and more.",
  "密码不会上传：它只在本机参与计算，服务器只保存校验值。": "Your password never leaves this device — the server only stores a salted check value.",
  "密码至少 8 位": "Password must be at least 8 characters", "两次输入的密码不一致": "Passwords do not match",
  "邮箱格式不正确": "Invalid email address", "正在处理…": "Working…", "验证码": "Verification code",
  "我们给你的邮箱发了 6 位验证码，10 分钟内有效。": "We sent a 6-digit code to your email. It expires in 10 minutes.",
  "验证": "Verify", "忘记密码？": "Forgot password?", "重置密码": "Reset password", "新密码": "New password", "返回登录": "Back to sign in",
  "提醒": "Reminders", "笔记": "Notes", "备份": "Backups", "助手": "Assistant", "账号": "Account",
  "内容": "What", "时间": "When", "重复": "Repeat", "仅一次": "Once", "每天": "Daily", "每周": "Weekly", "添加提醒": "Add reminder",
  "待提醒": "Upcoming", "已提醒": "Done", "删除": "Delete", "还没有提醒": "No reminders yet", "来自 iPhone": "From iPhone",
  "还没有设置 Bark：到点时不会有推送。去「我的」里填写 Bark 设备密钥。": "Bark isn't set up, so nothing will be pushed. Add your Bark key under Me.",
  "新建": "New", "搜索笔记": "Search notes", "标题": "Title", "写点什么…": "Write something…", "已保存": "Saved", "还没有笔记": "No notes yet",
  "返回": "Back", "无标题": "Untitled",
  "云备份": "Cloud backups", "上传备份文件": "Upload backup file", "下载": "Download", "还没有云备份": "No cloud backups yet",
  "备份在 iPhone 上加密后才会上传，服务器无法读取内容。恢复请在 App 里：设置 → OSVIA 账号 → 云备份。": "Backups are encrypted on your iPhone before upload; the server cannot read them. To restore, open the app: Settings → OSVIA Account → Cloud backups.",
  "只能上传 OSVIA 的加密备份（.osvbackup）。": "Only encrypted OSVIA backups (.osvbackup) can be uploaded.",
  "模型接口": "Model API", "服务商": "Provider", "接口地址": "Base URL", "模型名": "Model", "API 密钥": "API key", "系统提示词": "System prompt",
  "密钥只保存在这个浏览器里，发送时经 OSVIA 服务器转发给模型接口，服务器不保存。": "The key is stored only in this browser. It passes through the OSVIA server to your model API when you send and is never saved.",
  "发送": "Send", "停止": "Stop", "清空对话": "Clear chat", "复制": "Copy", "已复制": "Copied", "先在上面填好模型接口、模型名和密钥。": "Fill in the model API, model name and key above first.",
  "问点什么…": "Ask anything…", "自定义": "Custom", "出错了": "Error",
  "账号信息": "Account", "显示名称": "Display name", "保存": "Save", "语言": "Language", "已验证": "Verified", "未验证": "Not verified",
  "Bark 推送": "Bark push", "服务器（留空用官方）": "Server (blank = official)", "设备密钥（多个用逗号或换行分开）": "Device key(s), comma or newline separated",
  "加密密钥（可选）": "Encryption key (optional)", "已设置，留空则不修改": "Already set — leave blank to keep", "发送测试推送": "Send test push", "已发送": "Sent",
  "修改密码": "Change password", "当前密码": "Current password", "退出登录": "Sign out", "导出我的数据": "Export my data",
  "删除账号": "Delete account", "删除账号会清除云端的提醒、笔记和云备份，且无法恢复。输入密码确认：": "Deleting your account erases reminders, notes and cloud backups and cannot be undone. Enter your password to confirm:",
  "确定删除": "Delete permanently", "已删除": "Deleted", "密码已更新": "Password updated",
  "隐私政策": "Privacy Policy", "服务条款": "Terms of Service",
  "稍后提醒": "Snooze", "10 分钟后": "In 10 minutes", "1 小时后": "In 1 hour", "明天 9:00": "Tomorrow 9:00", "编辑": "Edit", "取消": "Cancel",
  "云端提醒": "Reminders", "云端笔记": "Notes", "云备份占用": "Backups",
  "首页": "Home", "我的": "Me", "对话": "Chats",
  "你的 AI 助手，网页与 iPhone 同步": "Your AI assistant, synced across web and iPhone",
  "登录即可使用内置 AI，不用自己准备 API 密钥。": "Sign in and use built-in AI — no API key to bring.",
  "内置 AI 对话": "Built-in AI chat", "无需 API 密钥，登录即用；对话保存在你的账号里，随时可删。": "No API key needed. Chats are saved to your account and can be deleted anytime.",
  "网页摘要与翻译": "Web summaries & translation", "贴一个链接或一段文字，几秒给出要点或译文。": "Paste a link or some text and get the gist or a translation in seconds.",
  "一句话设提醒": "Set reminders in one sentence", "说「明天下午 3 点开会」，自动识别时间。": "Say “tomorrow 3 pm meeting” and the time is parsed for you.",
  "笔记 + AI": "Notes + AI", "总结、润色、翻译、续写、提取待办，一键完成。": "Summarize, polish, translate, continue or pull out to-dos in one tap.",
  "Bark 推送提醒": "Bark push reminders", "到点推送到 iPhone，App 不在后台也准时。": "Pushed to your iPhone on time, even if the app is closed.",
  "加密云备份": "Encrypted cloud backup", "iPhone 端加密后上传，服务器无法读取内容。": "Encrypted on your iPhone before upload; the server can't read it.",
  "夜深了": "Late night", "早上好": "Good morning", "下午好": "Good afternoon", "晚上好": "Good evening",
  "AI 工具": "AI tools", "即将提醒": "Coming up", "最近笔记": "Recent notes",
  "网页摘要": "Web summary", "翻译": "Translate", "总结": "Summarize", "润色": "Polish", "提取待办": "To-dos", "续写": "Continue", "起标题": "Title it",
  "内置 AI 今日剩余": "Built-in AI left today", "今日已用": "Used today", "内置 AI": "Built-in AI",
  "输入要翻译的文字": "Text to translate", "粘贴要总结的长文": "Paste long text to summarize", "粘贴要润色的文字": "Paste text to polish",
  "粘贴会议记录或聊天内容，提取其中的待办": "Paste meeting notes or a chat to extract to-dos",
  "开始": "Go", "先贴一个网页链接": "Paste a web link first", "先输入要处理的文字": "Enter some text first", "AI 处理中…": "AI is working…",
  "存为笔记": "Save as note", "已存为笔记": "Saved as note", "译成": "Translate to",
  "有什么可以帮你？": "How can I help?", "帮我写一封请假邮件": "Write a leave-of-absence email", "用三句话解释什么是区块链": "Explain blockchain in three sentences",
  "给我一份一周的学习计划": "Make me a one-week study plan", "推荐几个提高专注力的方法": "Suggest ways to improve focus",
  "历史": "History", "新对话": "New chat", "设置": "Settings", "模式": "Mode", "内置 AI（免密钥）": "Built-in AI (no key)", "我的模型接口": "My own model API",
  "思考中…": "Thinking…", "正在回答…": "Answering…", "没有收到回复，请重试": "No reply received, please retry", "重新生成": "Regenerate",
  "对话历史": "Chat history", "还没有对话": "No chats yet", "加载中…": "Loading…", "返回对话": "Back to chat",
  "先写点内容": "Write something first", "替换原文": "Replace", "插入末尾": "Append", "用作标题": "Use as title", "关闭": "Close",
  "一句话设提醒，例如：明天下午 3 点开会": "Say it in one line, e.g. tomorrow 3 pm team meeting", "识别": "Parse", "识别中…": "Parsing…",
  "已识别，确认无误后点「添加提醒」": "Parsed — check it, then tap “Add reminder”",
  "删除全部对话": "Delete all chats",
};
let LANG = localStorage.getItem("osvia.lang") || ((navigator.language || "zh").toLowerCase().startsWith("zh") ? "zh" : "en");
const t = (s) => (LANG === "en" && EN[s]) || s;

// ---------- DOM 小工具 ----------
function h(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (k === "value") e.value = v;
    else if (v === true) e.setAttribute(k, "");
    else if (v !== false && v != null) e.setAttribute(k, v);
  }
  for (const c of kids.flat(Infinity)) if (c != null && c !== false) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
}
const $app = document.getElementById("app");
function mount(...nodes) { $app.replaceChildren(...nodes); }
function toast(msg) {
  const el = h("div", { class: "toast" }, msg);
  document.body.append(el);
  setTimeout(() => el.remove(), 2200);
}
function field(label, input) { return h("label", { class: "f" }, h("span", {}, t(label)), input); }
const fmt = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const fmtTime = (sec) => fmt.format(new Date(sec * 1000));
const fmtSize = (n) => (n > 1e6 ? (n / 1e6).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1e3)) + " KB");

// ---------- 状态与接口 ----------
const S = { token: localStorage.getItem("osvia.token") || "", user: null, tab: "home", sub: null, cfg: { mail: false, ai: false }, quota: null,
  chat: { id: null, msgs: [] }, abort: null, pendingAsk: "", tool: "web", focusNl: false };
const aiOn = () => !!S.cfg.ai;
function resetState() {
  if (S.abort) S.abort.abort();
  Object.assign(S, { token: "", user: null, tab: "home", sub: null, quota: null, chat: { id: null, msgs: [] }, abort: null, pendingAsk: "" });
  localStorage.removeItem("osvia.token");
}

async function api(path, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  if (S.token) headers.authorization = "Bearer " + S.token;
  let body = opts.body;
  if (body && typeof body === "object" && !(body instanceof ArrayBuffer) && !(body instanceof Blob)) {
    body = JSON.stringify(body);
    headers["content-type"] = "application/json";
  }
  let res;
  try {
    res = await fetch(path, { method: opts.method || "GET", headers, body, signal: opts.signal });
  } catch (e) {
    throw { error: "network", message: LANG === "en" ? "Network error" : "网络不通，请检查连接" };
  }
  if (opts.raw) return res;
  let data = {};
  try { data = await res.json(); } catch { /* 空响应 */ }
  if (res.status === 401 && S.token && !path.startsWith("/api/auth/")) { signOut(true); throw data; }
  if (!res.ok) throw data;
  return data;
}

function b64u(buf) {
  let s = "";
  new Uint8Array(buf).forEach((c) => (s += String.fromCharCode(c)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
// 从「密码 + 邮箱」派生 authKey：密码本身不离开本机。iOS App 用同样的参数
async function authKey(password, email) {
  const salt = new TextEncoder().encode("osvia-auth-v1:" + email.trim().toLowerCase());
  const km = await crypto.subtle.importKey("raw", new TextEncoder().encode(password.normalize("NFKC")), "PBKDF2", false, ["deriveBits"]);
  return b64u(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 210000 }, km, 256));
}

function saveSession(r) {
  S.token = r.token;
  S.user = r.user;
  localStorage.setItem("osvia.token", r.token);
  start();
}
function signOut(silent) {
  if (!silent && S.token) api("/api/auth/logout", { method: "POST" }).catch(() => {});
  resetState();
  renderAuth();
}

// ---------- 登录 / 注册 ----------
function renderAuth(mode = "login", pre = {}) {
  const email = h("input", { type: "email", autocomplete: "username", autocapitalize: "none", spellcheck: "false", value: pre.email || "", required: true });
  const pass = h("input", { type: "password", autocomplete: mode === "login" ? "current-password" : "new-password", required: true });
  const pass2 = h("input", { type: "password", autocomplete: "new-password" });
  const msg = h("p", { class: "err small" });
  const go = h("button", { class: "btn block", type: "submit" }, mode === "login" ? t("登录") : t("注册"));

  const form = h("form", {
    onsubmit: async (ev) => {
      ev.preventDefault();
      msg.textContent = "";
      const em = email.value.trim().toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(em)) { msg.textContent = t("邮箱格式不正确"); return; }
      if (mode === "register") {
        if (pass.value.length < 8) { msg.textContent = t("密码至少 8 位"); return; }
        if (pass.value !== pass2.value) { msg.textContent = t("两次输入的密码不一致"); return; }
      }
      go.disabled = true; go.textContent = t("正在处理…");
      try {
        const key = await authKey(pass.value, em);
        const r = await api(mode === "login" ? "/api/auth/login" : "/api/auth/register", { method: "POST", body: { email: em, authKey: key } });
        if (r.needVerify) return renderVerify(em);
        saveSession(r);
      } catch (e) {
        if (e.error === "need_verify") return renderVerify(em);
        msg.textContent = e.message || t("出错了");
        go.disabled = false; go.textContent = mode === "login" ? t("登录") : t("注册");
      }
    },
  },
    field("邮箱", email), field("密码", pass),
    mode === "register" ? field("确认密码", pass2) : null,
    msg, go,
    mode === "login" && S.cfg.mail ? h("p", { class: "center" }, h("button", { type: "button", class: "link", onclick: () => renderReset(email.value) }, t("忘记密码？"))) : null);

  const feats = FEATS.filter((f) => !f[0] || aiOn()).map(([, icon, name, desc]) => h("div", { class: "feat" }, svg(icon), h("div", {}, h("b", {}, t(name)), h("span", {}, t(desc)))));
  mount(h("div", { class: "land" },
    h("div", { class: "intro" },
      h("div", { class: "brand" }, h("img", { src: "/icon-192.png", alt: "" }), h("b", {}, "OSVIA")),
      h("h1", {}, t("你的 AI 助手，网页与 iPhone 同步")),
      aiOn() ? h("p", { class: "lead" }, t("登录即可使用内置 AI，不用自己准备 API 密钥。")) : null),
    h("div", { class: "auth" },
    h("div", { class: "seg" },
      h("button", { class: mode === "login" ? "on" : "", onclick: () => renderAuth("login", { email: email.value }) }, t("登录")),
      h("button", { class: mode === "register" ? "on" : "", onclick: () => renderAuth("register", { email: email.value }) }, t("注册"))),
    form,
    h("p", { class: "sub small center" }, t("支持 Gmail、Outlook、iCloud、QQ、网易等任意邮箱。")),
    h("p", { class: "sub small center" }, t("密码不会上传：它只在本机参与计算，服务器只保存校验值。")),
    legalLinks(),
    langSwitch()),
    h("div", { class: "feats" }, feats)));
}
// [仅内置 AI 开启时展示, 图标, 标题, 说明]
const FEATS = [
  [true, "assistant", "内置 AI 对话", "无需 API 密钥，登录即用；对话保存在你的账号里，随时可删。"],
  [true, "web", "网页摘要与翻译", "贴一个链接或一段文字，几秒给出要点或译文。"],
  [true, "remind", "一句话设提醒", "说「明天下午 3 点开会」，自动识别时间。"],
  [true, "notes", "笔记 + AI", "总结、润色、翻译、续写、提取待办，一键完成。"],
  [false, "reminders", "Bark 推送提醒", "到点推送到 iPhone，App 不在后台也准时。"],
  [false, "backups", "加密云备份", "iPhone 端加密后上传，服务器无法读取内容。"],
];

function legalLinks() {
  const a = (href, text) => h("a", { href, target: "_blank", rel: "noopener" }, t(text));
  return h("p", { class: "center small sub" }, a("/privacy", "隐私政策"), " · ", a("/terms", "服务条款"));
}

function langSwitch() {
  return h("p", { class: "center" }, h("button", { class: "link small", onclick: () => { LANG = LANG === "zh" ? "en" : "zh"; localStorage.setItem("osvia.lang", LANG); S.user ? render() : renderAuth(); } }, LANG === "zh" ? "English" : "中文"));
}

function renderVerify(em) {
  const code = h("input", { inputmode: "numeric", autocomplete: "one-time-code", maxlength: "6", required: true });
  const msg = h("p", { class: "err small" });
  mount(h("div", { class: "auth" },
    h("div", { class: "brand" }, h("img", { src: "/icon-192.png", alt: "" }), h("b", {}, "OSVIA")),
    h("p", {}, t("我们给你的邮箱发了 6 位验证码，10 分钟内有效。")),
    h("form", {
      onsubmit: async (ev) => {
        ev.preventDefault();
        try { saveSession(await api("/api/auth/verify", { method: "POST", body: { email: em, code: code.value } })); }
        catch (e) { msg.textContent = e.message || t("出错了"); }
      },
    }, field("验证码", code), msg, h("button", { class: "btn block", type: "submit" }, t("验证"))),
    h("p", { class: "center" }, h("button", { class: "link", onclick: () => renderAuth("login", { email: em }) }, t("返回登录")))));
}

function renderReset(em) {
  const email = h("input", { type: "email", value: em || "", required: true });
  const code = h("input", { inputmode: "numeric", maxlength: "6" });
  const pass = h("input", { type: "password", autocomplete: "new-password" });
  const msg = h("p", { class: "small" });
  mount(h("div", { class: "auth" },
    h("div", { class: "brand" }, h("img", { src: "/icon-192.png", alt: "" }), h("b", {}, "OSVIA")),
    h("h2", {}, t("重置密码")),
    h("div", { class: "card" },
      field("邮箱", email),
      h("button", { class: "btn ghost sm", onclick: async () => {
        try { await api("/api/auth/code", { method: "POST", body: { email: email.value.trim() } }); msg.className = "ok small"; msg.textContent = t("已发送"); }
        catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); }
      } }, t("验证码"))),
    field("验证码", code), field("新密码", pass), msg,
    h("button", { class: "btn block", onclick: async () => {
      const em2 = email.value.trim().toLowerCase();
      if (pass.value.length < 8) { msg.className = "err small"; msg.textContent = t("密码至少 8 位"); return; }
      try {
        await api("/api/auth/reset", { method: "POST", body: { email: em2, code: code.value, authKey: await authKey(pass.value, em2) } });
        renderAuth("login", { email: em2 });
      } catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); }
    } }, t("重置密码")),
    h("p", { class: "center" }, h("button", { class: "link", onclick: () => renderAuth("login", { email: email.value }) }, t("返回登录")))));
}

// ---------- 主界面 ----------
const ST = (p) => '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + p + "</g>";
const ICONS = {
  reminders: '<path d="M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6V11a6 6 0 1 0-12 0v5l-2 2v1h16v-1z" fill="currentColor"/>',
  notes: '<path d="M6 2h9l5 5v15H6zM14 3.5V8h4.5M9 12h8v1.5H9zm0 3.5h8V17H9z" fill="currentColor"/>',
  backups: '<path d="M19.4 11A7.5 7.5 0 0 0 5 9.6 5 5 0 0 0 6 19.5h12.5a4 4 0 0 0 .9-8.5z" fill="currentColor"/>',
  assistant: '<path d="M4 4h16v12H8l-4 4zm4 4v1.5h8V8zm0 3v1.5h5V11z" fill="currentColor"/>',
  me: '<path d="M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9zm0 2c-4.4 0-8 2.2-8 5v2h16v-2c0-2.8-3.6-5-8-5z" fill="currentColor"/>',
  home: '<path d="M12 3 3 10.5V21h6.5v-6h5v6H21V10.5z" fill="currentColor"/>',
  web: ST('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>'),
  translate: ST('<path d="M4 5h9M8.5 3v2M6 5c0 4 3 7 6 8M11 5c0 4-3 7-7 9M13 20l4-9 4 9M14.5 17h5"/>'),
  summarize: ST('<path d="M4 6h16M4 12h16M4 18h10"/>'),
  polish: ST('<path d="M12 3l1.8 4.7 4.7 1.8-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18 15l.8 2.2L21 18l-2.2.8L18 21l-.8-2.2L15 18l2.2-.8z"/>'),
  todos: ST('<path d="M4 6l2 2 3-3M4 15l2 2 3-3M12 7h8M12 16h8"/>'),
  remind: ST('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
};
const tabs = () => [["home", "首页"], ["assistant", "助手"], ["notes", "笔记"], ...(aiOn() ? [["auto", "自动化"]] : []), ["reminders", "提醒"], ["me", "我的"]];

function svg(name) {
  const w = document.createElement("span");
  w.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`; // 固定内置图标，不含用户内容
  return w.firstChild;
}

let content;
// 往当前页面追加内容：自动展平数组、忽略 null/false（原生 append 会把 null 写成文字）
const addc = (...k) => content.append(...k.flat(Infinity).filter((x) => x != null && x !== false));
function render() {
  if (S.abort) S.abort.abort(); // 离开助手页就停掉生成，已生成的部分会保存
  if (S.flush) { const f = S.flush; S.flush = null; f(); } // 离开笔记页前先存好还没落盘的修改
  const nav = h("nav", { class: "nav" },
    h("div", { class: "logo" }, h("img", { src: "/icon-192.png", alt: "" }), "OSVIA"),
    ...tabs().map(([id, label]) => h("button", { class: S.tab === id ? "on" : "", "data-tab": id, "aria-current": S.tab === id ? "page" : null, onclick: () => go(id) }, svg(id), h("span", {}, t(label)))));
  content = h("main", { class: "main" + (S.tab === "notes" && !S.sub ? " wide" : "") });
  mount(h("div", { class: "shell" }, nav, content));
  window.scrollTo(0, 0);
  const view = S.sub === "tools" ? viewTools : S.sub === "backups" ? viewBackups : S.sub === "webtools" ? viewWebTools : S.sub === "clip" ? viewClip
    : { home: viewHome, assistant: viewAssistant, notes: viewNotes, auto: viewAuto, reminders: viewReminders, me: viewAccount }[S.tab];
  view();
  paintBadge();
}
function go(tab, sub = null, extra = {}) { Object.assign(S, extra, { tab, sub }); render(); }

async function start() {
  stashClip(); // 书签 / 系统分享带来的网页内容，登录后再处理
  try { S.cfg = await api("/api/config"); } catch { /* 保持默认 */ }
  if (!S.token) return renderAuth();
  try {
    const r = await api("/api/me");
    S.user = r.user; S.counts = r.counts;
    takeClip();
    render();
    refreshUnread();
  } catch { renderAuth(); }
}

// ---------- 提醒 ----------
const localInput = (sec) => new Date(sec * 1000 - new Date(sec * 1000).getTimezoneOffset() * 60000).toISOString().slice(0, 16);
function snoozeDue(v) {
  if (v === "tom") { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(9, 0, 0, 0); return Math.floor(d / 1000); }
  return Math.floor(Date.now() / 1000) + Number(v);
}
async function viewReminders() {
  const title = h("input", { placeholder: t("内容"), maxlength: "120" });
  const when = h("input", { type: "datetime-local" });
  const d = new Date(Date.now() + 3600e3); d.setMinutes(0, 0, 0);
  when.value = localInput(Math.floor(d / 1000));
  const rep = h("select", {}, h("option", { value: "0" }, t("仅一次")), h("option", { value: "1" }, t("每天")), h("option", { value: "7" }, t("每周")));
  const list = h("div", {});
  const banner = h("div", {});
  const nl = h("input", { placeholder: t("一句话设提醒，例如：明天下午 3 点开会"), "aria-label": t("一句话设提醒"), maxlength: "200", onkeydown: (e) => { if (e.key === "Enter" && !e.isComposing) parse(); } });
  const nlMsg = h("p", { class: "small" });
  const nlBtn = h("button", { class: "btn", onclick: parse }, t("识别"));
  async function parse() {
    const text = nl.value.trim();
    if (!text) return;
    nlBtn.disabled = true; nlMsg.className = "sub small"; nlMsg.textContent = t("识别中…");
    try {
      const { reminder: r } = await api("/api/ai/reminder", { method: "POST", body: { text, tz: new Date().getTimezoneOffset() } });
      bump();
      title.value = r.title; when.value = localInput(r.due); rep.value = String(r.rep);
      nlMsg.className = "ok small"; nlMsg.textContent = t("已识别，确认无误后点「添加提醒」") + " · " + fmtTime(r.due);
    } catch (e) { nlMsg.className = "err small"; nlMsg.textContent = e.message || t("出错了"); }
    nlBtn.disabled = false;
  }
  addc(h("h2", {}, t("提醒")), banner,
    aiOn() ? h("div", { class: "card" }, h("div", { class: "askbar" }, nl, nlBtn), nlMsg) : null,
    h("div", { class: "card" }, field("内容", title), h("div", { class: "row" }, field("时间", when), field("重复", rep)),
      h("button", { class: "btn block", onclick: async () => {
        const due = Math.floor(new Date(when.value).getTime() / 1000);
        if (!title.value.trim() || !due) return;
        try { await api("/api/reminders", { method: "POST", body: { title: title.value, due, rep: Number(rep.value) } }); title.value = ""; load(); }
        catch (e) { toast(e.message || t("出错了")); }
      } }, t("添加提醒"))),
    list);
  if (S.focusNl) { S.focusNl = false; nl.focus(); }
  async function load() {
    try {
      const [{ items }, b] = await Promise.all([api("/api/reminders"), api("/api/bark")]);
      banner.replaceChildren(b.keySet ? "" : h("div", { class: "banner" }, t("还没有设置 Bark：到点时不会有推送。去「我的」里填写 Bark 设备密钥。")));
      const upcoming = items.filter((r) => !r.sent), done = items.filter((r) => r.sent);
      const row = (r) => {
        const box = h("div", { class: "item col" + (r.sent ? " done" : "") });
        const web = r.src !== "ios";
        const put = async (body) => { try { await api("/api/reminders/" + r.id, { method: "PUT", body }); load(); } catch (e) { toast(e.message || t("出错了")); } };
        const view = () => box.replaceChildren(
          h("div", { class: "line" },
            h("div", { class: "t" }, h("b", {}, r.title), h("span", { class: "sub small" }, fmtTime(r.due) + (r.rep ? " · " + t(r.rep === 1 ? "每天" : "每周") : ""))),
            r.src === "ios" ? h("span", { class: "tag" }, t("来自 iPhone")) : null),
          h("div", { class: "acts" },
            web ? h("select", { class: "sm-sel", "aria-label": t("稍后提醒"), onchange: (e) => { const v = e.target.value; if (v) put({ due: snoozeDue(v) }); } },
              h("option", { value: "" }, t("稍后提醒")), h("option", { value: "600" }, t("10 分钟后")), h("option", { value: "3600" }, t("1 小时后")), h("option", { value: "tom" }, t("明天 9:00"))) : null,
            web ? h("button", { class: "btn ghost sm", onclick: edit }, t("编辑")) : null,
            h("button", { class: "btn ghost sm", onclick: async () => { await api("/api/reminders/" + r.id, { method: "DELETE" }); load(); } }, t("删除"))));
        function edit() {
          const ti = h("input", { value: r.title, maxlength: "120" });
          const wh = h("input", { type: "datetime-local", value: localInput(r.due) });
          const rp = h("select", {}, h("option", { value: "0" }, t("仅一次")), h("option", { value: "1" }, t("每天")), h("option", { value: "7" }, t("每周")));
          rp.value = String(r.rep || 0);
          box.replaceChildren(field("内容", ti), h("div", { class: "row" }, field("时间", wh), field("重复", rp)),
            h("div", { class: "acts" }, h("button", { class: "btn ghost sm", onclick: view }, t("取消")),
              h("button", { class: "btn sm", onclick: () => { const due = Math.floor(new Date(wh.value).getTime() / 1000); if (ti.value.trim() && due) put({ title: ti.value, due, rep: Number(rp.value) }); } }, t("保存"))));
        }
        view();
        return box;
      };
      list.replaceChildren(...[
        upcoming.length ? [h("h3", {}, t("待提醒")), upcoming.map(row)] : h("div", { class: "empty" }, t("还没有提醒")),
        done.length ? [h("h3", {}, t("已提醒")), done.map(row)] : null].flat(Infinity).filter(Boolean));
    } catch (e) { list.textContent = e.message || ""; }
  }
  load();
}

// 笔记（桌面双栏）见 web.js

// ---------- 云备份 ----------
async function viewBackups() {
  const list = h("div", {});
  const file = h("input", { type: "file", accept: ".osvbackup", class: "hidden", onchange: async () => {
    const f = file.files[0]; if (!f) return;
    try { await api("/api/backups?name=" + encodeURIComponent(f.name) + "&device=web", { method: "PUT", body: await f.arrayBuffer() }); toast(t("已保存")); load(); }
    catch (e) { toast(e.message || t("出错了")); }
    file.value = "";
  } });
  addc(h("button", { class: "btn ghost sm back", onclick: () => go("me") }, "‹ " + t("返回")), h("div", { class: "top" }, h("h2", {}, t("云备份")), h("button", { class: "btn sm", onclick: () => file.click() }, t("上传备份文件"))), file,
    h("p", { class: "sub small" }, t("备份在 iPhone 上加密后才会上传，服务器无法读取内容。恢复请在 App 里：设置 → OSVIA 账号 → 云备份。")), list);
  async function load() {
    try {
      const { items } = await api("/api/backups");
      list.replaceChildren(...(items.length ? items.map((b) => h("div", { class: "item" },
        h("div", { class: "t" }, h("b", {}, b.name), h("span", { class: "sub small" }, fmtTime(b.created) + " · " + fmtSize(b.size) + (b.device ? " · " + b.device : ""))),
        h("button", { class: "btn ghost sm", onclick: async () => {
          const res = await api("/api/backups/" + b.id, { raw: true });
          if (!res.ok) return toast(t("出错了"));
          const a = h("a", { href: URL.createObjectURL(await res.blob()), download: b.name });
          document.body.append(a); a.click(); a.remove();
        } }, t("下载")),
        h("button", { class: "btn ghost sm", onclick: async () => { await api("/api/backups/" + b.id, { method: "DELETE" }); load(); } }, t("删除")))) : [h("div", { class: "empty" }, t("还没有云备份"))]));
    } catch (e) { list.textContent = e.message || ""; }
  }
  load();
}

// ---------- AI 公共小工具 ----------
const PROVIDERS = [
  ["openai", "OpenAI", "https://api.openai.com/v1", "openai"],
  ["anthropic", "Anthropic", "https://api.anthropic.com", "anthropic"],
  ["deepseek", "DeepSeek", "https://api.deepseek.com/v1", "openai"],
  ["openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "openai"],
  ["dashscope", "阿里云百炼", "https://dashscope.aliyuncs.com/compatible-mode/v1", "openai"],
  ["moonshot", "Moonshot", "https://api.moonshot.cn/v1", "openai"],
  ["zhipu", "智谱 AI", "https://open.bigmodel.cn/api/paas/v4", "openai"],
  ["siliconflow", "SiliconFlow", "https://api.siliconflow.cn/v1", "openai"],
  ["custom", "自定义", "", "openai"],
];
const LANGS = [["zh", "中文"], ["en", "English"], ["ja", "日本語"], ["ko", "한국어"], ["fr", "Français"], ["de", "Deutsch"], ["es", "Español"], ["ru", "Русский"]];
const loadJSON = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } };

function renderMd(text) {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const parts = text.split(/```/);
  return parts.map((p, i) => {
    if (i % 2 === 1) return "<pre><code>" + esc(p.replace(/^[^\n]*\n/, "")) + "</code></pre>";
    let s = esc(p);
    s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
    s = s.replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
    s = s.replace(/(^|\n)((?:[-*] .+(?:\n|$))+)/g, (m, a, b) => a + "<ul>" + b.trim().split("\n").map((l) => "<li>" + l.slice(2) + "</li>").join("") + "</ul>");
    return s.replace(/\n/g, "<br>").replace(/<\/ul><br>/g, "</ul>");
  }).join("");
}

const dots = () => h("span", { class: "dots", "aria-hidden": "true" }, h("i"), h("i"), h("i"));
async function copyText(s) {
  try { await navigator.clipboard.writeText(s); toast(t("已复制")); } catch { toast(t("出错了")); }
}
async function saveAsNote(title, body) {
  try {
    await api("/api/notes", { method: "POST", body: { title: String(title).replace(/\s+/g, " ").trim().slice(0, 60), body } });
    toast(t("已存为笔记"));
  } catch (e) { toast(e.message || t("出错了")); }
}
async function loadQuota() {
  if (!aiOn()) return null;
  try { S.quota = await api("/api/ai/quota"); } catch { /* 保持旧值 */ }
  return S.quota;
}
const bump = () => { if (S.quota) S.quota.used++; };
const quotaText = () => (S.quota ? `${t("内置 AI 今日剩余")} ${Math.max(0, S.quota.max - S.quota.used)}/${S.quota.max}` : "");
async function readSSE(res, on) {
  const rd = res.body.getReader(), dec = new TextDecoder();
  let buf = "";
  const line = (ln) => {
    if (!ln.startsWith("data:")) return;
    const d = ln.slice(5).trim();
    if (!d || d === "[DONE]") return;
    let j; try { j = JSON.parse(d); } catch { return; }
    on(j);
  };
  for (;;) {
    const { done, value } = await rd.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split("\n"); buf = lines.pop();
    lines.forEach(line);
  }
  line(buf);
}

// ---------- 首页 ----------
const TOOL_NAMES = { web: "网页摘要", translate: "翻译", summarize: "总结", polish: "润色", todos: "提取待办" };
async function viewHome() {
  const name = S.user.name || S.user.email.split("@")[0];
  const hr = new Date().getHours();
  const hi = hr < 6 ? "夜深了" : hr < 12 ? "早上好" : hr < 18 ? "下午好" : "晚上好";
  const ask = h("input", { placeholder: t("问点什么…"), "aria-label": t("问点什么…"), onkeydown: (e) => { if (e.key === "Enter" && !e.isComposing) submit(); } });
  const submit = () => { const v = ask.value.trim(); if (v) go("assistant", null, { pendingAsk: v }); };
  const quota = h("p", { class: "sub small" });
  const rem = h("div", {}), notes = h("div", {});
  const tile = (icon, label, fn) => h("button", { class: "tile", onclick: fn }, svg(icon), h("span", {}, t(label)));

  addc(
    h("div", { class: "hello" }, h("h2", {}, t(hi) + (LANG === "en" ? ", " : "，") + name),
      h("p", { class: "sub" }, new Intl.DateTimeFormat(undefined, { dateStyle: "full" }).format(new Date()))),
    aiOn() ? h("div", { class: "card hero" }, h("div", { class: "askbar" }, ask, h("button", { class: "btn", onclick: submit }, t("发送"))), quota) : null,
    aiOn() ? [h("h3", {}, t("AI 工具")),
      h("div", { class: "tiles" },
        ...Object.keys(TOOL_NAMES).map((k) => tile(k, TOOL_NAMES[k], () => go("home", "tools", { tool: k }))),
        tile("remind", "一句话提醒", () => go("reminders", null, { focusNl: true })))] : null,
    homeExtras(),
    h("h3", {}, t("即将提醒")), rem,
    h("h3", {}, t("最近笔记")), notes);

  const empty = (msg, to, label) => h("div", { class: "card center" }, h("p", { class: "sub" }, t(msg)), h("button", { class: "btn ghost sm", onclick: () => go(to) }, t(label)));
  const [r, n] = await Promise.allSettled([api("/api/reminders"), api("/api/notes"), loadQuota()]);
  if (S.tab !== "home" || S.sub) return;
  if (aiOn()) quota.textContent = quotaText();
  const up = r.status === "fulfilled" ? r.value.items.filter((x) => !x.sent).sort((a, b) => a.due - b.due).slice(0, 3) : [];
  rem.replaceChildren(...(up.length ? up.map((x) => h("div", { class: "item go", onclick: () => go("reminders") },
    h("div", { class: "t" }, h("b", {}, x.title), h("span", { class: "sub small" }, fmtTime(x.due) + (x.rep ? " · " + t(x.rep === 1 ? "每天" : "每周") : "")))))
    : [empty("还没有提醒", "reminders", "添加提醒")]));
  const nn = n.status === "fulfilled" ? n.value.items.slice(0, 3) : [];
  notes.replaceChildren(...(nn.length ? nn.map((x) => h("div", { class: "item go", onclick: () => go("notes") },
    h("div", { class: "t" }, h("b", {}, x.title || t("无标题")), h("span", { class: "sub small" }, (x.body || "").replace(/\s+/g, " ").slice(0, 60))),
    h("span", { class: "sub small" }, fmtTime(x.updated)))) : [empty("还没有笔记", "notes", "新建")]));
}

// ---------- AI 工具：网页摘要 / 翻译 / 总结 / 润色 / 待办 ----------
function viewTools() {
  const HINT = { translate: "输入要翻译的文字", summarize: "粘贴要总结的长文", polish: "粘贴要润色的文字", todos: "粘贴会议记录或聊天内容，提取其中的待办" };
  let tool = TOOL_NAMES[S.tool] ? S.tool : "web", busy = false;
  const src = { url: "", text: "", lang: LANG === "zh" ? "en" : "zh" };
  const chips = h("div", { class: "chips" }), form = h("div", {}), result = h("div", {});

  function draw() {
    chips.replaceChildren(...Object.keys(TOOL_NAMES).map((k) => h("button", { class: "chip" + (k === tool ? " on" : ""), onclick: () => { if (k !== tool) { tool = k; result.replaceChildren(); draw(); } } }, t(TOOL_NAMES[k]))));
    const isWeb = tool === "web";
    const url = h("input", { type: "url", inputmode: "url", autocapitalize: "none", spellcheck: "false", placeholder: "https://…", "aria-label": t("网页摘要"), oninput: (e) => { src.url = e.target.value; }, onkeydown: (e) => { if (e.key === "Enter") run(); } });
    url.value = src.url;
    const txt = h("textarea", { placeholder: t(HINT[tool] || ""), "aria-label": t(TOOL_NAMES[tool]), oninput: (e) => { src.text = e.target.value; } });
    txt.value = src.text;
    const lang = h("select", { "aria-label": t("译成"), onchange: (e) => { src.lang = e.target.value; } }, LANGS.map(([v, l]) => h("option", { value: v }, l)));
    lang.value = src.lang;
    const btn = h("button", { class: "btn", onclick: run }, t("开始"));
    form.replaceChildren(h("div", { class: "card" }, isWeb ? url : txt,
      h("div", { class: "row tool-act" }, tool === "translate" ? h("label", { class: "f fit" }, h("span", {}, t("译成")), lang) : null, btn)));
    form.btn = btn;
  }

  async function run() {
    if (busy) return;
    const isWeb = tool === "web";
    const input = (isWeb ? src.url : src.text).trim();
    if (!input) return toast(t(isWeb ? "先贴一个网页链接" : "先输入要处理的文字"));
    busy = true;
    const btn = form.btn;
    btn.disabled = true; btn.textContent = t("正在处理…");
    result.replaceChildren(h("div", { class: "card thinking" }, t("AI 处理中…"), dots()));
    try {
      if (isWeb) {
        const r = await api("/api/ai/web", { method: "POST", body: { url: input } });
        show(r.summary, r.title, r.url);
      } else {
        const r = await api("/api/ai/tool", { method: "POST", body: { tool, text: input, lang: src.lang } });
        show(r.text, "", "");
      }
      bump();
    } catch (e) {
      result.replaceChildren(h("div", { class: "card err" }, e.message || t("出错了")));
    }
    busy = false; btn.disabled = false; btn.textContent = t("开始");
  }

  function show(text, title, link) {
    const md = h("div", { class: "md" }); md.innerHTML = renderMd(text); // renderMd 先转义再加标签
    result.replaceChildren(h("div", { class: "card result" },
      title || link ? h("div", { class: "src" }, title ? h("b", {}, title) : null, link ? h("a", { href: link, target: "_blank", rel: "noopener noreferrer" }, link) : null) : null,
      md,
      h("div", { class: "acts" },
        h("button", { class: "btn ghost sm", onclick: () => copyText(text) }, t("复制")),
        h("button", { class: "btn ghost sm", onclick: () => pushPhone(title || t("AI 工具"), text, link) }, t("发到手机")),
        h("button", { class: "btn sm", onclick: () => saveAsNote(title || text.split("\n")[0], (link ? link + "\n\n" : "") + text) }, t("存为笔记")))));
  }

  addc(
    h("div", { class: "top" }, h("button", { class: "btn ghost sm", onclick: () => go("home") }, "‹ " + t("首页")), h("h2", {}, t("AI 工具")), h("span", { class: "sub small" }, quotaText())),
    chips, form, result);
  draw();
  enableDrop(content, (fs) => { if (tool === "web") tool = "summarize"; src.text = fs.map((f) => f.text).join("\n\n").slice(0, 12000); result.replaceChildren(); draw(); });
  loadQuota().then(() => { const el = content.querySelector(".top .sub"); if (el) el.textContent = quotaText(); });
}

// ---------- 助手：内置 AI（免密钥）或你自己的模型接口，对话云端保存 ----------
function viewAssistant() {
  const cfg = loadJSON("osvia.llm", { provider: "openai", base: PROVIDERS[0][2], kind: "openai", model: "", key: "", system: "" });
  const saveCfg = () => localStorage.setItem("osvia.llm", JSON.stringify(cfg));
  const useBuiltin = () => aiOn() && localStorage.getItem("osvia.amode") !== "custom";

  const prov = h("select", { onchange: () => {
    const p = PROVIDERS.find((x) => x[0] === prov.value);
    cfg.provider = p[0]; cfg.kind = p[3]; if (p[2]) cfg.base = p[2]; base.value = cfg.base; saveCfg();
  } }, PROVIDERS.map((p) => h("option", { value: p[0] }, p[0] === "custom" ? t("自定义") : p[1])));
  prov.value = cfg.provider;
  const base = h("input", { value: cfg.base, placeholder: "https://…", oninput: () => { cfg.base = base.value.trim(); saveCfg(); } });
  const model = h("input", { value: cfg.model, oninput: () => { cfg.model = model.value.trim(); saveCfg(); } });
  const key = h("input", { type: "password", value: cfg.key, autocomplete: "off", oninput: () => { cfg.key = key.value.trim(); saveCfg(); } });
  const sys = h("textarea", { oninput: () => { cfg.system = sys.value; saveCfg(); } }); sys.value = cfg.system;
  const modeSel = h("select", { onchange: () => { localStorage.setItem("osvia.amode", modeSel.value); applyMode(); } },
    h("option", { value: "builtin" }, t("内置 AI（免密钥）")), h("option", { value: "custom" }, t("我的模型接口")));
  modeSel.value = useBuiltin() ? "builtin" : "custom";
  const customBox = h("div", {}, field("服务商", prov), field("接口地址", base), field("模型名", model), field("API 密钥", key),
    h("p", { class: "sub small" }, t("密钥只保存在这个浏览器里，发送时经 OSVIA 服务器转发给模型接口，服务器不保存。")));
  const qline = h("span", { class: "sub small" });
  const settings = h("details", { class: "card", open: !useBuiltin() && !cfg.key },
    h("summary", {}, t("设置")), aiOn() ? field("模式", modeSel) : null, customBox, field("系统提示词", sys));
  function applyMode() { customBox.classList.toggle("hidden", useBuiltin()); qline.textContent = useBuiltin() ? quotaText() : ""; }

  const chat = h("div", { class: "chat" });
  const input = h("textarea", { placeholder: t("问点什么…"), rows: "1", "aria-label": t("问点什么…"),
    oninput: () => autosize(),
    onkeydown: (e) => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); } } });
  const btn = h("button", { class: "btn", onclick: () => (S.abort ? S.abort.abort() : send()) }, t("发送"));
  const composer = h("div", { class: "composer" }, input, btn);
  const main = h("div", {}, chat, composer), histBox = h("div", { class: "hidden" });
  function autosize() { input.style.height = "auto"; input.style.height = Math.min(input.scrollHeight, 160) + "px"; }
  const nearBottom = () => window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 180;
  const scrollDown = () => window.scrollTo(0, document.documentElement.scrollHeight);

  const PROMPTS = ["帮我写一封请假邮件", "用三句话解释什么是区块链", "给我一份一周的学习计划", "推荐几个提高专注力的方法"];

  function bubble(m, i, list) {
    const el = h("div", { class: "msg " + (m.role === "user" ? "user" : "ai") });
    if (m.role === "user") { el.textContent = m.content; return el; }
    const live = S.abort && i === list.length - 1;
    if (!m.content && !m.err) { el.append(h("span", { class: "sub" }, t(m.think ? "思考中…" : "正在回答…")), dots()); return el; }
    if (m.content) { const md = h("div", { class: "md" }); md.innerHTML = renderMd(m.content); el.append(md); }
    if (m.err) el.append(h("div", { class: "errline" }, "⚠️ " + m.err));
    if (!live && m.content) {
      el.append(h("div", { class: "mact" },
        h("button", { onclick: () => copyText(m.content) }, t("复制")),
        h("button", { onclick: () => saveAsNote(m.content.split("\n")[0], m.content) }, t("存为笔记")),
        h("button", { onclick: () => pushPhone("OSVIA", m.content) }, t("发到手机")),
        i === list.length - 1 ? h("button", { onclick: regen }, t("重新生成")) : null));
    }
    return el;
  }
  function draw() {
    const list = S.chat.msgs;
    if (!list.length) {
      chat.replaceChildren(h("div", { class: "welcome" }, h("h3", {}, t("有什么可以帮你？")),
        h("div", { class: "chips" }, PROMPTS.map((p) => h("button", { class: "chip", onclick: () => send(t(p)) }, t(p))))));
      return;
    }
    chat.replaceChildren(...list.map(bubble));
  }
  let raf = 0;
  function paint() {
    if (raf) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      if (!document.body.contains(chat)) return;
      const stick = nearBottom();
      const list = S.chat.msgs, i = list.length - 1;
      if (chat.lastChild && i >= 0) chat.lastChild.replaceWith(bubble(list[i], i, list));
      if (stick) scrollDown();
    });
  }
  function setBtn() { btn.textContent = t(S.abort ? "停止" : "发送"); btn.classList.toggle("ghost", !!S.abort); }

  async function stream(builtin, hist, reply, signal) {
    let res;
    if (builtin) {
      res = await api("/api/ai/chat", { method: "POST", body: { messages: hist, system: cfg.system || undefined }, raw: true, signal });
    } else {
      const anth = cfg.kind === "anthropic";
      const b0 = cfg.base.replace(/\/+$/, "");
      const url = anth ? b0 + "/v1/messages" : b0 + "/chat/completions";
      const payload = anth
        ? { model: cfg.model, max_tokens: 4096, stream: true, system: cfg.system || undefined, messages: hist }
        : { model: cfg.model, stream: true, messages: (cfg.system ? [{ role: "system", content: cfg.system }] : []).concat(hist) };
      const headers = anth ? { "x-api-key": cfg.key, "anthropic-version": "2023-06-01" } : { authorization: "Bearer " + cfg.key };
      res = await api("/api/llm", { method: "POST", body: { url, headers, payload }, raw: true, signal });
    }
    if (!res.ok) {
      if (res.status === 401 && builtin) { signOut(true); throw new Error(t("出错了")); }
      let m = ""; try { const j = await res.json(); m = j.message || j.error?.message || JSON.stringify(j.error || j); } catch { /* 非 JSON */ }
      throw new Error(m || "HTTP " + res.status);
    }
    await readSSE(res, (d) => {
      if (builtin) {
        if (d.e) throw new Error(d.e);
        if (d.r && !reply.content && !reply.think) { reply.think = true; paint(); }
        if (d.t) { reply.content += d.t; paint(); }
      } else {
        const piece = cfg.kind === "anthropic" ? (d.type === "content_block_delta" ? d.delta?.text : "") : d.choices?.[0]?.delta?.content;
        if (piece) { reply.content += piece; paint(); }
      }
    });
  }

  async function persist(C) {
    const clean = C.msgs.filter((m) => m.content && !m.err).map((m) => ({ role: m.role, content: m.content }));
    if (!clean.length) return;
    try {
      if (!C.id) C.id = (await api("/api/chats", { method: "POST", body: { title: clean[0].content.replace(/\s+/g, " ").slice(0, 40), msgs: clean } })).id;
      else await api("/api/chats/" + C.id, { method: "PUT", body: { msgs: clean } });
    } catch { /* 云端保存失败不影响继续对话 */ }
  }

  async function send(textArg, regenerating) {
    const text = (textArg ?? input.value).trim();
    if (!text || S.abort) return;
    const builtin = useBuiltin();
    if (!builtin && (!cfg.base || !cfg.model || !cfg.key)) { input.value = text; settings.open = true; return toast(t("先在上面填好模型接口、模型名和密钥。")); }
    if (textArg === undefined) { input.value = ""; autosize(); }
    const C = S.chat;
    if (!regenerating) C.msgs.push({ role: "user", content: text });
    const reply = { role: "assistant", content: "" };
    C.msgs.push(reply);
    const ac = new AbortController();
    S.abort = ac; setBtn(); draw(); scrollDown();
    const hist = C.msgs.filter((m) => !m.err && m.content).slice(-20).map((m) => ({ role: m.role, content: m.content }));
    try {
      await stream(builtin, hist, reply, ac.signal);
      if (!reply.content) reply.err = t("没有收到回复，请重试");
    } catch (e) {
      if (e.name === "AbortError") { if (!reply.content) C.msgs.pop(); }
      else reply.err = e.message || t("出错了");
    }
    if (S.abort === ac) S.abort = null;
    if (document.body.contains(chat)) { setBtn(); draw(); scrollDown(); }
    await persist(C);
    if (builtin) loadQuota().then(() => { if (document.body.contains(qline)) applyMode(); });
  }
  function regen() {
    const C = S.chat;
    if (S.abort || C.msgs.length < 2) return;
    const last = C.msgs[C.msgs.length - 1];
    if (last.role !== "assistant") return;
    C.msgs.pop();
    const u = C.msgs[C.msgs.length - 1];
    if (u && u.role === "user") send(u.content, true);
  }

  async function showHistory() {
    main.classList.add("hidden"); histBox.classList.remove("hidden");
    const list = h("div", {});
    histBox.replaceChildren(h("div", { class: "top" }, h("button", { class: "btn ghost sm", onclick: back }, "‹ " + t("返回对话")), h("h2", {}, t("对话历史")), h("span", {})), list);
    list.append(h("div", { class: "empty" }, t("加载中…")));
    async function load() {
      try {
        const { items } = await api("/api/chats");
        list.replaceChildren(...(items.length ? items.map((c) => h("div", { class: "item go", onclick: async () => {
          try { const r = await api("/api/chats/" + c.id); S.chat = { id: r.id, msgs: r.msgs.map((m) => ({ role: m.role, content: m.content })) }; render(); }
          catch (e) { toast(e.message || t("出错了")); }
        } },
        h("div", { class: "t" }, h("b", {}, c.title || t("无标题")), h("span", { class: "sub small" }, fmtTime(c.updated))),
        h("button", { class: "btn ghost sm", "aria-label": t("删除"), onclick: async (ev) => {
          ev.stopPropagation();
          await api("/api/chats/" + c.id, { method: "DELETE" }).catch(() => {});
          if (S.chat.id === c.id) S.chat = { id: null, msgs: [] };
          load();
        } }, t("删除")))) : [h("div", { class: "empty" }, t("还没有对话"))]));
      } catch (e) { list.textContent = e.message || ""; }
    }
    load();
  }
  function back() { histBox.classList.add("hidden"); main.classList.remove("hidden"); }

  addc(
    h("div", { class: "top" }, h("h2", {}, t("助手")), h("div", {},
      h("button", { class: "btn ghost sm", onclick: () => (S.chat.id ? shareDialog("chat", S.chat.id, S.chat.msgs[0]?.content.replace(/\s+/g, " ").slice(0, 40) || "OSVIA") : toast(t("先聊几句再分享"))) }, t("分享")),
      h("button", { class: "btn ghost sm", onclick: showHistory }, t("历史")),
      h("button", { class: "btn ghost sm", onclick: () => { S.chat = { id: null, msgs: [] }; render(); } }, t("新对话")))),
    h("div", { class: "qline" }, qline),
    settings, main, histBox);
  applyMode(); draw(); setBtn();
  enableDrop(content, (fs) => { input.value = ((input.value ? input.value + "\n\n" : "") + fs.map((f) => `${f.name}:\n${f.text}`).join("\n\n")).slice(0, 12000); autosize(); input.focus(); });
  if (aiOn()) loadQuota().then(() => { if (document.body.contains(qline)) applyMode(); });
  if (S.pendingAsk) { const q = S.pendingAsk; S.pendingAsk = ""; send(q); }
}

// ---------- 账号 ----------
async function viewAccount() {
  const mine = content;
  let counts = S.counts || {};
  try { const r = await api("/api/me"); S.user = r.user; counts = r.counts; } catch { /* 用缓存 */ }
  const name = h("input", { value: S.user.name || "", maxlength: "40" });
  const server = h("input", { placeholder: "https://api.day.app" });
  const bkey = h("input", { type: "password", autocomplete: "off" });
  const benc = h("input", { type: "password", autocomplete: "off" });
  let bark = { server: "", keySet: false, encSet: false };
  try { bark = await api("/api/bark"); } catch { /* 空 */ }
  server.value = bark.server;
  bkey.placeholder = bark.keySet ? t("已设置，留空则不修改") : t("设备密钥（多个用逗号或换行分开）");
  benc.placeholder = bark.encSet ? t("已设置，留空则不修改") : t("加密密钥（可选）");
  const barkMsg = h("p", { class: "small" });
  const say = (el, ok, m) => { el.className = (ok ? "ok" : "err") + " small"; el.textContent = m; };

  const cur = h("input", { type: "password", autocomplete: "current-password" });
  const nw = h("input", { type: "password", autocomplete: "new-password" });
  const pwMsg = h("p", { class: "small" });
  const delPw = h("input", { type: "password", autocomplete: "current-password" });
  const delMsg = h("p", { class: "small" });
  if (aiOn()) await loadQuota();
  if (content !== mine) return; // 等待期间已切到别的页面
  const link = (icon, title, sub, fn) => h("div", { class: "item" + (fn ? " go" : ""), onclick: fn }, svg(icon), h("div", { class: "t" }, h("b", {}, title), h("span", { class: "sub small" }, sub)), fn ? h("span", { class: "sub" }, "›") : null);

  addc(h("h2", {}, t("我的")),
    link("backups", t("云备份"), fmtSize(counts.backupBytes || 0), () => go("me", "backups")),
    aiOn() && S.quota ? link("assistant", t("内置 AI"), `${t("今日已用")} ${S.quota.used}/${S.quota.max}`) : null,
    link("toolbox", t("网页工具箱"), t("剪藏书签 · 分享链接 · 快捷键"), () => go("me", "webtools")),
    h("h3", {}, t("账号信息")),
    h("div", { class: "card" },
      h("p", {}, h("b", {}, S.user.email), " ", h("span", { class: "tag" }, S.user.verified ? t("已验证") : t("未验证"))),
      h("p", { class: "sub small" }, `${t("云端提醒")} ${counts.reminders ?? 0} · ${t("云端笔记")} ${counts.notes ?? 0} · ${t("对话")} ${counts.chats ?? 0} · ${t("云备份占用")} ${fmtSize(counts.backupBytes || 0)}`),
      field("显示名称", name),
      h("button", { class: "btn sm", onclick: async () => { await api("/api/me", { method: "PATCH", body: { name: name.value } }); toast(t("已保存")); } }, t("保存"))),
    langSwitch(),
    h("h3", {}, t("Bark 推送")),
    h("div", { class: "card" }, field("服务器（留空用官方）", server), field("设备密钥（多个用逗号或换行分开）", bkey), field("加密密钥（可选）", benc), barkMsg,
      h("div", { class: "row" },
        h("button", { class: "btn", onclick: async () => {
          const body = { server: server.value.trim() };
          if (bkey.value) body.key = bkey.value; if (benc.value) body.enc = benc.value;
          try { await api("/api/bark", { method: "PUT", body }); say(barkMsg, true, t("已保存")); bkey.value = ""; benc.value = ""; } catch (e) { say(barkMsg, false, e.message || t("出错了")); }
        } }, t("保存")),
        h("button", { class: "btn ghost", onclick: async () => {
          try { await api("/api/bark/test", { method: "POST" }); say(barkMsg, true, t("已发送")); } catch (e) { say(barkMsg, false, e.message || t("出错了")); }
        } }, t("发送测试推送")))),
    h("h3", {}, t("修改密码")),
    h("div", { class: "card" }, field("当前密码", cur), field("新密码", nw), pwMsg,
      h("button", { class: "btn sm", onclick: async () => {
        if (nw.value.length < 8) return say(pwMsg, false, t("密码至少 8 位"));
        try {
          await api("/api/auth/password", { method: "POST", body: { authKey: await authKey(cur.value, S.user.email), newAuthKey: await authKey(nw.value, S.user.email) } });
          cur.value = ""; nw.value = ""; say(pwMsg, true, t("密码已更新"));
        } catch (e) { say(pwMsg, false, e.message || t("出错了")); }
      } }, t("保存"))),
    h("h3", {}, t("导出我的数据")),
    h("div", { class: "card acts" }, h("button", { class: "btn ghost sm", onclick: async () => {
      const [r, n, cl] = await Promise.all([api("/api/reminders"), api("/api/notes"), api("/api/chats")]);
      const chats = [];
      for (let i = 0; i < cl.items.length; i += 8) chats.push(...(await Promise.all(cl.items.slice(i, i + 8).map((c) => api("/api/chats/" + c.id).catch(() => null)))).filter(Boolean));
      const a = h("a", { href: URL.createObjectURL(new Blob([JSON.stringify({ reminders: r.items, notes: n.items, chats }, null, 2)], { type: "application/json" })), download: "osvia-data.json" });
      document.body.append(a); a.click(); a.remove();
    } }, t("导出我的数据")),
    h("button", { class: "btn ghost sm", onclick: async () => {
      if (!confirm(t("删除全部对话") + "?")) return;
      try {
        const { items } = await api("/api/chats");
        for (let i = 0; i < items.length; i += 8) await Promise.all(items.slice(i, i + 8).map((c) => api("/api/chats/" + c.id, { method: "DELETE" }).catch(() => {})));
        S.chat = { id: null, msgs: [] }; toast(t("已删除"));
      } catch (e) { toast(e.message || t("出错了")); }
    } }, t("删除全部对话"))),
    h("div", { class: "card" }, h("button", { class: "btn ghost block", onclick: () => signOut(false) }, t("退出登录"))),
    legalLinks(),
    h("h3", {}, t("删除账号")),
    h("div", { class: "card" }, h("p", { class: "small" }, t("删除账号会清除云端的提醒、笔记和云备份，且无法恢复。输入密码确认：")), delPw, delMsg,
      h("button", { class: "btn danger sm", onclick: async () => {
        try {
          await api("/api/me", { method: "DELETE", body: { authKey: await authKey(delPw.value, S.user.email) } });
          toast(t("已删除")); resetState(); renderAuth();
        } catch (e) { say(delMsg, false, e.message || t("出错了")); }
      } }, t("确定删除"))));
}

if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
// web.js 在 app.js 之后加载，等两个脚本都就绪（DOMContentLoaded 在 defer 脚本之后触发）再启动
document.addEventListener("DOMContentLoaded", start);
