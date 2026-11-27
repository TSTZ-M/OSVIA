const models = ["@cf/zai-org/glm-4.7-flash", "@cf/google/gemma-4-26b-a4b-it", "@cf/meta/llama-3.1-8b-instruct-fp8", "@cf/meta/llama-3.3-70b-instruct-fp8-fast", "@cf/qwen/qwen3-30b-a3b-fp8", "@cf/mistralai/mistral-small-3.1-24b-instruct", "@cf/openai/gpt-oss-20b", "@cf/meta/llama-4-scout-17b-16e-instruct", "@cf/qwen/qwen2.5-7b-instruct"];
const B = "https://osvia.tstzrm.workers.dev";
await Promise.all(models.map(async (m) => {
  try {
    const r = await fetch(B + "/api/__bench", { method: "POST", headers: { authorization: "Bearer " + process.env.BENCH_TOKEN }, body: JSON.stringify({ model: m }) });
    const j = await r.json().catch(() => ({ status: r.status }));
    console.log("BENCH " + m + "\n  " + (j.rs ? j.rs.join("\n  ") : JSON.stringify(j)));
  } catch (e) { console.log("BENCH " + m + " ERR " + e.message); }
}));
