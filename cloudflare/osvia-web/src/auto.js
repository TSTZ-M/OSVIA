// 自动化：服务器 24 小时替你做的事——网页监控（有变化才通知）、每日简报。手机关机、App 被杀也照常运行。
import * as AI from "./ai.js";

export const MAX_AUTOS = 5;
export const WATCH_EVERY = [60, 360, 1440]; // 监控间隔（分钟）
const TEXT_KEEP = 8000; // 留作对照的正文长度
const JUDGE_PER_DAY = 4; // 每个监控每天最多让 AI 判断几次（页面计数器之类的噪音不会耗光额度）
const FAIL_LIMIT = 5; // 连续失败多少次后自动暂停

const clip = (s, n) => String(s ?? "").slice(0, n);
const pad = (n) => String(n).padStart(2, "0");
const safeJson = (s) => { try { return JSON.parse(s) || {}; } catch { return {}; } };
async function sha(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

export const validHm = (s) => /^([01]\d|2[0-3]):[0-5]\d$/.test(String(s || ""));

// 下一次「每天 hh:mm」（用户本地时间）对应的 epoch 秒；tzMin 取 JS 的 getTimezoneOffset()（东八区是 -480）
export function nextDaily(hm, tzMin, fromSec) {
  const [h, m] = hm.split(":").map(Number);
  const d = new Date(fromSec * 1000 - tzMin * 60000); // 用户本地「墙上时间」，按 UTC 字段读取
  d.setUTCHours(h, m, 0, 0);
  let t = d.getTime() + tzMin * 60000;
  if (t <= fromSec * 1000) t += 86400000;
  return Math.floor(t / 1000);
}
export function nextRun(a, cfg, from) {
  return a.kind === "brief" ? nextDaily(cfg.hm || "08:00", Number(cfg.tz) || 0, from) : from + (a.period || 1440) * 60;
}

const localStamp = (ms, tz) => {
  const l = new Date(ms - tz * 60000);
  return `${l.getUTCFullYear()}-${pad(l.getUTCMonth() + 1)}-${pad(l.getUTCDate())} ${pad(l.getUTCHours())}:${pad(l.getUTCMinutes())}（星期${"日一二三四五六"[l.getUTCDay()]}）`;
};

async function runWatch(env, a, cfg, st, d, t) {
  const target = d.publicHttps(cfg.url);
  if (!target) throw { bad: "这个网址不能再监控了" };
  const fetchPage = env.PAGE_FETCH || AI.fetchPageText;
  const page = await fetchPage(target, d.publicHttps, "");
  const text = page.text.slice(0, TEXT_KEEP);
  if (page.text.trim().length < 50) throw { bad: "没有读到有用的文字（可能需要登录，或页面靠脚本生成内容）" };
  const h = await sha(page.text.replace(/\s+/g, " ").trim());
  if (!st.h) {
    st.h = h; st.t = text;
    return { title: `开始监控「${a.title}」`, body: `已记录当前内容（${page.text.length} 字），之后有变化会通知你。`, url: cfg.url, push: false };
  }
  if (h === st.h) return null;
  const day = Math.floor(t / 86400);
  if (st.jd !== day) { st.jd = day; st.jn = 0; }
  if (st.jn >= JUDGE_PER_DAY) return null; // 今天判断次数用完：保留旧对照，变化会累积到之后判断
  const gate = await d.aiGate(env, a.uid);
  if (gate) throw { gate };
  const j = AI.parseJudge(await AI.complete(env, AI.compareMessages(cfg.goal, st.t || "", text), 300));
  st.jn++; st.h = h; st.t = text;
  if (!j.changed) return null;
  return { title: `「${a.title}」有更新`, body: j.summary || "页面内容有变化", url: cfg.url, push: true };
}

async function runBrief(env, a, cfg, d, t) {
  const gate = await d.aiGate(env, a.uid);
  if (gate) throw { gate };
  const tz = Number(cfg.tz) || 0;
  const rs = (await env.DB.prepare("SELECT title,due FROM reminders WHERE uid=? AND sent=0 AND due>=? AND due<=? ORDER BY due LIMIT 10").bind(a.uid, t, t + 86400).all()).results;
  const hm = (sec) => { const l = new Date(sec * 1000 - tz * 60000); return `${pad(l.getUTCHours())}:${pad(l.getUTCMinutes())}`; };
  const out = await AI.complete(env, AI.briefMessages(cfg.prompt, rs.map((r) => `${hm(r.due)} ${r.title}`), localStamp(t * 1000, tz)), 700);
  if (!out) throw { bad: "AI 没有生成内容" };
  return { title: a.title || "每日简报", body: out, url: "", push: true };
}

// 执行一次。返回 { ev, error, skipped, gate }；状态与动态由这里写库
export async function runAuto(env, a, d, { push = true } = {}) {
  const cfg = safeJson(a.cfg);
  const st = safeJson(a.state);
  const t = d.now();
  let ev = null, error = "", disable = false;
  try {
    ev = a.kind === "watch" ? await runWatch(env, a, cfg, st, d, t) : await runBrief(env, a, cfg, d, t);
    st.fails = 0; delete st.err;
  } catch (e) {
    if (e && e.gate) return { gate: e.gate, skipped: true };
    const f = e && e.friendly;
    if (f && (f.status === 503 || f.status === 501)) return { skipped: true, error: f.message }; // AI 忙或额度用完：不算失败，下次再试
    st.fails = (st.fails || 0) + 1;
    error = st.err = clip((e && (e.bad || (f && f.message))) || "出错了，稍后会自动重试", 120);
    if (st.fails >= FAIL_LIMIT) {
      disable = true;
      ev = { title: `「${a.title}」已暂停`, body: `连续 ${FAIL_LIMIT} 次失败：${st.err}。检查后可在「自动化」里重新开启。`, url: cfg.url || "", push: true };
    }
  }
  await env.DB.prepare("UPDATE autos SET last=?, state=?, runs=runs+1, enabled=? WHERE id=?").bind(t, JSON.stringify(st), disable ? 0 : a.enabled, a.id).run();
  if (ev) {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO autoevents(id,uid,aid,title,body,url,created,seen) VALUES(?,?,?,?,?,?,?,0)")
        .bind(d.uuid(), a.uid, a.id, clip(ev.title, 120), clip(ev.body, 4000), clip(ev.url, 500), t),
      env.DB.prepare("DELETE FROM autoevents WHERE uid=? AND id NOT IN (SELECT id FROM autoevents WHERE uid=? ORDER BY created DESC LIMIT 100)").bind(a.uid, a.uid),
    ]);
    if (push && ev.push !== false && a.bark_key) await d.barkSend(env, a, ev.title, ev.body, "active", ev.url);
  }
  return { ev, error };
}

// Cron（每分钟）：每次最多处理 3 个到期的自动化
export async function runAutos(env, d) {
  const t = d.now();
  const { results } = await env.DB.prepare(
    `SELECT a.*, u.bark_server, u.bark_key, u.bark_enc FROM autos a JOIN users u ON u.id=a.uid
     WHERE a.enabled=1 AND a.next<=? ORDER BY a.next LIMIT 3`
  ).bind(t).all();
  for (const a of results) {
    const next = nextRun(a, safeJson(a.cfg), t);
    const c = await env.DB.prepare("UPDATE autos SET next=? WHERE id=? AND next=?").bind(next, a.id, a.next).run();
    if (c.meta?.changes !== 1) continue; // 已被别的实例认领
    try {
      const r = await runAuto(env, a, d, { push: true });
      if (r.skipped && a.kind === "brief") await env.DB.prepare("UPDATE autos SET next=? WHERE id=?").bind(t + 3600, a.id).run(); // 简报没跑成，一小时后重试
    } catch (e) {
      console.error("auto", a.id, e && e.message ? e.message : e);
    }
  }
}
