// 内置 AI：Cloudflare Workers AI。无需用户填密钥；每人每天有次数配额，整站也有总量保护。
// 模型可用 AI_MODEL 变量改；默认优先用中文好又便宜的，失败时依次退到后面的。

export const MODELS = [
  "@cf/zai-org/glm-4.7-flash",
  "@cf/google/gemma-4-26b-a4b-it",
  "@cf/meta/llama-3.1-8b-instruct-fp8",
];

export const USER_DAILY = 40; // 每人每天
export const SITE_DAILY = 500; // 全站每天（免费额度每天约 1 万 neurons）

const dec = new TextDecoder();
const enc = new TextEncoder();

function modelList(env) {
  const first = (env.AI_MODEL || "").trim();
  return first ? [first, ...MODELS.filter((m) => m !== first)] : MODELS;
}

// 去掉模型可能输出的 <think>…</think>
export function stripThink(s) {
  return String(s || "").replace(/<think>[\s\S]*?<\/think>/g, "").replace(/^[\s\S]*?<\/think>/, "").trim();
}

function friendlyError(e) {
  const m = String((e && e.message) || e || "");
  if (/4006|daily free allocation|neurons|quota|exceeded/i.test(m)) return { status: 503, error: "ai_quota", message: "内置 AI 今天的免费额度用完了，明天自动恢复。也可以在助手设置里填自己的密钥继续用。" };
  if (/capacity|overloaded|temporarily|3040|timeout/i.test(m)) return { status: 503, error: "ai_busy", message: "内置 AI 现在比较忙，请稍后再试。" };
  return { status: 502, error: "ai_error", message: "内置 AI 暂时不可用，请稍后再试。" };
}

// 依次尝试模型：模型不存在、没权限这类错误换下一个，额度类错误直接抛出
async function runModel(env, payload) {
  if (!env.AI) throw Object.assign(new Error("no ai"), { friendly: { status: 501, error: "ai_off", message: "内置 AI 还没有开启。" } });
  let last;
  for (const model of modelList(env)) {
    try {
      return { model, out: await env.AI.run(model, payload) };
    } catch (e) {
      last = e;
      const f = friendlyError(e);
      if (f.error === "ai_quota") break;
    }
  }
  throw Object.assign(last || new Error("ai failed"), { friendly: friendlyError(last) });
}

function pickText(out) {
  if (typeof out === "string") return out;
  if (!out) return "";
  if (typeof out.response === "string") return out.response;
  const c = out.choices && out.choices[0];
  if (c && c.message && typeof c.message.content === "string") return c.message.content;
  if (c && typeof c.text === "string") return c.text;
  return "";
}

const BASE = { chat_template_kwargs: { enable_thinking: false } };

// 一次性生成，返回文本
export async function complete(env, messages, maxTokens = 900) {
  const { out } = await runModel(env, { ...BASE, messages, max_tokens: maxTokens, temperature: 0.4 });
  return stripThink(pickText(out));
}

// 流式生成：统一成 data: {"t":"文字"} / {"r":1}（思考中）/ {"e":"错误"} / [DONE]
export async function chatStream(env, messages, maxTokens = 1500) {
  const { out } = await runModel(env, { ...BASE, messages, max_tokens: maxTokens, temperature: 0.6, stream: true });
  if (!(out instanceof ReadableStream)) {
    const text = stripThink(pickText(out));
    return new ReadableStream({
      start(c) {
        if (text) c.enqueue(enc.encode(`data: ${JSON.stringify({ t: text })}\n\n`));
        c.enqueue(enc.encode("data: [DONE]\n\n"));
        c.close();
      },
    });
  }
  const reader = out.getReader();
  let buf = "";
  let inThink = false;
  let sentAny = false;
  let rawHead = "";
  const emit = (c, o) => c.enqueue(enc.encode(`data: ${JSON.stringify(o)}\n\n`));
  const text = (c, s) => {
    // 简单的 <think> 过滤，跨块时按状态处理
    let rest = s;
    while (rest) {
      if (inThink) {
        const i = rest.indexOf("</think>");
        if (i < 0) { emit(c, { r: 1 }); return; }
        inThink = false;
        rest = rest.slice(i + 8);
      } else {
        const i = rest.indexOf("<think>");
        if (i < 0) { if (rest) { sentAny = true; emit(c, { t: rest }); } return; }
        if (i > 0) { sentAny = true; emit(c, { t: rest.slice(0, i) }); }
        inThink = true;
        rest = rest.slice(i + 7);
      }
    }
  };
  return new ReadableStream({
    async pull(c) {
      try {
        const { done, value } = await reader.read();
        if (done) {
          if (!sentAny) emit(c, { e: "empty", raw: rawHead.slice(0, 300) });
          c.enqueue(enc.encode("data: [DONE]\n\n"));
          c.close();
          return;
        }
        buf += dec.decode(value, { stream: true });
        if (rawHead.length < 300) rawHead += buf.slice(0, 300);
        const lines = buf.split("\n");
        buf = lines.pop();
        for (const ln of lines) {
          if (!ln.startsWith("data:")) continue;
          const d = ln.slice(5).trim();
          if (!d || d === "[DONE]") continue;
          let j;
          try { j = JSON.parse(d); } catch { continue; }
          if (typeof j.response === "string") { text(c, j.response); continue; }
          const delta = j.choices && j.choices[0] && j.choices[0].delta;
          if (!delta) continue;
          if (typeof delta.content === "string" && delta.content) text(c, delta.content);
          else if (delta.reasoning_content || delta.reasoning) emit(c, { r: 1 });
        }
      } catch (e) {
        emit(c, { e: friendlyError(e).message });
        c.enqueue(enc.encode("data: [DONE]\n\n"));
        c.close();
      }
    },
    cancel() { reader.cancel().catch(() => {}); },
  });
}

// ---------- 小工具的提示词 ----------
const TOOLS = {
  summarize: "你是中文写作助手。请用中文概括下面的内容：先给一句话总结，再用 3 到 6 条要点列出关键信息。不要编造原文没有的内容。",
  polish: "你是中文编辑。请润色下面的文字：保持原意和语气，修正错别字和语病，让表达更通顺自然。只输出润色后的正文，不要解释。",
  continue: "你是写作助手。请顺着下面文字的风格和思路自然地续写一段，约 150 字。只输出续写的内容，不要重复原文。",
  todos: "请从下面的内容里提取待办事项，每行一条，以「- 」开头，写成简短的动作句；如果有时间或负责人也带上。没有待办就回答「没有待办事项」。",
  titleize: "请为下面的内容起一个不超过 16 个字的标题。只输出标题本身，不要引号和标点结尾。",
};
const LANGS = { zh: "简体中文", en: "English", ja: "日本語", ko: "한국어", fr: "Français", de: "Deutsch", es: "Español", ru: "Русский" };

export function toolMessages(tool, text, lang) {
  if (tool === "translate") {
    const target = LANGS[lang] || LANGS.en;
    return [
      { role: "system", content: `你是专业翻译。把用户给的文字翻译成${target}，保留原有的段落、列表和格式。只输出译文，不要解释。` },
      { role: "user", content: text },
    ];
  }
  const sys = TOOLS[tool];
  if (!sys) return null;
  return [{ role: "system", content: sys }, { role: "user", content: text }];
}
export const toolNames = () => [...Object.keys(TOOLS), "translate"];

// ---------- 一句话建提醒：让模型把自然语言转成 JSON，再由服务端校验 ----------
export async function parseReminder(env, text, nowMs, tzMin) {
  // tzMin 取 JS 的 getTimezoneOffset()（东八区是 -480）
  const local = new Date(nowMs - tzMin * 60000);
  const pad = (n) => String(n).padStart(2, "0");
  const stamp = `${local.getUTCFullYear()}-${pad(local.getUTCMonth() + 1)}-${pad(local.getUTCDate())} ${pad(local.getUTCHours())}:${pad(local.getUTCMinutes())}`;
  const wd = "日一二三四五六"[local.getUTCDay()];
  const sys =
    `现在是 ${stamp}（星期${wd}，用户所在时区的本地时间）。把用户的话转成提醒，只输出一行 JSON，不要任何其他文字：` +
    `{"title":"提醒内容，不超过 30 字，不要带时间","due":"YYYY-MM-DD HH:mm","rep":0}` +
    `。rep 表示重复：0 不重复，1 每天，7 每周。「早上」默认 8:00，「中午」12:00，「下午」15:00，「晚上」20:00，没说具体时间默认 9:00。` +
    `如果说的是几分钟或几小时后，请基于现在的时间推算。无法理解就输出 {"error":"无法理解"}。`;
  const raw = await complete(env, [{ role: "system", content: sys }, { role: "user", content: text }], 200);
  const m = raw.match(/\{[\s\S]*\}/);
  if (!m) return null;
  let j;
  try { j = JSON.parse(m[0]); } catch { return null; }
  if (j.error || typeof j.title !== "string" || typeof j.due !== "string") return null;
  const d = j.due.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
  if (!d) return null;
  const due = Math.floor((Date.UTC(+d[1], +d[2] - 1, +d[3], +d[4], +d[5]) + tzMin * 60000) / 1000);
  if (!Number.isFinite(due) || due < Math.floor(nowMs / 1000) - 60) return null;
  const rep = [0, 1, 7].includes(Number(j.rep)) ? Number(j.rep) : 0;
  return { title: j.title.trim().slice(0, 120), due, rep };
}

// ---------- 网页摘要：抓取公开网页，提取正文 ----------
export async function fetchPageText(startUrl, publicHttps, selfHost) {
  let url = startUrl;
  let res;
  for (let hop = 0; hop < 4; hop++) {
    if (url.hostname === selfHost) throw Object.assign(new Error("self"), { bad: "不能读取本站页面" });
    res = await fetch(url.href, {
      redirect: "manual",
      headers: { "user-agent": "Mozilla/5.0 (compatible; OSVIA-Reader/1.0)", accept: "text/html,text/plain;q=0.9,*/*;q=0.5", "accept-language": "zh-CN,zh;q=0.9,en;q=0.8" },
      signal: AbortSignal.timeout(10000),
    });
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      const next = publicHttps(new URL(res.headers.get("location"), url).href);
      if (!next) throw Object.assign(new Error("redirect"), { bad: "网页跳转到了不允许的地址" });
      url = next;
      continue;
    }
    break;
  }
  if (!res.ok) throw Object.assign(new Error("http"), { bad: `网页返回了 ${res.status}` });
  const type = (res.headers.get("content-type") || "").toLowerCase();
  if (type && !/text\/|html|xml|json/.test(type)) throw Object.assign(new Error("type"), { bad: "这个地址不是网页文字" });

  let title = "";
  let text = "";
  let skip = 0;
  const MAX = 16000;
  const rewriter = new HTMLRewriter()
    .on("title", { text(t) { if (title.length < 200) title += t.text; } })
    .on("script,style,noscript,svg,nav,footer,aside,iframe", {
      element(e) { skip++; e.onEndTag(() => { skip--; }); },
    })
    .on("body", { text(t) { if (!skip && text.length < MAX) text += t.text; } })
    .on("p,h1,h2,h3,h4,li,tr,br,blockquote,pre,div", { element() { if (!skip) text += "\n"; } });
  // 限制读取体积，防止超大页面
  const limited = new Response(res.body.pipeThrough(new TransformStream({
    start() { this.n = 0; },
    transform(chunk, c) {
      this.n += chunk.byteLength;
      if (this.n > 1_500_000) { c.terminate(); return; }
      c.enqueue(chunk);
    },
  })), { headers: res.headers });
  const out = rewriter.transform(limited);
  const raw = await out.text();
  const strip = (h) => h.replace(/<(script|style|noscript|svg)[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ");
  if (!text.trim()) text = strip(raw); // 不是标准 HTML（纯文本等）
  const clean = text.replace(/[ \t ]+/g, " ").replace(/\s*\n\s*/g, "\n").replace(/\n{3,}/g, "\n\n").trim().slice(0, MAX);
  let body = clean;
  if (body.length < 200) {
    const alt = strip(raw).replace(/\s+/g, " ").trim().slice(0, MAX); // 标签没闭合导致提取过少时的兜底
    if (alt.length > body.length) body = alt;
  }
  return { title: title.replace(/\s+/g, " ").trim(), text: body, url: url.href };
}

export { friendlyError };
