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
  "还没有设置 Bark：到点时不会有推送。去「账号」里填写 Bark 设备密钥。": "Bark isn't set up, so nothing will be pushed. Add your Bark key in Account.",
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
  "云端提醒": "Reminders", "云端笔记": "Notes", "云备份占用": "Backups",
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
const S = { token: localStorage.getItem("osvia.token") || "", user: null, tab: "reminders", cfg: { mail: false } };

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
  S.token = ""; S.user = null;
  localStorage.removeItem("osvia.token");
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

  mount(h("div", { class: "auth" },
    h("div", { class: "brand" }, h("img", { src: "/icon-192.png", alt: "" }), h("b", {}, "OSVIA")),
    h("div", { class: "seg" },
      h("button", { class: mode === "login" ? "on" : "", onclick: () => renderAuth("login", { email: email.value }) }, t("登录")),
      h("button", { class: mode === "register" ? "on" : "", onclick: () => renderAuth("register", { email: email.value }) }, t("注册"))),
    form,
    h("p", { class: "sub small center" }, t("支持 Gmail、Outlook、iCloud、QQ、网易等任意邮箱。")),
    h("p", { class: "sub small center" }, t("密码不会上传：它只在本机参与计算，服务器只保存校验值。")),
    langSwitch()));
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
const ICONS = {
  reminders: '<path d="M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6V11a6 6 0 1 0-12 0v5l-2 2v1h16v-1z" fill="currentColor"/>',
  notes: '<path d="M6 2h9l5 5v15H6zM14 3.5V8h4.5M9 12h8v1.5H9zm0 3.5h8V17H9z" fill="currentColor"/>',
  backups: '<path d="M19.4 11A7.5 7.5 0 0 0 5 9.6 5 5 0 0 0 6 19.5h12.5a4 4 0 0 0 .9-8.5z" fill="currentColor"/>',
  assistant: '<path d="M4 4h16v12H8l-4 4zm4 4v1.5h8V8zm0 3v1.5h5V11z" fill="currentColor"/>',
  account: '<path d="M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9zm0 2c-4.4 0-8 2.2-8 5v2h16v-2c0-2.8-3.6-5-8-5z" fill="currentColor"/>',
};
const TABS = [["reminders", "提醒"], ["notes", "笔记"], ["backups", "备份"], ["assistant", "助手"], ["account", "账号"]];

function svg(name) {
  const w = document.createElement("span");
  w.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`; // 固定内置图标，不含用户内容
  return w.firstChild;
}

let content;
function render() {
  const nav = h("nav", { class: "nav" },
    h("div", { class: "logo" }, h("img", { src: "/icon-192.png", alt: "" }), "OSVIA"),
    ...TABS.map(([id, label]) => h("button", { class: S.tab === id ? "on" : "", onclick: () => { S.tab = id; render(); } }, svg(id), h("span", {}, t(label)))));
  content = h("main", { class: "main" });
  mount(h("div", { class: "shell" }, nav, content));
  ({ reminders: viewReminders, notes: viewNotes, backups: viewBackups, assistant: viewAssistant, account: viewAccount })[S.tab]();
}

async function start() {
  try { S.cfg = await api("/api/config"); } catch { /* 保持默认 */ }
  if (!S.token) return renderAuth();
  try {
    const r = await api("/api/me");
    S.user = r.user; S.counts = r.counts;
    render();
  } catch { renderAuth(); }
}

// ---------- 提醒 ----------
async function viewReminders() {
  const title = h("input", { placeholder: t("内容"), maxlength: "120" });
  const when = h("input", { type: "datetime-local" });
  const d = new Date(Date.now() + 3600e3); d.setMinutes(0, 0, 0);
  when.value = new Date(d - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  const rep = h("select", {}, h("option", { value: "0" }, t("仅一次")), h("option", { value: "1" }, t("每天")), h("option", { value: "7" }, t("每周")));
  const list = h("div", {});
  const banner = h("div", {});
  content.append(h("h2", {}, t("提醒")), banner,
    h("div", { class: "card" }, field("内容", title), h("div", { class: "row" }, field("时间", when), field("重复", rep)),
      h("button", { class: "btn block", onclick: async () => {
        const due = Math.floor(new Date(when.value).getTime() / 1000);
        if (!title.value.trim() || !due) return;
        try { await api("/api/reminders", { method: "POST", body: { title: title.value, due, rep: Number(rep.value) } }); title.value = ""; load(); }
        catch (e) { toast(e.message || t("出错了")); }
      } }, t("添加提醒"))),
    list);
  async function load() {
    try {
      const [{ items }, b] = await Promise.all([api("/api/reminders"), api("/api/bark")]);
      banner.replaceChildren(b.keySet ? "" : h("div", { class: "banner" }, t("还没有设置 Bark：到点时不会有推送。去「账号」里填写 Bark 设备密钥。")));
      const upcoming = items.filter((r) => !r.sent), done = items.filter((r) => r.sent);
      const row = (r) => h("div", { class: "item" + (r.sent ? " done" : "") },
        h("div", { class: "t" }, h("b", {}, r.title), h("span", { class: "sub small" }, fmtTime(r.due) + (r.rep ? " · " + t(r.rep === 1 ? "每天" : "每周") : ""))),
        r.src === "ios" ? h("span", { class: "tag" }, t("来自 iPhone")) : null,
        h("button", { class: "btn ghost sm", onclick: async () => { await api("/api/reminders/" + r.id, { method: "DELETE" }); load(); } }, t("删除")));
      list.replaceChildren(...[
        upcoming.length ? [h("h3", {}, t("待提醒")), upcoming.map(row)] : h("div", { class: "empty" }, t("还没有提醒")),
        done.length ? [h("h3", {}, t("已提醒")), done.map(row)] : null].flat(Infinity).filter(Boolean));
    } catch (e) { list.textContent = e.message || ""; }
  }
  load();
}

// ---------- 笔记 ----------
async function viewNotes() {
  let notes = [], cur = null, q = "", timer = null;
  const box = h("div", {});
  content.append(box);
  async function load() { try { notes = (await api("/api/notes")).items; } catch (e) { toast(e.message || ""); } list(); }
  function list() {
    cur = null;
    const search = h("input", { placeholder: t("搜索笔记"), value: q, oninput: (e) => { q = e.target.value; draw(); } });
    const out = h("div", {});
    function draw() {
      const s = q.trim().toLowerCase();
      const shown = notes.filter((n) => !s || (n.title + " " + n.body).toLowerCase().includes(s));
      out.replaceChildren(...(shown.length ? shown.map((n) => h("div", { class: "item", onclick: () => edit(n) },
        h("div", { class: "t" }, h("b", {}, n.title || t("无标题")), h("span", { class: "sub small" }, (n.body || "").replace(/\s+/g, " ").slice(0, 80))),
        h("span", { class: "sub small" }, fmtTime(n.updated)))) : [h("div", { class: "empty" }, t("还没有笔记"))]));
    }
    box.replaceChildren(h("div", { class: "top" }, h("h2", {}, t("笔记")), h("button", { class: "btn sm", onclick: async () => {
      const r = await api("/api/notes", { method: "POST", body: { title: "", body: "" } });
      const n = { id: r.id, title: "", body: "", updated: Math.floor(Date.now() / 1000) };
      notes.unshift(n); edit(n);
    } }, "+ " + t("新建"))), h("div", { class: "card" }, search), out);
    draw();
  }
  function edit(n) {
    cur = n;
    const status = h("span", { class: "sub small" });
    const ti = h("input", { class: "note-title", placeholder: t("标题"), value: n.title, maxlength: "200" });
    const bo = h("textarea", { class: "note-body", placeholder: t("写点什么…") });
    bo.value = n.body;
    const save = () => {
      n.title = ti.value; n.body = bo.value;
      clearTimeout(timer);
      timer = setTimeout(async () => {
        try { const r = await api("/api/notes/" + n.id, { method: "PUT", body: { title: n.title, body: n.body } }); n.updated = r.updated; status.textContent = t("已保存"); }
        catch (e) { status.textContent = e.message || ""; }
      }, 700);
    };
    ti.addEventListener("input", save); bo.addEventListener("input", save);
    box.replaceChildren(
      h("div", { class: "top" }, h("button", { class: "btn ghost sm", onclick: () => { clearTimeout(timer); load(); } }, "‹ " + t("返回")),
        h("div", {}, status, h("button", { class: "btn ghost sm", onclick: async () => {
          if (!confirm(t("删除") + "?")) return;
          clearTimeout(timer); await api("/api/notes/" + n.id, { method: "DELETE" }); load();
        } }, t("删除")))), ti, bo);
  }
  load();
}

// ---------- 云备份 ----------
async function viewBackups() {
  const list = h("div", {});
  const file = h("input", { type: "file", accept: ".osvbackup", class: "hidden", onchange: async () => {
    const f = file.files[0]; if (!f) return;
    try { await api("/api/backups?name=" + encodeURIComponent(f.name) + "&device=web", { method: "PUT", body: await f.arrayBuffer() }); toast(t("已保存")); load(); }
    catch (e) { toast(e.message || t("出错了")); }
    file.value = "";
  } });
  content.append(h("div", { class: "top" }, h("h2", {}, t("云备份")), h("button", { class: "btn sm", onclick: () => file.click() }, t("上传备份文件"))), file,
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

// ---------- 助手：浏览器直接和你配置的模型对话（经服务器转发，密钥不入库） ----------
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

function viewAssistant() {
  const cfg = loadJSON("osvia.llm", { provider: "openai", base: PROVIDERS[0][2], kind: "openai", model: "", key: "", system: "" });
  let msgs = loadJSON("osvia.chat", []);
  let abort = null;
  const save = () => localStorage.setItem("osvia.chat", JSON.stringify(msgs.slice(-60)));
  const saveCfg = () => localStorage.setItem("osvia.llm", JSON.stringify(cfg));

  const prov = h("select", { onchange: () => {
    const p = PROVIDERS.find((x) => x[0] === prov.value);
    cfg.provider = p[0]; cfg.kind = p[3]; if (p[2]) cfg.base = p[2]; base.value = cfg.base; saveCfg();
  } }, PROVIDERS.map((p) => h("option", { value: p[0] }, p[0] === "custom" ? t("自定义") : p[1])));
  prov.value = cfg.provider;
  const base = h("input", { value: cfg.base, placeholder: "https://…", oninput: () => { cfg.base = base.value.trim(); saveCfg(); } });
  const model = h("input", { value: cfg.model, oninput: () => { cfg.model = model.value.trim(); saveCfg(); } });
  const key = h("input", { type: "password", value: cfg.key, autocomplete: "off", oninput: () => { cfg.key = key.value.trim(); saveCfg(); } });
  const sys = h("textarea", { oninput: () => { cfg.system = sys.value; saveCfg(); } }); sys.value = cfg.system;
  const chat = h("div", { class: "chat" });
  const input = h("textarea", { placeholder: t("问点什么…"), rows: "1", onkeydown: (e) => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); } } });
  const btn = h("button", { class: "btn", onclick: () => (abort ? abort.abort() : send()) }, t("发送"));

  function bubble(m) {
    const el = h("div", { class: "msg " + (m.role === "user" ? "user" : "ai") });
    if (m.role === "user") el.textContent = m.content; else el.innerHTML = renderMd(m.content); // renderMd 先转义再加标签
    return el;
  }
  function draw() { chat.replaceChildren(...msgs.map(bubble)); window.scrollTo(0, document.body.scrollHeight); }

  async function send() {
    const text = input.value.trim();
    if (!text) return;
    if (!cfg.base || !cfg.model || !cfg.key) return toast(t("先在上面填好模型接口、模型名和密钥。"));
    input.value = "";
    msgs.push({ role: "user", content: text });
    const reply = { role: "assistant", content: "" };
    msgs.push(reply); draw();
    abort = new AbortController(); btn.textContent = t("停止");
    const hist = msgs.slice(0, -1).slice(-20).map((m) => ({ role: m.role, content: m.content }));
    const anth = cfg.kind === "anthropic";
    const base0 = cfg.base.replace(/\/+$/, "");
    const url = anth ? base0 + "/v1/messages" : base0 + "/chat/completions";
    const payload = anth
      ? { model: cfg.model, max_tokens: 4096, stream: true, system: cfg.system || undefined, messages: hist }
      : { model: cfg.model, stream: true, messages: (cfg.system ? [{ role: "system", content: cfg.system }] : []).concat(hist) };
    const headers = anth ? { "x-api-key": cfg.key, "anthropic-version": "2023-06-01" } : { authorization: "Bearer " + cfg.key };
    const el = chat.lastChild;
    try {
      const res = await api("/api/llm", { method: "POST", body: { url, headers, payload }, raw: true, signal: abort.signal });
      if (!res.ok) {
        let m = ""; try { const j = await res.json(); m = j.message || j.error?.message || JSON.stringify(j.error || j); } catch { /* 非 JSON */ }
        throw new Error(m || "HTTP " + res.status);
      }
      const rd = res.body.getReader(), dec = new TextDecoder();
      let buf = "";
      for (;;) {
        const { done, value } = await rd.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        const lines = buf.split("\n"); buf = lines.pop();
        for (const ln of lines) {
          if (!ln.startsWith("data:")) continue;
          const d = ln.slice(5).trim();
          if (!d || d === "[DONE]") continue;
          try {
            const j = JSON.parse(d);
            const piece = anth ? (j.type === "content_block_delta" ? j.delta?.text : "") : j.choices?.[0]?.delta?.content;
            if (piece) { reply.content += piece; el.innerHTML = renderMd(reply.content); }
          } catch { /* 忽略不完整的行 */ }
        }
      }
      if (!reply.content) reply.content = "…";
    } catch (e) {
      if (e.name !== "AbortError") reply.content += (reply.content ? "\n\n" : "") + "⚠️ " + (e.message || t("出错了"));
    }
    abort = null; btn.textContent = t("发送"); save(); draw();
  }

  content.append(h("div", { class: "top" }, h("h2", {}, t("助手")), h("div", {},
    h("button", { class: "btn ghost sm", onclick: () => { const last = [...msgs].reverse().find((m) => m.role === "assistant"); if (last) navigator.clipboard.writeText(last.content).then(() => toast(t("已复制"))); } }, t("复制")),
    h("button", { class: "btn ghost sm", onclick: () => { msgs = []; save(); draw(); } }, t("清空对话")))),
    h("details", { class: "card", open: !cfg.key }, h("summary", {}, t("模型接口")),
      field("服务商", prov), field("接口地址", base), field("模型名", model), field("API 密钥", key), field("系统提示词", sys),
      h("p", { class: "sub small" }, t("密钥只保存在这个浏览器里，发送时经 OSVIA 服务器转发给模型接口，服务器不保存。"))),
    chat, h("div", { class: "composer" }, input, btn));
  draw();
}

// ---------- 账号 ----------
async function viewAccount() {
  const u = S.user;
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

  content.append(h("h2", {}, t("账号")),
    h("h3", {}, t("账号信息")),
    h("div", { class: "card" },
      h("p", {}, h("b", {}, S.user.email), " ", h("span", { class: "tag" }, S.user.verified ? t("已验证") : t("未验证"))),
      h("p", { class: "sub small" }, `${t("云端提醒")} ${counts.reminders ?? 0} · ${t("云端笔记")} ${counts.notes ?? 0} · ${t("云备份占用")} ${fmtSize(counts.backupBytes || 0)}`),
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
    h("div", { class: "card" }, h("button", { class: "btn ghost sm", onclick: async () => {
      const [r, n] = await Promise.all([api("/api/reminders"), api("/api/notes")]);
      const a = h("a", { href: URL.createObjectURL(new Blob([JSON.stringify({ reminders: r.items, notes: n.items }, null, 2)], { type: "application/json" })), download: "osvia-data.json" });
      document.body.append(a); a.click(); a.remove();
    } }, t("导出我的数据"))),
    h("div", { class: "card" }, h("button", { class: "btn ghost block", onclick: () => signOut(false) }, t("退出登录"))),
    h("h3", {}, t("删除账号")),
    h("div", { class: "card" }, h("p", { class: "small" }, t("删除账号会清除云端的提醒、笔记和云备份，且无法恢复。输入密码确认：")), delPw, delMsg,
      h("button", { class: "btn danger sm", onclick: async () => {
        try {
          await api("/api/me", { method: "DELETE", body: { authKey: await authKey(delPw.value, S.user.email) } });
          toast(t("已删除")); S.token = ""; localStorage.removeItem("osvia.token"); renderAuth();
        } catch (e) { say(delMsg, false, e.message || t("出错了")); }
      } }, t("确定删除"))));
}

start();
