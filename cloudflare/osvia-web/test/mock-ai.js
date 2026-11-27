// 本地测试用的假 AI：模拟 Workers AI 的几种返回格式（OpenAI 风格流、旧版 response 流、思考内容）
const enc = new TextEncoder();
const sse = (chunks) =>
  new ReadableStream({
    start(c) {
      for (const ch of chunks) c.enqueue(enc.encode(`data: ${typeof ch === "string" ? ch : JSON.stringify(ch)}\n\n`));
      c.close();
    },
  });

export default {
  async run(model, p) {
    const sys = (p.messages.find((m) => m.role === "system") || {}).content || "";
    const last = p.messages[p.messages.length - 1].content;
    if (p.stream) {
      if (/旧格式/.test(last)) return sse([{ response: "旧" }, { response: "格式" }, "[DONE]"]);
      if (/空回复/.test(last)) return sse(["[DONE]"]);
      return sse([
        { choices: [{ delta: { role: "assistant" } }] }, // 没有内容的块：曾导致流卡住
        { choices: [{ delta: { reasoning_content: "想一想" } }] },
        { choices: [{ delta: { content: "<think>内部" } }] },
        { choices: [{ delta: { content: "思考</think>你好" } }] },
        { choices: [{ delta: { content: "，世界" } }] },
        { usage: { total_tokens: 9 } }, // 末尾的用量块，没有 choices
        "[DONE]",
      ]);
    }
    if (/网页变化监控助手/.test(sys)) {
      if (/噪音/.test(last)) return { response: '{"changed":false,"summary":""}' };
      return { response: '{"changed":true,"summary":"价格从 100 降到 90"}' };
    }
    if (/每日简报助手/.test(sys)) return { response: "【简报】今天有安排：" + (last.includes("开会") ? "开会" : "无") };
    if (/只输出一行 JSON/.test(sys)) {
      const m = sys.match(/现在是 (\d{4})-(\d{2})-(\d{2})/);
      const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3] + 1));
      const pad = (n) => String(n).padStart(2, "0");
      if (/乱码/.test(last)) return { response: "我不知道" };
      return { response: `{"title":"开会","due":"${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} 15:00","rep":0}` };
    }
    if (/只输出译文/.test(sys)) return { choices: [{ message: { content: `<think>x</think>[译]${last}` } }] };
    return { response: `[${sys.slice(0, 4)}]${last.slice(0, 20)}` };
  },
};
