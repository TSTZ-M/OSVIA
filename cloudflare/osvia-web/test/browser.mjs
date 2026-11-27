// 真实浏览器检查：node test/browser.mjs <站点地址>。注册临时账号，逐个打开标签，汇总控制台报错与失败请求。
import { chromium } from "playwright";
const B = (process.argv[2] || "http://localhost:8787").replace(/\/+$/, "");
const errs = [], failed = [];
let fails = 0;
const ok = (n, c, x) => { console.log((c ? "PASS " : "FAIL ") + n + (c ? "" : " " + JSON.stringify(x ?? ""))); if (!c) fails++; };
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, locale: "zh-CN" });
const p = await ctx.newPage();
p.on("console", (m) => { if (["error", "warning"].includes(m.type())) errs.push(m.text()); });
p.on("pageerror", (e) => errs.push("PAGEERR " + e.message));
p.on("requestfailed", (r) => failed.push(r.url() + " " + (r.failure()?.errorText || "")));
p.on("response", (r) => { if (r.status() >= 400 && !r.url().includes("/api/")) failed.push(r.status() + " " + r.url()); });
try {
  await p.goto(B + "/", { waitUntil: "load", timeout: 30000 });
  await p.waitForSelector(".auth", { timeout: 15000 });
  ok("landing features", (await p.$$(".feat")).length >= 4);
  ok("login screen", true);
  console.log("welcome text:", (await p.textContent(".auth")).replace(/\s+/g, " ").slice(0, 200));
  await p.click(".seg button:nth-child(2)");
  await p.fill("input[type=email]", `ui${Date.now()}@example.com`);
  const pws = await p.$$("input[type=password]");
  await pws[0].fill("password123"); await pws[1].fill("password123");
  await p.click("button[type=submit]");
  await p.waitForSelector(".tiles, .main", { timeout: 25000 });
  ok("signed in", true);
  const tabs = await p.$$eval(".nav button", (bs) => bs.map((x) => x.textContent.trim()));
  console.log("tabs:", tabs.join(" | "));
  for (let i = 0; i < tabs.length; i++) {
    await p.click(`.nav button:nth-of-type(${i + 1})`);
    await p.waitForTimeout(700);
    const text = (await p.textContent(".main")).replace(/\s+/g, " ").trim();
    ok("tab " + tabs[i] + " has content", text.length > 10, text);
  }
  // 网页独有：命令面板、自动化（服务器真实抓取 example.com 建立基线）
  await p.keyboard.press("Control+k");
  ok("palette opens", !!(await p.waitForSelector(".modal.pal input", { timeout: 5000 }).catch(() => null)));
  await p.keyboard.press("Escape");
  const cfg = await (await fetch(B + "/api/config")).json();
  if (cfg.ai) {
    await p.click(".nav button[data-tab=auto]");
    await p.waitForSelector("input[type=url]");
    await p.fill(".main input[type=url]", "https://example.com");
    await p.click(".main button:has-text('添加')");
    ok("live watch created (real fetch)", !!(await p.waitForSelector(".card.auto", { timeout: 30000 }).catch(() => null)));
    ok("live watch start event", (await p.textContent(".main")).includes("开始监控"));
  }
  // 真实内置 AI：助手发一句话，等回复
  if (cfg.ai) {
    await p.click(".nav button[data-tab=assistant]");
    await p.fill(".composer textarea", "用一句话介绍你自己");
    await p.click(".composer .btn");
    await p.waitForFunction(() => { const m = document.querySelector(".msg.ai"); return m && !m.querySelector(".dots") && m.textContent.trim().length > 0; }, null, { timeout: 90000 });
    const reply = (await p.textContent(".msg.ai")).trim();
    console.log("AI reply:", reply.slice(0, 160));
    ok("real AI chat replied", reply.length > 3 && !(await p.$(".msg.ai .errline")), reply);
  }
} catch (e) {
  ok("flow", false, String(e.message || e));
}
ok("no console errors", errs.length === 0, errs);
ok("no failed requests", failed.length === 0, failed);
await b.close();
console.log(fails ? `FAILS ${fails}` : "ALL PASS");
process.exit(fails ? 1 : 0);
