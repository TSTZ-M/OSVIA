// 测试入口：给真实 Worker 注入假的 AI 绑定（本地 wrangler dev 无法使用线上 Workers AI）
import worker from "../src/index.js";
import mock from "./mock-ai.js";
export default {
  fetch: (req, env, ctx) => worker.fetch(req, { ...env, AI: mock }, ctx),
  scheduled: (ev, env, ctx) => worker.scheduled(ev, { ...env, AI: mock }, ctx),
};
