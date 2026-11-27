// 测试入口：给真实 Worker 注入假的 AI 绑定和假的网页抓取（本地 wrangler dev 无法使用线上 Workers AI，也不该依赖外网）
import worker from "../src/index.js";
import mock from "./mock-ai.js";
let PAGE = "初始内容。".repeat(30); // 通过 /__test/page 修改，模拟网页变化
const fakeFetchPage = async (url) => {
  if (PAGE === "FAIL") throw Object.assign(new Error("http"), { bad: "网页返回了 500" });
  return { title: "测试页", text: PAGE, url: url.href };
};
const wrap = (env) => ({ ...env, AI: mock, PAGE_FETCH: fakeFetchPage });
export default {
  async fetch(req, env, ctx) {
    const u = new URL(req.url);
    if (u.pathname === "/__test/page" && req.method === "POST") { PAGE = await req.text(); return new Response("ok"); }
    if (u.pathname === "/__test/sql" && req.method === "POST") { const b = await req.json(); await env.DB.prepare(b.sql).bind(...(b.args || [])).run(); return new Response("ok"); }
    if (u.pathname === "/__test/cron") { await worker.scheduled({ scheduledTime: Date.now() }, wrap(env), ctx); return new Response("ok"); }
    return worker.fetch(req, wrap(env), ctx);
  },
  scheduled: (ev, env, ctx) => worker.scheduled(ev, wrap(env), ctx),
};
