// 网页独有功能的冒烟测试：自动化、动态、分享链接、发到手机。node test/smoke2.mjs <站点地址>
import { pbkdf2Sync } from "node:crypto";
const B = (process.argv[2] || "http://localhost:8787").replace(/\/+$/, "");
const local = /localhost|127\.0\.0\.1/.test(B);
const key = (pw, em) => pbkdf2Sync(pw.normalize("NFKC"), "osvia-auth-v1:" + em.toLowerCase(), 210000, 32, "sha256").toString("base64url");
let tok = "", fails = 0;
async function call(m, p, body) {
  const h = {}; if (tok) h.authorization = "Bearer " + tok;
  let b = body; if (body !== undefined) { b = JSON.stringify(body); h["content-type"] = "application/json"; }
  const r = await fetch(B + p, { method: m, headers: h, body: b });
  let j = {}; try { j = await r.json(); } catch {}
  return { s: r.status, ...j };
}
const ok = (n, c, x) => { console.log((c ? "PASS " : "FAIL ") + n + (c ? "" : " " + JSON.stringify(x))); if (!c) fails++; };
const sql = (q, args) => fetch(B + "/__test/sql", { method: "POST", body: JSON.stringify({ sql: q, args }) });
const setPage = (t) => fetch(B + "/__test/page", { method: "POST", body: t });
const em = `w${Date.now()}@Example.com`, pw = "correct horse 密码";
let r = await call("POST", "/api/auth/register", { email: em, authKey: key(pw, em) });
ok("register", r.s === 200 && r.token, r); tok = r.token;

// ---------- 自动化 ----------
r = await call("GET", "/api/autos"); ok("autos empty", r.s === 200 && r.items?.length === 0 && r.max === 5, r);
r = await call("POST", "/api/autos", { kind: "watch", url: "http://127.0.0.1/x" }); ok("watch ssrf rejected", r.s === 400, r);
r = await call("POST", "/api/autos", { kind: "watch", url: "https://localhost/x" }); ok("watch localhost rejected", r.s === 400, r);
r = await call("POST", "/api/autos", { kind: "brief", prompt: "   " }); ok("brief needs prompt", r.s === 400, r);
r = await call("POST", "/api/autos", { kind: "nope" }); ok("bad kind", r.s === 400, r);
if (local) await setPage("商品价格 100 元。".repeat(20));
r = await call("POST", "/api/autos", { kind: "watch", url: local ? "https://shop.example.com/item" : "https://example.com", title: "测试监控", goal: "价格", period: 60 });
ok("watch create (baseline)", r.s === 200 && r.id, r); const wid = r.id;
r = await call("GET", "/api/autos"); const w = r.items?.find((x) => x.id === wid);
ok("watch listed with baseline", w?.kind === "watch" && w.baseline === true && w.period === 60 && w.enabled && w.url.startsWith("https://"), w);
r = await call("GET", "/api/feed"); ok("feed has start event", r.items?.[0]?.title?.includes("开始监控") && r.unread === 1, r);
r = await call("POST", "/api/feed/seen"); r = await call("GET", "/api/feed"); ok("feed seen", r.unread === 0, r);
r = await call("POST", `/api/autos/${wid}/run`); ok("watch run unchanged", r.s === 200 && r.event === null, r);
if (local) {
  await setPage("商品价格 90 元。".repeat(20));
  r = await call("POST", `/api/autos/${wid}/run`); ok("watch run changed → event", r.s === 200 && r.event?.title?.includes("有更新") && r.event.body.includes("100"), r);
  await setPage("商品价格 90 元。".repeat(20) + " 噪音 访问量 12345");
  r = await call("POST", `/api/autos/${wid}/run`); ok("watch noise → AI says unchanged", r.s === 200 && r.event === null, r);
  await setPage("FAIL");
  for (let i = 1; i <= 5; i++) { r = await call("POST", `/api/autos/${wid}/run`); if (i < 5) ok("watch fail " + i, r.s === 502 && r.error === "run_failed", r); }
  r = await call("GET", "/api/autos"); const w2 = r.items.find((x) => x.id === wid);
  ok("auto-paused after 5 failures", w2.enabled === false && w2.fails === 5 && w2.err.includes("500"), w2);
  r = await call("GET", "/api/feed"); ok("pause event in feed", r.items.some((x) => x.title.includes("已暂停")), r.items.map((x) => x.title));
  await setPage("商品价格 80 元。".repeat(20));
  r = await call("PUT", `/api/autos/${wid}`, { enabled: true }); ok("re-enable", r.s === 200, r);
  r = await call("GET", "/api/autos"); ok("re-enabled resets fails", r.items.find((x) => x.id === wid).fails === 0 && r.items.find((x) => x.id === wid).enabled, r);
}
// 每日简报
r = await call("POST", "/api/reminders", { title: "开会", due: Math.floor(Date.now() / 1000) + 1800, rep: 0 }); ok("reminder for brief", r.s === 200, r);
r = await call("POST", "/api/autos", { kind: "brief", prompt: "总结我今天的安排", hm: "08:30", tz: -480 }); ok("brief create", r.s === 200 && r.id, r); const bid = r.id;
r = await call("GET", "/api/autos"); const b0 = r.items.find((x) => x.id === bid);
const nowS = Date.now() / 1000;
ok("brief next within 24h and at 08:30 CST", b0.next > nowS && b0.next <= nowS + 86400 + 5 && (b0.next + 8 * 3600) % 86400 === 8.5 * 3600, b0);
r = await call("POST", `/api/autos/${bid}/run`); ok("brief run now", r.s === 200 && r.event?.body?.includes("简报"), r);
if (local) {
  ok("brief includes today's reminder", r.event.body.includes("开会"), r);
  await sql("UPDATE autos SET next=1 WHERE id=?", [bid]);
  await fetch(B + "/__test/cron");
  r = await call("GET", "/api/feed"); const n1 = r.items.filter((x) => x.title === "每日简报").length;
  ok("cron ran due brief", n1 >= 2, r.items.map((x) => x.title));
  r = await call("GET", "/api/autos"); ok("cron rescheduled brief to future", r.items.find((x) => x.id === bid).next > nowS, r);
}
r = await call("PUT", `/api/autos/${bid}`, { hm: "21:00", prompt: "新的要求", title: "晚报", enabled: false }); ok("brief edit", r.s === 200, r);
r = await call("GET", "/api/autos"); const b1 = r.items.find((x) => x.id === bid); ok("brief edit applied", b1.hm === "21:00" && b1.prompt === "新的要求" && b1.title === "晚报" && b1.enabled === false, b1);
// 数量上限
let made = 0, lim = null;
for (let i = 0; i < 6; i++) { const x = await call("POST", "/api/autos", { kind: "brief", prompt: "x" + i }); if (x.s === 200) made++; else lim = x; }
ok("autos capped at 5", lim?.error === "limit" && made === 3, { made, lim });
r = await call("GET", "/api/me"); ok("me counts autos", r.counts?.autos === 5, r.counts);
r = await call("DELETE", `/api/autos/${wid}`); ok("auto delete", r.s === 200, r);
r = await call("GET", "/api/feed"); ok("deleting auto removes its events", !r.items.some((x) => x.title.includes("测试监控")), r.items.map((x) => x.title));
r = await call("POST", `/api/autos/${wid}/run`); ok("run deleted auto 404", r.s === 404, r);
r = await call("DELETE", "/api/feed"); r = await call("GET", "/api/feed"); ok("feed cleared", r.items.length === 0, r);

// 线上才测：真实的大页面（HTML 数百 KB），确认不触发 Workers 的 CPU 限制
if (!local) {
  const t0 = Date.now();
  r = await call("POST", "/api/autos", { kind: "watch", url: "https://en.wikipedia.org/wiki/Cloudflare", title: "重页面", period: 1440 });
  ok("heavy page watch baseline (CPU limit)", r.s === 200 && r.id, r);
  console.log("heavy page ms:", Date.now() - t0);
  if (r.id) {
    const r2 = await call("POST", `/api/autos/${r.id}/run`); ok("heavy page re-run", r2.s === 200, r2);
    await call("DELETE", `/api/autos/${r.id}`);
  }
}

// ---------- 分享链接 ----------
r = await call("POST", "/api/notes", { title: "分享测试", body: "# 大标题\n\n正文 **加粗** [链接](https://example.com)\n\n- 条目一\n- 条目二\n\n<script>alert(1)</script> [坏](javascript:alert(1))\n\n```\nlet a = 1 < 2;\n```" });
const nid = r.id; ok("note for share", r.s === 200 && nid, r);
r = await call("POST", "/api/shares", { kind: "note", ref: nid }); ok("share note", r.s === 200 && r.id?.length >= 12, r); const sid = r.id;
let pg = await fetch(B + "/s/" + sid); let html = await pg.text();
ok("share page public 200", pg.status === 200 && html.includes("分享测试") && html.includes("<h3>大标题</h3>") && html.includes("<b>加粗</b>") && html.includes("<li>条目二</li>"), html.slice(0, 300));
ok("share page escapes html", html.includes("&lt;script&gt;alert(1)&lt;/script&gt;") && !html.includes("<script") && !/href="javascript/i.test(html) && html.includes("1 &lt; 2"), html.slice(-700));
ok("share page headers", /noindex/.test(pg.headers.get("x-robots-tag") || "") && /default-src 'none'/.test(pg.headers.get("content-security-policy") || "") && /no-store/.test(pg.headers.get("cache-control") || ""), [...pg.headers]);
r = await call("POST", "/api/shares", { kind: "note", ref: nid }); ok("re-share updates same link", r.s === 200 && r.id === sid && r.updated, r);
r = await call("PUT", "/api/notes/" + nid, { title: "改了标题", body: "新内容" }); r = await call("POST", "/api/shares", { kind: "note", ref: nid });
html = await (await fetch(B + "/s/" + sid)).text(); ok("snapshot refreshed on re-share", html.includes("改了标题") && html.includes("新内容"), html.slice(0, 200));
await new Promise((x) => setTimeout(x, 500));
r = await call("GET", "/api/shares"); ok("share list with views", r.items?.length === 1 && r.items[0].views >= 1 && r.items[0].title === "改了标题", r);
r = await call("POST", "/api/chats", { title: "对话分享", msgs: [{ role: "user", content: "你好 <b>x</b>" }, { role: "assistant", content: "**嗨**" }] }); const cid = r.id;
r = await call("POST", "/api/shares", { kind: "chat", ref: cid, days: 7 }); ok("share chat", r.s === 200 && r.id, r); const sid2 = r.id;
html = await (await fetch(B + "/s/" + sid2)).text();
ok("chat share renders both roles + escapes", html.includes("turn u") && html.includes("turn a") && html.includes("&lt;b&gt;x&lt;/b&gt;") && html.includes("<b>嗨</b>"), html.slice(0, 400));
r = await call("POST", "/api/shares", { kind: "note", ref: "nonexist-123456" }); ok("share missing note 404", r.s === 404, r);
r = await call("POST", "/api/shares", { kind: "x", ref: nid }); ok("share bad kind", r.s === 400, r);
if (local) {
  await sql("UPDATE shares SET exp=1 WHERE id=?", [sid2]);
  ok("expired share 404", (await fetch(B + "/s/" + sid2)).status === 404);
}
r = await call("DELETE", "/api/shares/" + sid); ok("revoke share", r.s === 200, r);
ok("revoked share 404", (await fetch(B + "/s/" + sid)).status === 404);
ok("random share id 404", (await fetch(B + "/s/AAAAAAAAAAAA")).status === 404);
tok = ""; r = await call("GET", "/api/shares"); ok("shares need login", r.s === 401, r); r = await call("GET", "/api/autos"); ok("autos need login", r.s === 401, r);
tok = (await call("POST", "/api/auth/login", { email: em, authKey: key(pw, em) })).token;

// ---------- 发到手机 ----------
r = await call("POST", "/api/push", { body: "hi" }); ok("push without bark → no_bark", r.s === 400 && r.error === "no_bark", r);
r = await call("PUT", "/api/bark", { server: "https://api.day.app", key: "abcDEF123", enc: "" }); ok("bark set", r.s === 200, r);
r = await call("POST", "/api/push", { body: "hi", url: "http://insecure.example.com" }); ok("push rejects non-https url", r.s === 400 && r.error === "bad_url", r);
r = await call("POST", "/api/push", { body: "  " }); ok("push needs body", r.s === 400, r);

// ---------- 删除账号清空 ----------
r = await call("POST", "/api/shares", { kind: "note", ref: nid }); const sid3 = r.id;
r = await call("DELETE", "/api/me", { authKey: key(pw, em) }); ok("delete account", r.s === 200, r);
ok("deleted account's share is gone", (await fetch(B + "/s/" + sid3)).status === 404);
console.log(fails ? `FAILS ${fails}` : "ALL PASS"); process.exit(fails ? 1 : 0);
