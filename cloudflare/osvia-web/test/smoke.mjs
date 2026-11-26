// 接口冒烟测试：node test/smoke.mjs <站点地址>。会创建并最后删除一个临时账号。
import { pbkdf2Sync } from "node:crypto";
const B = (process.argv[2] || "http://localhost:8787").replace(/\/+$/, "");
const key = (pw, em) => pbkdf2Sync(pw.normalize("NFKC"), "osvia-auth-v1:" + em.toLowerCase(), 210000, 32, "sha256").toString("base64url");
let tok = "", fails = 0;
async function call(m, p, body, raw) {
  const h = {}; if (tok) h.authorization = "Bearer " + tok;
  let b = body; if (body && !(body instanceof Uint8Array)) { b = JSON.stringify(body); h["content-type"] = "application/json"; }
  const r = await fetch(B + p, { method: m, headers: h, body: b });
  if (raw) return r;
  let j = {}; try { j = await r.json(); } catch {}
  return { s: r.status, ...j };
}
const ok = (n, c, x) => { console.log((c ? "PASS " : "FAIL ") + n + (c ? "" : " " + JSON.stringify(x))); if (!c) fails++; };
const em = `t${Date.now()}@Example.com`, pw = "correct horse 密码";
let r = await call("POST", "/api/auth/register", { email: em, authKey: key(pw, em) });
ok("register", r.s === 200 && r.token, r); tok = r.token;
r = await call("POST", "/api/auth/register", { email: em, authKey: key(pw, em) }); ok("dup register", r.s >= 400, r);
tok = "";
r = await call("POST", "/api/auth/login", { email: em, authKey: key("bad", em) }); ok("bad login", r.s === 401 || r.s === 400, r);
r = await call("POST", "/api/auth/login", { email: em.toUpperCase(), authKey: key(pw, em) }); ok("login case-insens", r.s === 200 && r.token, r); tok = r.token;
r = await call("GET", "/api/me"); ok("me", r.s === 200 && r.user?.email === em.toLowerCase(), r);
r = await call("PATCH", "/api/me", { name: "Tester" }); ok("patch me", r.s === 200, r);
const due = Math.floor(Date.now() / 1000) + 3600;
r = await call("POST", "/api/reminders", { title: "喝水", due, rep: 1 }); ok("add reminder", r.s === 200, r); const rid = r.id;
r = await call("GET", "/api/reminders"); ok("list reminders", r.items?.length === 1 && r.items[0].title === "喝水", r);
r = await call("POST", "/api/relay", { items: [{ ref: "a1", title: "iOS 提醒", body: "x", due: Math.floor(Date.now()/1000) - 5 }, { ref: "a2", title: "未来", body: "", due: due + 100 }] }); ok("relay", r.s === 200 && r.accepted >= 1, r);
r = await call("POST", "/api/relay", { items: [{ ref: "a1", title: "iOS 提醒", body: "x", due: Math.floor(Date.now()/1000) - 5 }] }); ok("relay idempotent", r.s === 200, r);
r = await call("GET", "/api/reminders"); ok("reminders after relay = 2", r.items?.length === 2, r.items?.length);
r = await call("PUT", "/api/reminders/" + rid, { title: "喝温水", due: due + 600, rep: 7 }); ok("edit reminder", r.s === 200, r);
r = await call("GET", "/api/reminders"); const er = r.items?.find((x) => x.id === rid); ok("edit applied", er?.title === "喝温水" && er.due === due + 600 && er.rep === 7 && er.sent === 0, er);
r = await call("PUT", "/api/reminders/" + rid, { title: "   " }); ok("edit empty title rejected", r.s === 400, r);
const iosItem = (await call("GET", "/api/reminders")).items?.find((x) => x.src === "ios");
r = await call("PUT", "/api/reminders/" + (iosItem?.id || "x"), { title: "改" }); ok("ios reminder readonly", r.s === 400 || r.s === 404, r);
r = await call("DELETE", "/api/reminders/" + rid); ok("del reminder", r.s === 200, r);
r = await call("PUT", "/api/bark", { server: "https://api.day.app", key: "abcDEF123", enc: "" }); ok("bark put", r.s === 200, r);
r = await call("GET", "/api/bark"); ok("bark get", r.keySet === true && r.server === "https://api.day.app" && !JSON.stringify(r).includes("abcDEF123"), r);
r = await call("PUT", "/api/bark", { server: "http://127.0.0.1" }); ok("bark ssrf reject", r.s >= 400, r);
r = await call("POST", "/api/notes", { title: "T", body: "B" }); ok("note add", r.s === 200 && r.id, r); const nid = r.id;
r = await call("PUT", "/api/notes/" + nid, { title: "T2", body: "B2" }); ok("note put", r.s === 200, r);
r = await call("GET", "/api/notes"); ok("note list", r.items?.[0]?.title === "T2", r);
r = await call("DELETE", "/api/notes/" + nid); ok("note del", r.s === 200, r);
const enc = new Uint8Array(1000); enc.set([0x4f, 0x53, 0x56, 0x42, 1, 1]); enc.fill(7, 6);
const plain = new Uint8Array(1000); plain.set([0x4f, 0x53, 0x56, 0x42, 1, 0]);
r = await call("PUT", "/api/backups?name=a.osvbackup&device=iPhone", plain); ok("reject plaintext", r.s >= 400 && r.error === "must_encrypt", r);
r = await call("PUT", "/api/backups?name=a.osvbackup&device=iPhone", new Uint8Array([1,2,3])); ok("reject junk", r.s >= 400, r);
r = await call("PUT", "/api/backups?name=a.osvbackup&device=iPhone", enc); ok("upload enc", r.s === 200 && r.id, r); const bid = r.id;
r = await call("GET", "/api/backups"); ok("list backups", r.items?.length === 1 && r.items[0].size === 1000, r);
const dl = await call("GET", "/api/backups/" + bid, null, true); const buf = new Uint8Array(await dl.arrayBuffer()); ok("download same bytes", dl.status === 200 && buf.length === 1000 && buf[5] === 1, dl.status);
r = await call("POST", "/api/llm", { url: "http://127.0.0.1/v1/chat/completions", headers: {}, payload: {} }); ok("llm ssrf reject", r.s >= 400, r);
r = await call("POST", "/api/llm", { url: "https://169.254.169.254/x", headers: {}, payload: {} }); ok("llm metadata reject", r.s >= 400, r);
r = await call("POST", "/api/auth/password", { authKey: key("bad", em), newAuthKey: key("newpass123", em) }); ok("pw change wrong", r.s >= 400, r);
r = await call("POST", "/api/auth/password", { authKey: key(pw, em), newAuthKey: key("newpass123", em) }); ok("pw change", r.s === 200, r);
r = await call("GET", "/api/me"); ok("old session still ok or revoked", r.s === 200 || r.s === 401, r.s);
tok = "";
r = await call("POST", "/api/auth/login", { email: em, authKey: key(pw, em) }); ok("old pw rejected", r.s >= 400, r);
r = await call("POST", "/api/auth/login", { email: em, authKey: key("newpass123", em) }); ok("new pw login", r.s === 200, r); tok = r.token;
r = await call("GET", "/api/me"); ok("me counts", r.counts?.reminders >= 1 && r.counts?.backupBytes === 1000, r);
r = await call("DELETE", "/api/backups/" + bid); ok("del backup", r.s === 200, r);
// ---------- 内置 AI、对话记录 ----------
const local = /localhost|127\.0\.0\.1/.test(B);
async function sse(path, body) {
  const res = await call("POST", path, body, true);
  const text = await res.text();
  const o = { status: res.status, t: "", r: 0, e: null, done: false, raw: text.slice(0, 200) };
  for (const ln of text.split("\n")) {
    if (!ln.startsWith("data:")) continue;
    const d = ln.slice(5).trim();
    if (d === "[DONE]") { o.done = true; continue; }
    try { const j = JSON.parse(d); if (j.t) o.t += j.t; if (j.r) o.r++; if (j.e) o.e = j.e; } catch {}
  }
  return o;
}
const cfg = await (await fetch(B + "/api/config")).json();
ok("config has ai flag", typeof cfg.ai === "boolean", cfg);
if (cfg.ai) {
  r = await call("GET", "/api/ai/quota"); ok("ai quota", r.s === 200 && r.on === true && r.max > 0, r);
  let c = await sse("/api/ai/chat", { messages: [{ role: "user", content: "请只回答一个字：好" }] });
  ok("ai chat stream", c.status === 200 && c.t.length > 0 && c.done && !c.e && !c.t.includes("<think>"), c);
  r = await call("POST", "/api/ai/chat", { messages: [{ role: "assistant", content: "hi" }] }); ok("ai chat needs user msg", r.s === 400, r);
  r = await call("POST", "/api/ai/tool", { tool: "translate", text: "你好，世界", lang: "en" }); ok("ai tool translate", r.s === 200 && r.text?.length > 0 && !r.text.includes("<think>"), r);
  r = await call("POST", "/api/ai/tool", { tool: "nope", text: "x" }); ok("ai tool unknown rejected", r.s === 400, r);
  r = await call("POST", "/api/ai/reminder", { text: "明天下午3点提醒我开会", tz: -480 });
  ok("ai reminder parse", (r.s === 200 && r.reminder?.title && r.reminder.due > Date.now() / 1000) || r.s === 422, r);
  r = await call("POST", "/api/ai/web", { url: "http://127.0.0.1/x" }); ok("ai web ssrf rejected", r.s === 400, r);
  r = await call("POST", "/api/ai/web", { url: "https://localhost/x" }); ok("ai web localhost rejected", r.s === 400, r);
  if (!local) {
    r = await call("POST", "/api/ai/web", { url: "https://example.com" });
    ok("ai web summary", r.s === 200 && r.summary?.length > 0, r);
  }
  r = await call("GET", "/api/ai/quota"); ok("ai quota counted", r.used >= 3, r);
  if (local) {
    c = await sse("/api/ai/chat", { messages: [{ role: "user", content: "hi" }] }); ok("mock: think stripped", c.t === "你好，世界" && c.r >= 1, c);
    c = await sse("/api/ai/chat", { messages: [{ role: "user", content: "旧格式" }] }); ok("mock: legacy stream", c.t === "旧格式", c);
    c = await sse("/api/ai/chat", { messages: [{ role: "user", content: "空回复" }] }); ok("mock: empty stream reports", c.e === "empty", c);
    r = await call("POST", "/api/ai/reminder", { text: "乱码", tz: -480 }); ok("mock: unparsable reminder 422", r.s === 422, r);
    r = await call("POST", "/api/ai/reminder", { text: "明天下午3点提醒我开会", tz: -480 });
    const tomorrow = new Date(Date.now() + 8 * 3600e3 + 86400e3); // 东八区的明天
    const want = Date.UTC(tomorrow.getUTCFullYear(), tomorrow.getUTCMonth(), tomorrow.getUTCDate(), 15, 0) / 1000 - 8 * 3600;
    ok("mock: reminder timezone math", r.s === 200 && r.reminder.due === want && r.reminder.title === "开会", { r, want });
    let blocked = null;
    for (let i = 0; i < 45 && !blocked; i++) { const x = await call("POST", "/api/ai/tool", { tool: "polish", text: "测试" }); if (x.s === 429) blocked = x; }
    ok("ai daily quota enforced", blocked?.error === "ai_user_quota", blocked);
  }
} else {
  r = await call("POST", "/api/ai/chat", { messages: [{ role: "user", content: "hi" }] }); ok("ai off -> 501", r.s === 501, r);
}
r = await call("POST", "/api/chats", { title: "测试对话", msgs: [{ role: "user", content: "你好" }, { role: "assistant", content: "你好！" }, { role: "system", content: "x" }] });
ok("chat create", r.s === 200 && r.id, r); const cid = r.id;
r = await call("GET", "/api/chats"); ok("chat list", r.items?.some((x) => x.id === cid && x.title === "测试对话"), r);
r = await call("GET", "/api/chats/" + cid); ok("chat get (system filtered)", r.msgs?.length === 2 && r.msgs[1].content === "你好！", r);
r = await call("PUT", "/api/chats/" + cid, { title: "改名", msgs: [{ role: "user", content: "再见" }] }); ok("chat put", r.s === 200, r);
r = await call("GET", "/api/chats/" + cid); ok("chat put applied", r.title === "改名" && r.msgs?.length === 1, r);
r = await call("GET", "/api/me"); ok("me counts chats", r.counts?.chats === 1, r.counts);
r = await call("DELETE", "/api/chats/" + cid); ok("chat delete", r.s === 200, r);
r = await call("GET", "/api/chats/" + cid); ok("chat gone", r.s === 404, r);
r = await call("POST", "/api/chats", { title: "删号前", msgs: [] }); ok("chat for deletion test", r.s === 200, r);

r = await call("DELETE", "/api/me", { authKey: key("nope", em) }); ok("delete acct wrong pw", r.s >= 400, r);
r = await call("DELETE", "/api/me", { authKey: key("newpass123", em) }); ok("delete acct", r.s === 200, r);
r = await call("GET", "/api/me"); ok("after delete 401", r.s === 401, r);
r = await call("GET", "/api/reminders"); ok("unauth reminders 401", (tok="", (await call("GET","/api/reminders")).s) === 401, r);
const idx = await fetch(B + "/"); ok("index served", idx.status === 200 && (await idx.text()).includes("app.js"));
console.log(fails ? `FAILS ${fails}` : "ALL PASS"); process.exit(fails ? 1 : 0);
