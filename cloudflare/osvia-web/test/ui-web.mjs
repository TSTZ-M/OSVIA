// 本地真实浏览器测试（依赖 test/entry.js 的 /__test/* 接口）：node test/ui-web.mjs [地址]
import { chromium } from "playwright";
const B = (process.argv[2] || "http://localhost:8787").replace(/\/+$/, "");
const errs = [];
let fails = 0;
const ok = (n, c, x) => { console.log((c ? "PASS " : "FAIL ") + n + (c ? "" : " " + JSON.stringify(x ?? ""))); if (!c) fails++; };
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1280, height: 860 }, locale: "zh-CN", permissions: ["clipboard-read", "clipboard-write"] });
const p = await ctx.newPage();
p.on("console", (m) => { if (m.type() === "error" || m.type() === "warning") errs.push(m.text()); });
p.on("pageerror", (e) => errs.push("PAGEERR " + e.message));
const setPage = (t) => fetch(B + "/__test/page", { method: "POST", body: t });
const text = async (sel) => (await p.textContent(sel)).replace(/\s+/g, " ").trim();
const nav = (n) => p.click(`.nav button:nth-of-type(${n})`);
try {
  await setPage("商品价格 100 元。".repeat(20));
  await p.goto(B + "/", { waitUntil: "load" });
  await p.waitForSelector(".auth");
  await p.click(".seg button:nth-child(2)");
  await p.fill("input[type=email]", `ui${Date.now()}@example.com`);
  const pws = await p.$$("input[type=password]");
  await pws[0].fill("password123"); await pws[1].fill("password123");
  await p.click("button[type=submit]");
  await p.waitForSelector(".tiles");
  const tabs = await p.$$eval(".nav button", (bs) => bs.map((x) => x.textContent.trim()));
  ok("6 tabs incl. 自动化", tabs.join() === "首页,助手,笔记,自动化,提醒,我的", tabs);
  ok("home 网页独有 tiles", (await text(".main")).includes("网页独有") && (await text(".main")).includes("网页工具箱"));

  // ---- 笔记：双栏 + 自动保存 + 切换不丢 ----
  await nav(3); await p.waitForSelector(".notes-split");
  ok("two-pane layout", !!(await p.$(".notes-list")) && !!(await p.$(".notes-edit")));
  ok("placeholder shown", (await text(".notes-edit")).includes("选择或新建"));
  await p.click(".notes-list button:has-text('新建')");
  await p.waitForSelector(".note-title");
  await p.fill(".note-title", "周报 <b>x</b>");
  await p.fill(".note-body", "第一行\n**重点** 内容 <script>alert(1)</script>");
  await p.click(".notes-list button:has-text('新建')"); // 立刻再建一条：上一条必须已保存
  await p.waitForFunction(() => document.querySelector(".note-title")?.value === "");
  await p.fill(".note-title", "第二条");
  await p.waitForTimeout(1200);
  const items = await p.$$eval(".notes-items .item b", (e) => e.map((x) => x.textContent));
  ok("both notes listed", items.includes("周报 <b>x</b>") && items.includes("第二条"), items);
  await p.click(".notes-items .item:has-text('周报')");
  await p.waitForFunction(() => document.querySelector(".note-title")?.value.startsWith("周报"));
  ok("quick switch kept body", (await p.inputValue(".note-body")).includes("重点"));
  // 切走标签前的待保存内容
  await p.fill(".note-body", "改过的内容 ABC");
  await nav(1); await p.waitForSelector(".tiles");
  await nav(3); await p.waitForSelector(".notes-split");
  await p.click(".notes-items .item:has-text('周报')");
  await p.waitForFunction(() => document.querySelector(".note-body")?.value.includes("ABC"), null, { timeout: 4000 }).catch(() => {});
  ok("edit survived leaving tab", (await p.inputValue(".note-body")).includes("ABC"), await p.inputValue(".note-body"));

  // ---- 分享 ----
  await p.click(".notes-edit button:has-text('分享')");
  await p.waitForSelector(".modal");
  await p.click(".modal button:has-text('生成链接')");
  await p.waitForSelector(".modal input[readonly]");
  const url = await p.inputValue(".modal input[readonly]");
  ok("share url", /\/s\/[\w-]{8,}$/.test(url), url);
  const sp = await ctx.newPage();
  const resp = await sp.goto(url);
  const html = await sp.content();
  ok("share page 200 + content", resp.status() === 200 && html.includes("改过的内容 ABC"));
  ok("share page escapes", !html.includes("<script>alert") && html.includes("&lt;b&gt;x&lt;/b&gt;"));
  ok("share csp", (resp.headers()["content-security-policy"] || "").includes("default-src 'none'") && /noindex/.test(resp.headers()["x-robots-tag"] || html));
  await p.click(".modal button:has-text('撤回')");
  await p.waitForTimeout(400);
  const r404 = await sp.goto(url);
  ok("revoked → 404", r404.status() === 404);
  await sp.close();
  await p.keyboard.press("Escape");
  ok("esc closes modal", !(await p.$(".modal")));

  // ---- 命令面板 ----
  await p.keyboard.press("Control+k");
  await p.waitForSelector(".modal.pal input");
  ok("palette opens, focused", await p.evaluate(() => document.activeElement?.tagName === "INPUT"));
  await p.keyboard.type("周报");
  await p.waitForTimeout(500);
  const rows = await p.$$eval(".pal-row .pal-t", (e) => e.map((x) => x.textContent));
  ok("palette finds note + ask AI", rows.some((r) => r.includes("周报")) && rows.some((r) => r.startsWith("问 AI")), rows);
  await p.keyboard.press("Enter");
  await p.waitForFunction(() => document.querySelector(".note-title")?.value.startsWith("周报"));
  ok("palette opened note", !(await p.$(".modal")));
  await p.keyboard.press("Control+k"); await p.keyboard.type("自动化"); await p.keyboard.press("Enter");
  await p.waitForSelector(".nav button.on[data-tab=auto]");
  ok("palette jump to auto", true);

  // ---- 自动化 ----
  await p.waitForSelector(".main .empty:has-text('还没有自动化')");
  ok("auto page: empty + form", (await text(".main")).includes("新建") && (await text(".main")).includes("0/5"));
  await p.fill(".main input[type=url]", "https://shop.example.com/item");
  await p.fill(".main input:not([type=url]):not([type=time])", "价格");
  await p.click(".main button:has-text('添加')");
  await p.waitForSelector(".card.auto", { timeout: 15000 });
  ok("watch created", (await text(".card.auto")).includes("shop.example.com"));
  ok("start event in feed", (await text(".main")).includes("开始监控"));
  await setPage("商品价格 90 元。".repeat(20));
  await p.click(".card.auto button:has-text('立即运行')");
  await p.waitForFunction(() => document.body.textContent.includes("价格从 100 降到 90"), null, { timeout: 15000 });
  ok("change event rendered", true);
  // 简报
  await p.click(".chips .chip:has-text('每日简报')");
  await p.click(".chips .chip:has-text('每天学一个')");
  await p.click(".main button:has-text('添加')");
  await p.waitForFunction(() => document.querySelectorAll(".card.auto").length === 2, null, { timeout: 15000 });
  ok("brief created", (await text(".main")).includes("每日简报"));
  // 开关
  await p.click(".card.auto:nth-of-type(1) .switch");
  await p.waitForTimeout(600);
  ok("toggle off → dims", (await p.$$(".card.auto.off")).length === 1);
  // 角标：离开再回首页，动态已读
  await nav(1); await p.waitForSelector(".tiles");
  ok("no unread badge after viewing", !(await p.$(".nav .badge")));

  // ---- 剪藏 ----
  await p.goto(B + "/#clip?u=" + encodeURIComponent("https://shop.example.com/item") + "&ti=" + encodeURIComponent("示例商品") + "&t=" + encodeURIComponent("选中的一句话"));
  await p.reload(); await p.waitForSelector(".card input[type=url]");
  ok("clip view prefilled", (await p.inputValue(".card input[type=url]")) === "https://shop.example.com/item" && (await p.inputValue(".card input:not([type=url])")) === "示例商品");
  await p.click("button:has-text('仅存为笔记')");
  await p.waitForSelector(".notes-split");
  await p.waitForFunction(() => document.querySelector(".note-body")?.value.includes("选中的一句话"), null, { timeout: 5000 });
  ok("clip saved as note", (await p.inputValue(".note-body")).includes("https://shop.example.com/item"), await p.inputValue(".note-body"));
  ok("clip cleared from url", !(p.url().includes("clip")));

  // ---- 拖文件导入 ----
  await p.evaluate(() => {
    const dt = new DataTransfer();
    dt.items.add(new File(["导入的正文\n第二行"], "会议记录.md", { type: "text/markdown" }));
    dt.items.add(new File([new Uint8Array(10)], "pic.png", { type: "image/png" }));
    const ev = (t) => new DragEvent(t, { dataTransfer: dt, bubbles: true, cancelable: true });
    const m = document.querySelector(".main");
    m.dispatchEvent(ev("dragenter")); m.dispatchEvent(ev("dragover")); m.dispatchEvent(ev("drop"));
  });
  await p.waitForFunction(() => document.querySelector(".note-title")?.value === "会议记录", null, { timeout: 5000 });
  ok("dropped file imported", (await p.inputValue(".note-body")).includes("第二行"));
  ok("non-text file rejected with toast", (await p.$$eval(".toast", (e) => e.map((x) => x.textContent).join())).includes("pic.png"));

  // ---- 网页工具箱 + 助手分享 ----
  await nav(6); await p.waitForSelector(".item:has-text('网页工具箱')");
  await p.click(".item:has-text('网页工具箱')");
  await p.waitForSelector("a.bm");
  ok("bookmarklet href", ((await p.getAttribute("a.bm", "href")) || "").startsWith("javascript:"));
  ok("share list empty/ok", (await text(".main")).includes("我的分享链接"));
  await nav(2); await p.waitForSelector(".composer textarea");
  await p.click(".top button:has-text('分享')");
  ok("share before chat → toast", !!(await p.waitForSelector(".toast", { timeout: 3000 })));
  await p.fill(".composer textarea", "你好");
  await p.click(".composer .btn");
  await p.waitForFunction(() => { const m = document.querySelector(".msg.ai"); return m && m.querySelector(".mact"); }, null, { timeout: 15000 });
  ok("assistant has 发到手机", (await text(".msg.ai .mact")).includes("发到手机"));
  await p.waitForTimeout(800);
  await p.click(".top button:has-text('分享')");
  await p.click(".modal button:has-text('生成链接')");
  await p.waitForSelector(".modal input[readonly]");
  const curl = await p.inputValue(".modal input[readonly]");
  const cp = await ctx.newPage(); const cr = await cp.goto(curl);
  ok("chat share page", cr.status() === 200 && (await cp.content()).includes("你好，世界"));
  await cp.close();
  await p.keyboard.press("Escape");

  // ---- 手机宽度：单栏 ----
  await p.setViewportSize({ width: 390, height: 844 });
  await nav(3); await p.waitForSelector(".notes-list");
  ok("mobile: single pane", !(await p.$(".notes-split")));
  await p.click(".notes-items .item >> nth=0");
  await p.waitForSelector(".note-title");
  ok("mobile: back button", !!(await p.$("button:has-text('返回')")));
  const navw = await p.$$eval(".nav button", (bs) => bs.map((x) => Math.round(x.getBoundingClientRect().width)));
  ok("mobile nav fits 6 tabs", navw.length === 6 && navw.every((w) => w >= 52), navw);
  const overflow = await p.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  ok("mobile: no horizontal scroll", !overflow);
  await p.screenshot({ path: process.env.SHOT ? process.env.SHOT + "/mobile-notes.png" : "/dev/null" }).catch(() => {});
} catch (e) {
  ok("flow", false, String(e.message || e).slice(0, 400));
  await p.screenshot({ path: (process.env.SHOT || "/tmp") + "/fail.png" }).catch(() => {});
}
const bad = errs.filter((e) => !/status of 4\d\d|Failed to load resource/.test(e));
ok("no console errors", bad.length === 0, bad);
await b.close();
console.log(fails ? `FAILS ${fails}` : "ALL PASS");
process.exit(fails ? 1 : 0);
