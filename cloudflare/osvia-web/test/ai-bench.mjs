// 临时：测各模型延迟（直接调 Cloudflare REST）。node test/ai-bench.mjs
const A = process.env.CLOUDFLARE_ACCOUNT_ID, T = process.env.CLOUDFLARE_API_TOKEN;
const api = (p, o) => fetch(`https://api.cloudflare.com/client/v4/accounts/${A}/${p}`, { ...o, headers: { authorization: "Bearer " + T, "content-type": "application/json" } });
const ls = await (await api("ai/models/search?task=Text%20Generation&per_page=100")).json();
console.log("list ok:", ls.success, (ls.result || []).map((m) => m.name).join(" | ") || JSON.stringify(ls.errors));
const names = new Set((ls.result || []).map((m) => m.name));
const want = ["@cf/zai-org/glm-4.7-flash", "@cf/google/gemma-4-26b-a4b-it", "@cf/meta/llama-3.1-8b-instruct-fp8", "@cf/meta/llama-3.3-70b-instruct-fp8-fast", "@cf/qwen/qwen3-30b-a3b-fp8", "@cf/mistralai/mistral-small-3.1-24b-instruct", "@cf/openai/gpt-oss-20b", "@cf/meta/llama-4-scout-17b-16e-instruct", "@cf/qwen/qwen2.5-7b-instruct"].filter((m) => !names.size || names.has(m));
const msgs = [{ role: "system", content: "你是翻译助手，只输出译文。" }, { role: "user", content: "把这句话译成英文：明天下午三点在会议室讨论新版本的发布计划。" }];
for (const m of want) {
  const out = [];
  for (let i = 0; i < 3; i++) {
    const t0 = Date.now();
    try {
      const r = await api("ai/run/" + m, { method: "POST", body: JSON.stringify({ messages: msgs, max_tokens: 200, chat_template_kwargs: { enable_thinking: false } }) });
      const j = await r.json();
      const txt = j.result?.response ?? j.result?.choices?.[0]?.message?.content ?? JSON.stringify(j.errors || j).slice(0, 100);
      out.push(`${Date.now() - t0}ms ${String(txt).replace(/\s+/g, " ").slice(0, 70)}`);
    } catch (e) { out.push("ERR " + e.message); }
  }
  console.log("BENCH " + m + "\n  " + out.join("\n  "));
}
