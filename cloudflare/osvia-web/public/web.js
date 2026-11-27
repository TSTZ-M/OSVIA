// OSVIA 网页版独有的能力（App 里没有，也不该照搬）：
//   自动化与动态（服务器 24 小时替你盯网页/写简报）、分享链接、网页剪藏、⌘K 命令面板、
//   笔记双栏工作台、拖文件导入、一键发到手机。与 app.js 共用全局（先加载 app.js）。

Object.assign(EN, {
  "自动化": "Automations", "动态": "Activity", "网页独有": "Only on the web", "网页工具箱": "Web toolbox", "快速跳转": "Quick jump",
  "交给服务器 24 小时去做：有变化才通知你，手机关机、App 被杀也照常运行。": "Let the server work 24/7 — you're only notified when something changes, even if your phone is off.",
  "我的自动化": "My automations", "新建": "New", "网页监控": "Page watch", "每日简报": "Daily brief",
  "网址": "URL", "关注什么（可留空）": "What to watch for (optional)", "例如：价格、库存、新公告": "e.g. price, stock, announcements",
  "检查频率": "Check every", "每小时": "Hourly", "每 6 小时": "Every 6 hours", "每天": "Daily",
  "写下你想每天收到什么": "What should the brief contain?", "每天几点": "Time of day",
  "总结我今天的安排，并给一条提高效率的建议": "Summarize my day and add one productivity tip", "每天学一个实用的英语表达": "One useful English expression a day", "用一段话鼓励我开始新的一天": "A short pep talk to start my day",
  "添加": "Add", "正在检查网页…": "Checking the page…", "已添加": "Added", "立即运行": "Run now", "编辑": "Edit", "保存": "Save", "没有变化": "No change",
  "上次运行": "Last run", "还没运行过": "Not run yet", "已暂停": "Paused", "已开启": "On", "还没有自动化": "No automations yet",
  "还没有动态": "Nothing yet", "全部已读": "Mark all read", "清空": "Clear", "打开网页": "Open page", "发到手机": "Send to phone", "已发到手机": "Sent to your phone",
  "AI 判断和生成会占用你每天的内置 AI 次数；监控本身不占用。": "AI judging/writing uses your daily built-in AI quota; the watching itself doesn't.",
  "分享": "Share", "分享链接": "Share link", "生成一个公开的只读网页，任何拿到链接的人都能看到当时的内容。随时可以撤回。": "Creates a public read-only page. Anyone with the link can see the content as of now. You can revoke it anytime.",
  "有效期": "Expires", "永久有效": "Never", "7 天": "7 days", "30 天": "30 days", "生成链接": "Create link", "更新快照": "Update snapshot",
  "复制链接": "Copy link", "撤回": "Revoke", "已撤回": "Revoked", "已复制": "Copied", "链接是生成时的快照；改了内容后点「更新快照」。": "The link shows a snapshot; tap “Update snapshot” after editing.",
  "先聊几句再分享": "Chat a bit first", "导出": "Export", "导出全部": "Export all", "导入文件": "Import files", "选择或新建一条笔记": "Pick or create a note",
  "松开即可导入": "Drop to import", "不是文本文件或超过 1 MB": "not a text file or over 1 MB", "已导入": "Imported",
  "搜索或输入命令…": "Search or type a command…", "没有匹配的内容": "No matches", "问 AI：": "Ask AI: ", "笔记": "Notes", "对话": "Chats", "命令": "Command",
  "新建笔记": "New note", "一句话设提醒": "Quick reminder", "新对话": "New chat",
  "网页剪藏": "Web clipper", "存到 OSVIA": "Save to OSVIA", "把上面的按钮拖到浏览器书签栏。之后在任意网页点一下（可先选中文字），就能摘要并存进笔记。": "Drag the button above to your bookmarks bar. Then click it on any page (optionally select text first) to summarize and save to notes.",
  "复制书签代码": "Copy bookmarklet code", "快捷键": "Keyboard shortcuts", "命令面板：搜索笔记、对话，跳转、新建": "Command palette: search notes & chats, jump, create",
  "发送 / 换行": "Send / new line", "把文本文件拖进笔记、AI 工具或助手页即可导入": "Drag text files into Notes, AI tools or Assistant to import",
  "安装为应用": "Install as app", "在 Chrome / Edge 地址栏点「安装」，或 Safari「添加到主屏幕」，可离线打开界面；Android 和桌面 Chrome 安装后还能从系统分享菜单把网页发给 OSVIA。": "Use “Install” in Chrome/Edge or “Add to Home Screen” in Safari to open offline. On Android and desktop Chrome you can also share pages to OSVIA from the system share menu.",
  "我的分享链接": "My share links", "还没有分享链接": "No share links yet", "次查看": "views", "已过期": "Expired", "笔记分享": "Note", "对话分享": "Chat",
  "来源": "Source", "摘要": "Summary", "摘录": "Excerpt", "标题": "Title", "AI 摘要并存为笔记": "AI summary → note", "仅存为笔记": "Save as note", "稍后读（明早 9 点提醒）": "Read later (remind 9 am)",
  "稍后读：": "Read later: ", "已存为笔记": "Saved as note", "已添加提醒": "Reminder added", "要剪藏的网址或文字": "URL or text to clip",
  "选中的文字": "Selected text", "没有可剪藏的内容": "Nothing to clip", "返回": "Back",
  "剪藏书签 · 分享链接 · 快捷键": "Clipper · share links · shortcuts",
});

// ---------- 通用小件 ----------
Object.assign(ICONS, {
  auto: ST('<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/>'),
  share: ST('<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.2 10.8l7.6-3.6M8.2 13.2l7.6 3.6"/>'),
  toolbox: ST('<rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M3 13h18"/>'),
  key: ST('<rect x="3" y="6" width="18" height="12" rx="3"/><path d="M7 10h.01M11 10h.01M15 10h.01M8 14h8"/>'),
});

function modal(title, kids, opts = {}) {
  const prev = document.activeElement;
  const close = () => { ov.remove(); document.removeEventListener("keydown", onKey, true); if (prev && prev.focus) prev.focus(); };
  const onKey = (e) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
  const ov = h("div", { class: "modal " + (opts.cls || ""), role: "dialog", "aria-modal": "true", "aria-label": title, onclick: (e) => { if (e.target === ov) close(); } },
    h("div", { class: "sheet " + (opts.cls || "") }, opts.bare ? null : h("div", { class: "top" }, h("h2", {}, title), h("button", { class: "btn ghost sm", "aria-label": t("关闭"), onclick: close }, "✕")), kids));
  document.addEventListener("keydown", onKey, true);
  document.body.append(ov);
  const first = ov.querySelector("input,textarea,select,button.btn");
  if (first && opts.focus !== false) first.focus();
  return { close, el: ov };
}

function download(name, text, type = "text/markdown") {
  const a = h("a", { href: URL.createObjectURL(new Blob([text], { type: type + ";charset=utf-8" })), download: name });
  document.body.append(a); a.click(); a.remove();
}
const safeName = (s) => (String(s || "").replace(/[\\/:*?"<>|\n\r]+/g, " ").trim().slice(0, 60) || "OSVIA");

async function pushPhone(title, body, url) {
  try { await api("/api/push", { method: "POST", body: { title, body: String(body).replace(/\s+/g, " ").trim().slice(0, 400), url } }); toast(t("已发到手机")); }
  catch (e) { toast(e.message || t("出错了")); }
}

// ---------- 拖文件导入 ----------
const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|html?|xml|ya?ml|log|js|ts|py|swift|java|c|h|cpp|go|rs|rb|php|sh|sql|css|ini|toml|srt|vtt)$/i;
const hasFiles = (e) => e.dataTransfer && [...(e.dataTransfer.types || [])].includes("Files");
async function readTextFile(f) {
  if (f.size > 1e6 || !(f.type.startsWith("text/") || TEXT_EXT.test(f.name))) return null;
  try { return { name: f.name, text: await f.text() }; } catch { return null; }
}
async function readFiles(files) {
  const out = [];
  for (const f of [...files].slice(0, 10)) {
    const x = await readTextFile(f);
    if (x) out.push(x); else toast(`${f.name}：${t("不是文本文件或超过 1 MB")}`);
  }
  return out;
}
function enableDrop(el, onFiles) {
  let n = 0;
  el.dataset.drop = t("松开即可导入");
  el.addEventListener("dragenter", (e) => { if (hasFiles(e)) { e.preventDefault(); n++; el.classList.add("dropping"); } });
  el.addEventListener("dragover", (e) => { if (hasFiles(e)) e.preventDefault(); });
  el.addEventListener("dragleave", () => { if (--n <= 0) { n = 0; el.classList.remove("dropping"); } });
  el.addEventListener("drop", async (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault(); n = 0; el.classList.remove("dropping");
    const files = await readFiles(e.dataTransfer.files);
    if (files.length) onFiles(files);
  });
}

// ---------- 分享链接 ----------
async function shareDialog(kind, ref, title) {
  const days = h("select", {}, [[0, "永久有效"], [7, "7 天"], [30, "30 天"]].map(([v, l]) => h("option", { value: v }, t(l))));
  const out = h("div", {});
  let sid = "";
  const url = () => `${location.origin}/s/${sid}`;
  const btn = h("button", { class: "btn", onclick: make }, t("生成链接"));
  async function make() {
    btn.disabled = true;
    try {
      const r = await api("/api/shares", { method: "POST", body: { kind, ref, days: Number(days.value) } });
      sid = r.id; show(); if (r.updated) toast(t("已保存"));
    } catch (e) { toast(e.message || t("出错了")); }
    btn.disabled = false;
  }
  function show() {
    btn.textContent = t("更新快照");
    const inp = h("input", { readonly: true, value: url(), "aria-label": t("分享链接"), onfocus: (e) => e.target.select() });
    out.replaceChildren(inp,
      h("div", { class: "acts" },
        h("button", { class: "btn sm", onclick: () => copyText(url()) }, t("复制链接")),
        navigator.share ? h("button", { class: "btn ghost sm", onclick: () => navigator.share({ title, url: url() }).catch(() => {}) }, t("分享")) : null,
        h("button", { class: "btn ghost sm", onclick: () => pushPhone(title, url(), url()) }, t("发到手机")),
        h("a", { class: "btn ghost sm", href: url(), target: "_blank", rel: "noopener" }, t("打开网页")),
        h("button", { class: "btn ghost sm", onclick: async () => {
          await api("/api/shares/" + sid, { method: "DELETE" }).catch(() => {});
          sid = ""; out.replaceChildren(); btn.textContent = t("生成链接"); toast(t("已撤回"));
        } }, t("撤回"))),
      h("p", { class: "sub small" }, t("链接是生成时的快照；改了内容后点「更新快照」。")));
  }
  modal(t("分享链接"), [h("p", { class: "sub small" }, t("生成一个公开的只读网页，任何拿到链接的人都能看到当时的内容。随时可以撤回。")), field("有效期", days), out, h("div", { class: "acts" }, btn)]);
  try {
    const ex = (await api("/api/shares")).items.find((s) => s.kind === kind && s.ref === ref);
    if (ex) { sid = ex.id; show(); }
  } catch { /* 没有也没关系 */ }
}

// ---------- ⌘K 命令面板 ----------
async function openPalette() {
  if (!S.user || document.querySelector(".modal.pal")) return;
  const inp = h("input", { placeholder: t("搜索或输入命令…"), "aria-label": t("搜索或输入命令…"), autocomplete: "off", spellcheck: "false", role: "combobox", "aria-expanded": "true" });
  const list = h("div", { class: "pal-list", role: "listbox" });
  const m = modal("", [inp, list], { cls: "pal", bare: true });
  let notes = [], chats = [], sel = 0, rows = [];
  const run = (fn) => () => { m.close(); fn(); };
  const cmds = [
    [t("首页"), "home", "home", () => go("home")], [t("助手"), "assistant", "assistant", () => go("assistant")], [t("笔记"), "notes", "notes", () => go("notes")],
    [t("提醒"), "reminders", "reminders", () => go("reminders")], [t("自动化"), "auto automation watch", "auto", () => go("auto")], [t("我的"), "me account", "me", () => go("me")],
    [t("网页工具箱"), "toolbox share clip bookmarklet", "toolbox", () => go("me", "webtools")],
    [t("新建笔记"), "new note", "notes", async () => { const r = await api("/api/notes", { method: "POST", body: { title: "", body: "" } }); go("notes", null, { openNote: r.id }); }],
    [t("新对话"), "new chat", "assistant", () => { S.chat = { id: null, msgs: [] }; go("assistant"); }],
    ...(aiOn() ? [
      [t("一句话设提醒"), "reminder", "remind", () => go("reminders", null, { focusNl: true })],
      ...Object.entries(TOOL_NAMES).map(([k, v]) => [t(v), "ai tool " + k, k, () => go("home", "tools", { tool: k })]),
    ] : []),
  ];
  function build() {
    const q = inp.value.trim().toLowerCase();
    rows = cmds.filter((c) => !q || (c[0] + " " + c[1]).toLowerCase().includes(q)).map(([label, , icon, fn]) => ({ label, hint: t("命令"), icon, fn }));
    if (q) {
      notes.filter((n) => (n.title + " " + n.body).toLowerCase().includes(q)).slice(0, 6).forEach((n) =>
        rows.push({ label: n.title || t("无标题"), hint: t("笔记"), icon: "notes", fn: () => go("notes", null, { openNote: n.id }) }));
      chats.filter((c) => (c.title || "").toLowerCase().includes(q)).slice(0, 4).forEach((c) =>
        rows.push({ label: c.title || t("无标题"), hint: t("对话"), icon: "assistant", fn: async () => {
          try { const r = await api("/api/chats/" + c.id); S.chat = { id: r.id, msgs: r.msgs.map((x) => ({ role: x.role, content: x.content })) }; go("assistant"); } catch (e) { toast(e.message || ""); }
        } }));
      rows.push({ label: t("问 AI：") + inp.value.trim(), hint: "↵", icon: "assistant", fn: () => go("assistant", null, { pendingAsk: inp.value.trim() }) });
    }
    sel = Math.min(sel, rows.length - 1);
    draw();
  }
  function draw() {
    list.replaceChildren(...(rows.length ? rows.map((r, i) => h("div", { class: "pal-row" + (i === sel ? " on" : ""), role: "option", "aria-selected": String(i === sel), onclick: run(r.fn), onmousemove: () => { if (sel !== i) { sel = i; draw(); } } },
      svg(r.icon), h("span", { class: "pal-t" }, r.label), h("span", { class: "sub small" }, r.hint))) : [h("div", { class: "empty" }, t("没有匹配的内容"))]));
    const on = list.querySelector(".on"); if (on && on.scrollIntoView) on.scrollIntoView({ block: "nearest" });
  }
  inp.addEventListener("input", () => { sel = 0; build(); });
  inp.addEventListener("keydown", (e) => {
    if (e.isComposing) return;
    if (e.key === "ArrowDown") { e.preventDefault(); sel = Math.min(rows.length - 1, sel + 1); draw(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); sel = Math.max(0, sel - 1); draw(); }
    else if (e.key === "Enter" && rows[sel]) { e.preventDefault(); run(rows[sel].fn)(); }
  });
  build();
  const [n, c] = await Promise.allSettled([api("/api/notes"), api("/api/chats")]);
  if (n.status === "fulfilled") notes = n.value.items;
  if (c.status === "fulfilled") chats = c.value.items;
  if (document.body.contains(m.el)) build();
}
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "k" && S.user) { e.preventDefault(); openPalette(); }
});

// ---------- 动态角标 ----------
S.unread = 0;
function paintBadge() {
  const b = document.querySelector('.nav button[data-tab="auto"]');
  if (!b) return;
  b.querySelector(".badge")?.remove();
  if (S.unread > 0) b.append(h("i", { class: "badge", "aria-label": `${S.unread}` }, S.unread > 9 ? "9+" : String(S.unread)));
}
let unreadAt = 0;
async function refreshUnread(force) {
  if (!S.user || !aiOn() || (!force && Date.now() - unreadAt < 60000)) return paintBadge();
  unreadAt = Date.now();
  try { S.unread = (await api("/api/feed")).unread || 0; } catch { /* 保持 */ }
  paintBadge();
}
setInterval(() => { if (!document.hidden) refreshUnread(true); }, 5 * 60000);

// ---------- 剪藏：书签小工具 / 系统分享入口 → 摘要并存进笔记 ----------
function readClip() {
  let c = null;
  const h0 = location.hash;
  if (h0.startsWith("#clip?")) { const p = new URLSearchParams(h0.slice(6)); c = { u: p.get("u") || "", ti: p.get("ti") || "", t: p.get("t") || "" }; }
  else {
    const p = new URLSearchParams(location.search);
    if (p.has("u") || p.has("t") || p.has("ti")) c = { u: p.get("u") || "", ti: p.get("ti") || "", t: p.get("t") || "" };
  }
  if (c) history.replaceState(null, "", location.pathname);
  return c;
}
function stashClip() { const c = readClip(); if (c) try { sessionStorage.setItem("osvia.clip", JSON.stringify(c)); } catch { /* 无痕模式 */ } }
function takeClip() {
  let c = readClip();
  if (!c) try { c = JSON.parse(sessionStorage.getItem("osvia.clip")); sessionStorage.removeItem("osvia.clip"); } catch { c = null; }
  if (!c || !(c.u || c.t || c.ti)) return;
  if (!c.u && /^https?:\/\/\S+$/.test((c.t || "").trim())) { c.u = c.t.trim(); c.t = ""; } // 有的 App 把链接放在 text 里
  S.clip = c; S.tab = "home"; S.sub = "clip";
}

function viewClip() {
  const c = S.clip || { u: "", ti: "", t: "" };
  const url = h("input", { type: "url", inputmode: "url", value: c.u, placeholder: "https://…", autocapitalize: "none" });
  const title = h("input", { value: c.ti, maxlength: "200" });
  const text = h("textarea", { class: "short" }); text.value = c.t;
  const msg = h("p", { class: "small" });
  const host = () => { try { return new URL(url.value).hostname; } catch { return ""; } };
  const body = (summary) => [url.value.trim() ? `${t("来源")}：${url.value.trim()}` : "", summary ? `## ${t("摘要")}\n${summary}` : "",
    text.value.trim() ? `## ${t("摘录")}\n${text.value.trim().split("\n").map((l) => "> " + l).join("\n")}` : ""].filter(Boolean).join("\n\n");
  const btns = [];
  async function save(withAI) {
    if (!url.value.trim() && !text.value.trim() && !title.value.trim()) return toast(t("没有可剪藏的内容"));
    btns.forEach((b) => (b.disabled = true));
    msg.className = "sub small"; msg.textContent = t("AI 处理中…");
    try {
      let summary = "", ttl = title.value.trim();
      if (withAI) {
        if (url.value.trim()) { const r = await api("/api/ai/web", { method: "POST", body: { url: url.value.trim() } }); summary = r.summary; ttl = ttl || r.title; }
        else { summary = (await api("/api/ai/tool", { method: "POST", body: { tool: "summarize", text: text.value.trim() } })).text; }
        bump();
      }
      const r = await api("/api/notes", { method: "POST", body: { title: (ttl || host() || text.value.trim().slice(0, 30)).slice(0, 60), body: body(summary) } });
      toast(t("已存为笔记")); S.clip = null; go("notes", null, { openNote: r.id });
    } catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); btns.forEach((b) => (b.disabled = false)); }
  }
  async function later() {
    const d = new Date(); d.setHours(9, 0, 0, 0); if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1);
    try {
      await api("/api/reminders", { method: "POST", body: { title: (t("稍后读：") + (title.value.trim() || host())).slice(0, 120), body: url.value.trim(), due: Math.floor(d.getTime() / 1000), rep: 0 } });
      toast(t("已添加提醒")); S.clip = null; go("reminders");
    } catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); }
  }
  btns.push(
    aiOn() ? h("button", { class: "btn", onclick: () => save(true) }, t("AI 摘要并存为笔记")) : null,
    h("button", { class: aiOn() ? "btn ghost" : "btn", onclick: () => save(false) }, t("仅存为笔记")),
    h("button", { class: "btn ghost", onclick: later }, t("稍后读（明早 9 点提醒）")));
  addc(h("div", { class: "top" }, h("h2", {}, t("网页剪藏")), h("button", { class: "btn ghost sm", onclick: () => { S.clip = null; go("home"); } }, t("关闭"))),
    h("div", { class: "card" }, field("网址", url), field("标题", title), field("选中的文字", text), msg, h("div", { class: "acts stack" }, btns)));
}

// ---------- 网页工具箱：剪藏书签、快捷键、分享链接管理 ----------
async function viewWebTools() {
  const mine = content;
  const code = `javascript:(()=>{var s=String(getSelection()).slice(0,6000);window.open(${JSON.stringify(location.origin)}+'/#clip?'+new URLSearchParams({u:location.href,ti:document.title,t:s}),'_blank')})()`;
  const bm = h("a", { class: "btn bm", draggable: "true", title: "OSVIA" }, "📎 " + t("存到 OSVIA"));
  bm.setAttribute("href", code); // 只放在书签里使用；页面自身的 CSP 会拦截在本页点击
  bm.addEventListener("click", (e) => { e.preventDefault(); toast(t("把上面的按钮拖到浏览器书签栏。之后在任意网页点一下（可先选中文字），就能摘要并存进笔记。")); });
  const shares = h("div", {});
  addc(h("button", { class: "btn ghost sm back", onclick: () => go("me") }, "‹ " + t("返回")), h("h2", {}, t("网页工具箱")),
    h("h3", {}, t("网页剪藏")),
    h("div", { class: "card" }, h("p", {}, bm), h("p", { class: "sub small" }, t("把上面的按钮拖到浏览器书签栏。之后在任意网页点一下（可先选中文字），就能摘要并存进笔记。")),
      h("button", { class: "btn ghost sm", onclick: () => copyText(code) }, t("复制书签代码"))),
    h("h3", {}, t("快捷键")),
    h("div", { class: "card" }, h("p", {}, h("kbd", {}, "⌘/Ctrl"), " + ", h("kbd", {}, "K"), "  ", t("命令面板：搜索笔记、对话，跳转、新建")),
      h("p", {}, h("kbd", {}, "Enter"), " / ", h("kbd", {}, "Shift"), "+", h("kbd", {}, "Enter"), "  ", t("发送 / 换行")),
      h("p", { class: "sub small" }, t("把文本文件拖进笔记、AI 工具或助手页即可导入"))),
    h("h3", {}, t("安装为应用")), h("div", { class: "card" }, h("p", { class: "small" }, t("在 Chrome / Edge 地址栏点「安装」，或 Safari「添加到主屏幕」，可离线打开界面；Android 和桌面 Chrome 安装后还能从系统分享菜单把网页发给 OSVIA。"))),
    h("h3", {}, t("我的分享链接")), shares);
  let items = [];
  try { items = (await api("/api/shares")).items; } catch { /* 空 */ }
  if (content !== mine) return;
  const now = Date.now() / 1000;
  shares.replaceChildren(...(items.length ? items.map((s) => {
    const u = `${location.origin}/s/${s.id}`, dead = s.exp && s.exp < now;
    return h("div", { class: "item col" },
      h("div", { class: "line" }, h("b", { class: "t1" }, s.title || t("无标题")), h("span", { class: "tag" }, t(s.kind === "chat" ? "对话分享" : "笔记分享"))),
      h("div", { class: "sub small" }, `${fmtTime(s.created)} · ${s.views} ${t("次查看")}${s.exp ? " · " + (dead ? t("已过期") : fmtTime(s.exp)) : ""}`),
      h("div", { class: "acts" },
        h("button", { class: "btn ghost sm", onclick: () => copyText(u) }, t("复制链接")),
        h("a", { class: "btn ghost sm", href: u, target: "_blank", rel: "noopener" }, t("打开网页")),
        h("button", { class: "btn ghost sm", onclick: async (ev) => { await api("/api/shares/" + s.id, { method: "DELETE" }).catch(() => {}); ev.target.closest(".item").remove(); toast(t("已撤回")); } }, t("撤回"))));
  }) : [h("div", { class: "empty" }, t("还没有分享链接"))]));
}

// ---------- 自动化与动态 ----------
const PERIODS = { 60: "每小时", 360: "每 6 小时", 1440: "每天" };
const hostOf = (u) => { try { return new URL(u).hostname; } catch { return u; } };

async function viewAuto() {
  const mine = content;
  const feedBox = h("div", {}), listBox = h("div", {}), formBox = h("div", {});
  let max = 5, autos = [];
  addc(h("h2", {}, t("自动化")), h("p", { class: "sub" }, t("交给服务器 24 小时去做：有变化才通知你，手机关机、App 被杀也照常运行。")),
    h("h3", {}, t("动态")), feedBox, h("h3", {}, t("我的自动化")), listBox, h("h3", {}, t("新建")), formBox);

  function eventRow(ev, fresh) {
    const md = h("div", { class: "md" }); md.innerHTML = renderMd(ev.body);
    return h("div", { class: "item col" + (fresh ? " fresh" : "") },
      h("div", {}, h("b", { class: "t1" }, ev.title), h("div", { class: "sub small" }, fmtTime(ev.created))), md,
      h("div", { class: "acts" },
        ev.url ? h("a", { class: "btn ghost sm", href: ev.url, target: "_blank", rel: "noopener noreferrer" }, t("打开网页")) : null,
        h("button", { class: "btn ghost sm", onclick: () => pushPhone(ev.title, ev.body, ev.url) }, t("发到手机")),
        h("button", { class: "btn ghost sm", onclick: () => saveAsNote(ev.title, (ev.url ? ev.url + "\n\n" : "") + ev.body) }, t("存为笔记")),
        h("button", { class: "btn ghost sm", onclick: async (e) => { await api("/api/feed/" + ev.id, { method: "DELETE" }).catch(() => {}); e.target.closest(".item").remove(); } }, t("删除"))));
  }
  async function loadFeed() {
    try {
      const f = await api("/api/feed");
      if (content !== mine) return;
      feedBox.replaceChildren(...(f.items.length ? [
        ...f.items.map((ev) => eventRow(ev, !ev.seen)),
        h("div", { class: "acts" }, h("button", { class: "btn ghost sm", onclick: async () => { await api("/api/feed", { method: "DELETE" }); loadFeed(); } }, t("清空")))]
        : [h("div", { class: "empty" }, t("还没有动态"))]));
      if (f.unread) { api("/api/feed/seen", { method: "POST" }).catch(() => {}); S.unread = 0; paintBadge(); }
    } catch (e) { feedBox.textContent = e.message || ""; }
  }
  const short = (u) => { try { const x = new URL(u); return (x.hostname + x.pathname + x.search).replace(/\/$/, "").slice(0, 60); } catch { return u; } };
  const sched = (a) => a.kind === "brief" ? `${t("每天")} ${a.hm}` : `${short(a.url)} · ${t(PERIODS[a.period] || "每天")}`;
  function autoRow(a) {
    const tz = new Date().getTimezoneOffset();
    const goal = h("input", { value: a.goal, maxlength: "200", placeholder: t("例如：价格、库存、新公告") });
    const prompt = h("textarea", { class: "short", maxlength: "500" }); prompt.value = a.prompt;
    const hm = h("input", { type: "time", value: a.hm || "08:00" });
    const per = h("select", {}, Object.entries(PERIODS).map(([v, l]) => h("option", { value: v }, t(l)))); per.value = String(a.period);
    const msg = h("p", { class: "small" });
    const run = h("button", { class: "btn ghost sm", onclick: async () => {
      run.disabled = true; run.textContent = t("正在检查网页…");
      try { const r = await api(`/api/autos/${a.id}/run`, { method: "POST" }); bump(); toast(r.event ? r.event.title : t("没有变化")); loadFeed(); loadAutos(); }
      catch (e) { toast(e.message || t("出错了")); run.disabled = false; run.textContent = t("立即运行"); }
    } }, t("立即运行"));
    const sw = h("input", { type: "checkbox", checked: a.enabled, "aria-label": a.title, onchange: async () => {
      try { await api("/api/autos/" + a.id, { method: "PUT", body: { enabled: sw.checked } }); loadAutos(); } catch (e) { sw.checked = !sw.checked; toast(e.message || ""); }
    } });
    return h("div", { class: "card auto" + (a.enabled ? "" : " off") },
      h("div", { class: "line" }, h("div", { class: "t" }, h("b", {}, a.title), h("span", { class: "tag" }, t(a.kind === "brief" ? "每日简报" : "网页监控"))), h("label", { class: "switch" }, sw, h("i"))),
      h("div", { class: "sub small" }, sched(a)),
      h("div", { class: "small " + (a.err ? "err" : "sub") }, a.err ? (a.enabled ? "" : t("已暂停") + "：") + a.err : (a.last ? `${t("上次运行")}：${fmtTime(a.last)}` : t("还没运行过"))),
      h("details", {}, h("summary", { class: "small sub" }, t("编辑")),
        a.kind === "watch" ? [field("关注什么（可留空）", goal), field("检查频率", per)] : [field("写下你想每天收到什么", prompt), field("每天几点", hm)], msg,
        h("button", { class: "btn sm", onclick: async () => {
          const body = a.kind === "watch" ? { goal: goal.value, period: Number(per.value) } : { prompt: prompt.value, hm: hm.value, tz };
          try { await api("/api/autos/" + a.id, { method: "PUT", body }); toast(t("已保存")); loadAutos(); } catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); }
        } }, t("保存"))),
      h("div", { class: "acts" }, run, h("button", { class: "btn ghost sm", onclick: async () => {
        if (!confirm(t("删除") + "?")) return;
        await api("/api/autos/" + a.id, { method: "DELETE" }).catch(() => {}); loadAutos(); loadFeed();
      } }, t("删除"))));
  }
  async function loadAutos() {
    try {
      const r = await api("/api/autos");
      if (content !== mine) return;
      autos = r.items; max = r.max;
      listBox.replaceChildren(...(autos.length ? autos.map(autoRow) : [h("div", { class: "empty" }, t("还没有自动化"))]));
      syncForm(); // 只更新计数和按钮状态，不重建表单（否则正在输入的内容会被打断）
    } catch (e) { listBox.textContent = e.message || ""; }
  }
  let kind = "watch", cnt = null, addBtn = null;
  const syncForm = () => { if (cnt) { cnt.textContent = `${autos.length}/${max}`; addBtn.disabled = autos.length >= max; } };
  const f = { url: "", goal: "", period: "1440", prompt: "", hm: "08:00" };
  function drawForm() {
    const msg = h("p", { class: "small" });
    const chips = h("div", { class: "chips" }, [["watch", "网页监控"], ["brief", "每日简报"]].map(([k, l]) => h("button", { class: "chip" + (k === kind ? " on" : ""), onclick: () => { kind = k; drawForm(); } }, t(l))));
    const url = h("input", { type: "url", inputmode: "url", placeholder: "https://…", autocapitalize: "none", value: f.url, oninput: (e) => { f.url = e.target.value; } });
    const goal = h("input", { value: f.goal, maxlength: "200", placeholder: t("例如：价格、库存、新公告"), oninput: (e) => { f.goal = e.target.value; } });
    const per = h("select", { onchange: (e) => { f.period = e.target.value; } }, Object.entries(PERIODS).map(([v, l]) => h("option", { value: v }, t(l)))); per.value = f.period;
    const prompt = h("textarea", { class: "short", maxlength: "500", oninput: (e) => { f.prompt = e.target.value; } }); prompt.value = f.prompt;
    const hm = h("input", { type: "time", value: f.hm, oninput: (e) => { f.hm = e.target.value; } });
    const add = h("button", { class: "btn", onclick: async () => {
      add.disabled = true; msg.className = "sub small"; msg.textContent = kind === "watch" ? t("正在检查网页…") : "…";
      try {
        const body = kind === "watch" ? { kind, url: f.url, goal: f.goal, period: Number(f.period) } : { kind, prompt: f.prompt, hm: f.hm, tz: new Date().getTimezoneOffset() };
        await api("/api/autos", { method: "POST", body });
        toast(t("已添加")); Object.assign(f, { url: "", goal: "", prompt: "" }); drawForm(); loadAutos(); loadFeed();
      } catch (e) { msg.className = "err small"; msg.textContent = e.message || t("出错了"); add.disabled = false; }
    } }, t("添加"));
    formBox.replaceChildren(h("div", { class: "card" }, chips,
      kind === "watch" ? [field("网址", url), field("关注什么（可留空）", goal), field("检查频率", per)]
        : [field("写下你想每天收到什么", prompt),
          h("div", { class: "chips" }, ["总结我今天的安排，并给一条提高效率的建议", "每天学一个实用的英语表达", "用一段话鼓励我开始新的一天"].map((p) => h("button", { class: "chip", onclick: () => { f.prompt = t(p); prompt.value = f.prompt; } }, t(p)))),
          field("每天几点", hm)],
      msg, h("div", { class: "acts" }, cnt = h("span", { class: "sub small" }), add),
      h("p", { class: "sub small" }, t("AI 判断和生成会占用你每天的内置 AI 次数；监控本身不占用。"))));
    addBtn = add; syncForm();
  }
  drawForm();
  await Promise.all([loadFeed(), loadAutos()]);
  refreshUnread(true);
}

// ---------- 首页里的「网页独有」入口与动态预览 ----------
function homeExtras() {
  const feed = h("div", {});
  const tile = (icon, label, fn) => h("button", { class: "tile", onclick: fn }, svg(icon), h("span", {}, t(label)));
  if (aiOn()) api("/api/feed").then((f) => {
    S.unread = f.unread || 0; paintBadge();
    const fresh = f.items.filter((e) => !e.seen).slice(0, 2);
    if (fresh.length && document.body.contains(feed)) feed.replaceChildren(h("h3", {}, t("动态")), ...fresh.map((e) => h("div", { class: "item go fresh", onclick: () => go("auto") },
      h("div", { class: "t" }, h("b", {}, e.title), h("span", { class: "sub small" }, e.body.replace(/\s+/g, " ").slice(0, 70))), h("span", { class: "sub small" }, fmtTime(e.created)))));
  }).catch(() => {});
  return [feed, h("h3", {}, t("网页独有")),
    h("div", { class: "tiles" }, aiOn() ? tile("auto", "自动化", () => go("auto")) : null, tile("toolbox", "网页工具箱", () => go("me", "webtools")), tile("key", "快速跳转", openPalette))];
}

// ---------- 笔记：桌面双栏工作台 + 分享 / 发到手机 / 导出 / 拖文件导入 ----------
async function viewNotes() {
  const wide = matchMedia("(min-width: 900px)").matches;
  let notes = [], cur = null, q = "", timer = null, pending = null, drawItems = () => {};
  const listCol = h("div", { class: "notes-list" }), editCol = h("div", { class: "notes-edit" });
  const box = wide ? h("div", { class: "notes-split" }, listCol, editCol) : listCol;
  addc(box);
  const flush = () => { if (pending) { clearTimeout(timer); const p = pending; pending = null; return p(); } };
  S.flush = flush;
  const placeholder = () => editCol.replaceChildren(h("div", { class: "empty" }, t("选择或新建一条笔记")));

  async function load() {
    try { notes = (await api("/api/notes")).items; } catch (e) { toast(e.message || ""); }
    list();
    const id = S.openNote; S.openNote = null;
    const n = id && notes.find((x) => x.id === id);
    if (n) edit(n); else if (wide && !cur) placeholder();
  }
  async function create(title = "", body = "") {
    const r = await api("/api/notes", { method: "POST", body: { title, body } });
    const n = { id: r.id, title, body, updated: Math.floor(Date.now() / 1000) };
    notes.unshift(n); return n;
  }
  function list() {
    if (!wide) cur = null;
    const search = h("input", { placeholder: t("搜索笔记"), value: q, oninput: (e) => { q = e.target.value; drawItems(); } });
    const out = h("div", { class: "notes-items" });
    drawItems = () => {
      const s = q.trim().toLowerCase();
      const shown = notes.filter((n) => !s || (n.title + " " + n.body).toLowerCase().includes(s));
      out.replaceChildren(...(shown.length ? shown.map((n) => h("div", { class: "item go" + (cur && cur.id === n.id ? " active" : ""), onclick: () => edit(n) },
        h("div", { class: "t" }, h("b", {}, n.title || t("无标题")), h("span", { class: "sub small" }, (n.body || "").replace(/\s+/g, " ").slice(0, 80))),
        wide ? null : h("span", { class: "sub small" }, fmtTime(n.updated)))) : [h("div", { class: "empty" }, t("还没有笔记"))]));
    };
    const pick = h("input", { type: "file", multiple: true, class: "hidden", accept: ".txt,.md,.markdown,.csv,.json,.html,.xml,.yml,.yaml,.log,text/*", onchange: async (e) => { await importFiles(await readFiles(e.target.files)); e.target.value = ""; } });
    listCol.replaceChildren(h("div", { class: "top" }, h("h2", {}, t("笔记")), h("div", {},
      h("button", { class: "btn ghost sm", onclick: () => pick.click() }, t("导入文件")),
      notes.length ? h("button", { class: "btn ghost sm", onclick: () => download("OSVIA-notes.md", notes.map((n) => `# ${n.title || t("无标题")}\n\n${n.body}`).join("\n\n---\n\n")) }, t("导出全部")) : null,
      h("button", { class: "btn sm", onclick: async () => { await flush(); edit(await create()); drawItems(); } }, "+ " + t("新建")))), pick, h("div", { class: "card" }, search), out);
    drawItems();
  }
  async function importFiles(files) {
    let last = null;
    for (const f of files) last = await create(f.name.replace(/\.[^.]+$/, ""), f.text.slice(0, 100000));
    if (last) { toast(`${t("已导入")} ${files.length}`); list(); edit(last); }
  }
  enableDrop(content, importFiles);

  async function edit(n) {
    await flush();
    cur = n;
    const status = h("span", { class: "sub small" });
    const ti = h("input", { class: "note-title", placeholder: t("标题"), value: n.title, maxlength: "200" });
    const bo = h("textarea", { class: "note-body", placeholder: t("写点什么…") });
    bo.value = n.body;
    const doSave = async () => {
      try { const r = await api("/api/notes/" + n.id, { method: "PUT", body: { title: n.title, body: n.body } }); n.updated = r.updated; status.textContent = t("已保存"); drawItems(); }
      catch (e) { status.textContent = e.message || ""; }
    };
    const save = () => {
      n.title = ti.value; n.body = bo.value; status.textContent = "";
      pending = doSave; clearTimeout(timer);
      timer = setTimeout(() => { pending = null; doSave(); }, 700);
    };
    ti.addEventListener("input", save); bo.addEventListener("input", save);
    const aiBox = h("div", {});
    const nlang = h("select", { class: "sm-sel", "aria-label": t("译成"), onchange: (e) => { S.tlang = e.target.value; } }, LANGS.map(([v, l]) => h("option", { value: v }, l)));
    nlang.value = S.tlang || (LANG === "zh" ? "en" : "zh");
    async function runAi(tool) {
      const s0 = bo.selectionStart, e0 = bo.selectionEnd;
      const sel = s0 !== e0 ? bo.value.slice(s0, e0) : "";
      const orig = (tool === "titleize" ? bo.value : sel || bo.value).trim();
      if (!orig) return toast(t("先写点内容"));
      aiBox.replaceChildren(h("div", { class: "card thinking" }, t("AI 处理中…"), dots()));
      try {
        const r = await api("/api/ai/tool", { method: "POST", body: { tool, text: orig.slice(0, 12000), lang: nlang.value } });
        bump();
        const out = String(r.text).trim();
        const put = (v) => { bo.value = v; bo.dispatchEvent(new Event("input")); aiBox.replaceChildren(); };
        const tail = () => bo.value.replace(/\s*$/, "") + "\n\n" + out;
        const replace = () => {
          if (orig.length > 12000) return tail(); // 超长时只处理了前半部分，不能整篇覆盖
          if (sel) return bo.value.slice(s0, e0) === sel ? bo.value.slice(0, s0) + out + bo.value.slice(e0) : tail();
          return bo.value.trim() === orig ? out : tail();
        };
        const md = h("div", { class: "md" }); md.innerHTML = renderMd(out);
        aiBox.replaceChildren(h("div", { class: "card result" }, md, h("div", { class: "acts" },
          tool === "titleize"
            ? h("button", { class: "btn sm", onclick: () => { ti.value = out.replace(/^["“「『]+|["”」』。.]+$/g, "").slice(0, 60); ti.dispatchEvent(new Event("input")); aiBox.replaceChildren(); } }, t("用作标题"))
            : [tool === "polish" || tool === "translate" ? h("button", { class: "btn sm", onclick: () => put(replace()) }, t("替换原文")) : null,
              h("button", { class: "btn ghost sm", onclick: () => put(tail()) }, t("插入末尾"))],
          h("button", { class: "btn ghost sm", onclick: () => copyText(out) }, t("复制")),
          h("button", { class: "btn ghost sm", onclick: () => aiBox.replaceChildren() }, t("关闭")))));
      } catch (er) { aiBox.replaceChildren(h("div", { class: "card err" }, er.message || t("出错了"))); }
    }
    const tb = aiOn() ? h("div", { class: "chips ai" }, [["summarize", "总结"], ["polish", "润色"], ["translate", "翻译"], ["continue", "续写"], ["todos", "提取待办"], ["titleize", "起标题"]]
      .map(([k, l]) => [h("button", { class: "chip", onclick: () => runAi(k) }, "✦ " + t(l)), k === "translate" ? nlang : null])) : null;
    const acts = h("div", { class: "acts" }, status,
      h("button", { class: "btn ghost sm", onclick: async () => { await flush(); shareDialog("note", n.id, n.title || t("无标题")); } }, t("分享")),
      h("button", { class: "btn ghost sm", onclick: () => pushPhone(n.title || "OSVIA", n.body || n.title || "") }, t("发到手机")),
      h("button", { class: "btn ghost sm", onclick: () => download(safeName(n.title) + ".md", `# ${n.title || ""}\n\n${n.body}\n`) }, t("导出")),
      h("button", { class: "btn ghost sm", onclick: async () => {
        if (!confirm(t("删除") + "?")) return;
        pending = null; clearTimeout(timer);
        await api("/api/notes/" + n.id, { method: "DELETE" }).catch(() => {});
        notes = notes.filter((x) => x.id !== n.id); cur = null;
        if (wide) { placeholder(); drawItems(); } else load();
      } }, t("删除")));
    const head = wide ? h("div", { class: "top" }, h("span", {}), acts)
      : h("div", { class: "top" }, h("button", { class: "btn ghost sm", onclick: async () => { await flush(); load(); } }, "‹ " + t("返回")), acts);
    (wide ? editCol : box).replaceChildren(head, ti, tb, aiBox, bo);
    if (wide) drawItems();
  }
  load();
}
