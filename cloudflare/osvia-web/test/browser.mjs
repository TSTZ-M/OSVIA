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
  ok("login screen", true);
  console.log("welcome text:", (await p.textContent(".auth")).replace(/\s+/g, " ").slice(0, 200));
  await p.click(".seg button:nth-child(2)");
  await p.fill("input[type=email]", `ui${Date.now()}@example.com`);
  const pws = await p.$$("input[type=password]");
  await pws[0].fill("password123"); await pws[1].fill("password123");
  await p.click("button[type=submit]");
  await p.waitForSelector(".main", { timeout: 25000 });
  ok("signed in", true);
  const tabs = await p.$$eval(".nav button", (bs) => bs.map((x) => x.textContent.trim()));
  console.log("tabs:", tabs.join(" | "));
  for (let i = 0; i < tabs.length; i++) {
    await p.click(`.nav button:nth-child(${i + 2})`);
    await p.waitForTimeout(700);
    const text = (await p.textContent(".main")).replace(/\s+/g, " ").trim();
    ok("tab " + tabs[i] + " has content", text.length > 10, text);
  }
} catch (e) {
  ok("flow", false, String(e.message || e));
}
ok("no console errors", errs.length === 0, errs);
ok("no failed requests", failed.length === 0, failed);
await b.close();
console.log(fails ? `FAILS ${fails}` : "ALL PASS");
process.exit(fails ? 1 : 0);
