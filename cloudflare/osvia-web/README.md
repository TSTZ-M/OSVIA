# OSVIA 网页版

Cloudflare Worker + 静态页面。线上地址：https://osvia.tstzrm.workers.dev

- 账号：任意邮箱注册登录。密码在浏览器/App 里用 PBKDF2-SHA256（210000 次）派生后才发送，服务器只存加盐哈希。
- 提醒：到点由服务器通过 Bark 推送（Worker 每分钟一次 cron）；iOS App 可把排队中的提醒中转到这里。
- 笔记、云备份（只收 OSVIA 加密备份）、模型对话代理（密钥不落库）。
- 内置 AI（Cloudflare Workers AI，免 API 密钥）：助手对话（云端保存历史）、网页摘要、翻译/总结/润色/提取待办、笔记 AI 工具、一句话设提醒。
  每账号每天 40 次、全站每天 500 次（UTC 零点重置，见 `src/ai.js`），额度用完前端会提示改用自己的密钥。
- 账号可在网页/App 内删除，同时清除全部云端数据。

## 部署

推送到 `main` 且改动了 `cloudflare/**` 会自动部署；也可手动运行工作流 `deploy-cloudflare.yml`。
部署后会自动运行 `test/smoke.mjs` 对线上接口做冒烟测试。

本地调试：`npx wrangler dev --local`，另开终端 `node test/smoke.mjs`。

## 邮箱验证码（可选）

默认不发验证码（账号直接可用）。要开启注册验证和找回密码：
1. 在 Cloudflare 开通 Email Sending，或准备 Resend 的 API Key；
2. 在 `wrangler.toml` 里取消 `send_email` 绑定的注释，或用 `wrangler secret put RESEND_API_KEY` 并在 `[vars]` 里设置 `MAIL_FROM`；
3. 重新部署后 `/api/config` 会返回 `mail: true`，前端自动出现验证码与找回密码入口。


## 内置 AI

- 绑定：`wrangler.toml` 的 `[ai] binding = "AI"`；模型由 `[vars] AI_MODEL` 指定（默认 `@cf/zai-org/glm-4.7-flash`，不可用时依次回退到 gemma / llama）。
- 免费额度：Workers AI 免费账号每天 10,000 neurons（UTC 零点重置），Workers Free 不会超额扣费，用完接口返回 `ai_quota`。
- 不想启用：删掉 `[ai]` 绑定即可，`/api/config` 会返回 `ai: false`，前端自动隐藏相关入口。
- 本地测试：`wrangler dev -c test/wrangler.test.toml --local`（注入假 AI，不消耗额度），另开终端 `node test/smoke.mjs`。
