// OSVIA Web — 账号、提醒云端中转（Bark）、笔记、加密云备份、网页助手代理
// 设计要点：
//  - 密码不上传：客户端用 PBKDF2(210k) 从「密码 + 邮箱」派生 authKey，服务器只存 authKey 的加盐哈希
//  - 会话令牌随机 256 位，服务器只存它的 SHA-256；通过 Authorization: Bearer 传递（无 Cookie，天然免 CSRF）
//  - 云备份只接受已加密的 .osvbackup（校验文件头），服务器看不到内容
//  - 邮箱验证码为可选能力：配置了发信渠道（见 wrangler.toml）才启用

import * as AI from "./ai.js";

const enc = new TextEncoder();
const VERSION = "1.1.0";

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS users(
    id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT DEFAULT '',
    pw TEXT NOT NULL, verified INTEGER DEFAULT 0, created INTEGER NOT NULL, last_login INTEGER DEFAULT 0,
    bark_server TEXT DEFAULT '', bark_key TEXT DEFAULT '', bark_enc TEXT DEFAULT '')`,
  `CREATE TABLE IF NOT EXISTS sessions(
    id TEXT PRIMARY KEY, uid TEXT NOT NULL, exp INTEGER NOT NULL, created INTEGER NOT NULL, ua TEXT DEFAULT '')`,
  `CREATE INDEX IF NOT EXISTS idx_sessions_uid ON sessions(uid)`,
  `CREATE TABLE IF NOT EXISTS otps(
    email TEXT PRIMARY KEY, hash TEXT NOT NULL, exp INTEGER NOT NULL, tries INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS rl(k TEXT PRIMARY KEY, n INTEGER NOT NULL, exp INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS reminders(
    id TEXT PRIMARY KEY, uid TEXT NOT NULL, title TEXT NOT NULL, body TEXT DEFAULT '',
    due INTEGER NOT NULL, rep INTEGER DEFAULT 0, sent INTEGER DEFAULT 0, src TEXT DEFAULT 'web',
    ref TEXT DEFAULT '', updated INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS idx_rem_due ON reminders(sent, due)`,
  `CREATE INDEX IF NOT EXISTS idx_rem_uid ON reminders(uid, due)`,
  `CREATE TABLE IF NOT EXISTS notes(
    id TEXT PRIMARY KEY, uid TEXT NOT NULL, title TEXT DEFAULT '', body TEXT DEFAULT '',
    updated INTEGER NOT NULL, deleted INTEGER DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS idx_notes_uid ON notes(uid, updated)`,
  `CREATE TABLE IF NOT EXISTS backups(
    id TEXT PRIMARY KEY, uid TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL,
    created INTEGER NOT NULL, device TEXT DEFAULT '')`,
  `CREATE INDEX IF NOT EXISTS idx_backups_uid ON backups(uid, created)`,
  `CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS chats(
    id TEXT PRIMARY KEY, uid TEXT NOT NULL, title TEXT DEFAULT '', msgs TEXT DEFAULT '[]', updated INTEGER NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS idx_chats_uid ON chats(uid, updated)`,
];

let ready = null;
async function ensure(env) {
  if (!ready) {
    ready = env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s))).catch((e) => {
      ready = null;
      throw e;
    });
  }
  await ready;
}

// ---------- 小工具 ----------
const now = () => Math.floor(Date.now() / 1000);
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
const fail = (status, error, message) => json({ error, message }, status);

function b64u(buf) {
  const a = new Uint8Array(buf);
  let s = "";
  for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function unb64u(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const rand = (n) => crypto.getRandomValues(new Uint8Array(n));
const uuid = () => crypto.randomUUID();
async function sha256(data) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", typeof data === "string" ? enc.encode(data) : data));
}
function same(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
const AUTHKEY_RE = /^[A-Za-z0-9_-]{43}$/;
function normEmail(s) {
  s = String(s || "").trim().toLowerCase();
  return s.length <= 254 && EMAIL_RE.test(s) ? s : "";
}
const clip = (s, n) => String(s ?? "").slice(0, n);

async function body(req) {
  try {
    const t = await req.text();
    if (t.length > 2_000_000) return {};
    return t ? JSON.parse(t) : {};
  } catch {
    return {};
  }
}

// 限流：窗口内计数，超出返回 false
async function limit(env, key, max, windowSec) {
  const t = now();
  const bucket = Math.floor(t / windowSec);
  const r = await env.DB.prepare(
    "INSERT INTO rl(k,n,exp) VALUES(?,1,?) ON CONFLICT(k) DO UPDATE SET n=n+1 RETURNING n"
  )
    .bind(`${key}:${bucket}`, (bucket + 1) * windowSec + 60)
    .first();
  return (r?.n ?? 1) <= max;
}
const ip = (req) => req.headers.get("cf-connecting-ip") || "0";

// ---------- 字段加密（Bark 密钥等）：数据密钥首次使用时生成并存在 meta 表 ----------
let dataKey = null;
async function getDataKey(env) {
  if (dataKey) return dataKey;
  let row = await env.DB.prepare("SELECT v FROM meta WHERE k='dk'").first();
  if (!row) {
    await env.DB.prepare("INSERT OR IGNORE INTO meta(k,v) VALUES('dk',?)").bind(b64u(rand(32))).run();
    row = await env.DB.prepare("SELECT v FROM meta WHERE k='dk'").first();
  }
  dataKey = await crypto.subtle.importKey("raw", unb64u(row.v), "AES-GCM", false, ["encrypt", "decrypt"]);
  return dataKey;
}
async function seal(env, text) {
  if (!text) return "";
  const iv = rand(12);
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await getDataKey(env), enc.encode(text));
  return `v1.${b64u(iv)}.${b64u(ct)}`;
}
async function open(env, text) {
  if (!text) return "";
  const [v, iv, ct] = text.split(".");
  if (v !== "v1" || !iv || !ct) return "";
  try {
    const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64u(iv) }, await getDataKey(env), unb64u(ct));
    return new TextDecoder().decode(pt);
  } catch {
    return "";
  }
}

// ---------- 密码与会话 ----------
async function hashPw(authKey, salt = b64u(rand(16))) {
  return `${salt}.${b64u(await sha256(`${salt}.${authKey}`))}`;
}
async function checkPw(stored, authKey) {
  const salt = stored.split(".")[0];
  return same(stored, await hashPw(authKey, salt));
}

const SESSION_DAYS = 30;
async function newSession(env, uid, req) {
  const token = b64u(rand(32));
  const id = b64u(await sha256(token));
  const t = now();
  await env.DB.prepare("INSERT INTO sessions(id,uid,exp,created,ua) VALUES(?,?,?,?,?)")
    .bind(id, uid, t + SESSION_DAYS * 86400, t, clip(req.headers.get("user-agent"), 120))
    .run();
  // 每个账号最多保留 12 个会话
  await env.DB.prepare(
    "DELETE FROM sessions WHERE uid=? AND id NOT IN (SELECT id FROM sessions WHERE uid=? ORDER BY created DESC LIMIT 12)"
  )
    .bind(uid, uid)
    .run();
  return token;
}

async function auth(env, req) {
  const m = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.get("authorization") || "");
  if (!m) return null;
  const id = b64u(await sha256(m[1]));
  const row = await env.DB.prepare(
    "SELECT s.id AS sid, s.exp AS sexp, u.* FROM sessions s JOIN users u ON u.id=s.uid WHERE s.id=?"
  )
    .bind(id)
    .first();
  if (!row || row.sexp < now()) return null;
  return row;
}

const publicUser = (u) => ({
  id: u.id,
  email: u.email,
  name: u.name || "",
  verified: !!u.verified,
  created: u.created,
  barkOn: !!u.bark_key,
  barkServer: u.bark_server || "",
});

// ---------- 邮箱验证码（可选） ----------
const mailOn = (env) => !!(env.EMAIL || (env.RESEND_API_KEY && env.MAIL_FROM));
async function sendMail(env, to, subject, text) {
  if (env.EMAIL && env.EMAIL.send) {
    await env.EMAIL.send({ from: env.MAIL_FROM, to, subject, text });
    return true;
  }
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ from: env.MAIL_FROM, to: [to], subject, text }),
  });
  return r.ok;
}
async function issueCode(env, email) {
  const n = new Uint32Array(1);
  crypto.getRandomValues(n);
  const code = String(n[0] % 1000000).padStart(6, "0");
  const hash = b64u(await sha256(`${email}:${code}`));
  await env.DB.prepare(
    "INSERT INTO otps(email,hash,exp,tries) VALUES(?,?,?,0) ON CONFLICT(email) DO UPDATE SET hash=excluded.hash, exp=excluded.exp, tries=0"
  )
    .bind(email, hash, now() + 600)
    .run();
  await sendMail(
    env,
    email,
    `OSVIA 验证码 ${code}`,
    `你的 OSVIA 验证码是 ${code}，10 分钟内有效。\n如果不是你本人操作，请忽略这封邮件。\n\nYour OSVIA verification code is ${code}. It expires in 10 minutes.`
  );
}
async function checkCode(env, email, code) {
  const row = await env.DB.prepare("SELECT * FROM otps WHERE email=?").bind(email).first();
  if (!row || row.exp < now() || row.tries >= 5) return false;
  const ok = same(row.hash, b64u(await sha256(`${email}:${String(code || "").trim()}`)));
  if (ok) await env.DB.prepare("DELETE FROM otps WHERE email=?").bind(email).run();
  else await env.DB.prepare("UPDATE otps SET tries=tries+1 WHERE email=?").bind(email).run();
  return ok;
}

// ---------- 网络安全：只允许公开 https 地址 ----------
function publicHttps(u) {
  let url;
  try {
    url = new URL(u);
  } catch {
    return null;
  }
  const h = url.hostname.toLowerCase();
  if (url.protocol !== "https:" || url.username || url.password) return null;
  if (!h.includes(".") || h === "localhost" || /^[\d.]+$/.test(h) || h.includes(":") || h.includes("[")) return null;
  if (/\.(local|internal|lan|localdomain|home\.arpa)$/.test(h)) return null;
  return url;
}


// ---------- 内置 AI 的配额与消息清洗 ----------
async function aiGate(env, uid) {
  if (!env.AI) return fail(501, "ai_off", "内置 AI 还没有开启");
  if (!(await limit(env, `ai:${uid}`, AI.USER_DAILY, 86400)))
    return fail(429, "ai_user_quota", `今天的内置 AI 次数用完了（每天 ${AI.USER_DAILY} 次），明天自动恢复。也可以在助手设置里填自己的密钥继续用。`);
  if (!(await limit(env, "ai:site", AI.SITE_DAILY, 86400)))
    return fail(503, "ai_site_quota", "内置 AI 今天太忙了，明天再来，或者在助手设置里填自己的密钥。");
  return null;
}
async function aiUsed(env, uid) {
  const r = await env.DB.prepare("SELECT n FROM rl WHERE k=?").bind(`ai:${uid}:${Math.floor(now() / 86400)}`).first();
  return r?.n ?? 0;
}
// 只保留 user / assistant，限制条数与总长度（从最新往回取）
function cleanMsgs(list, maxCount, maxChars) {
  if (!Array.isArray(list)) return [];
  const out = [];
  let total = 0;
  for (let i = list.length - 1; i >= 0 && out.length < maxCount; i--) {
    const m = list[i];
    if (!m || (m.role !== "user" && m.role !== "assistant") || typeof m.content !== "string") continue;
    const content = clip(m.content, 12000);
    if (!content.trim()) continue;
    total += content.length;
    if (total > maxChars) break;
    out.unshift({ role: m.role, content });
  }
  return out;
}

// ---------- Bark ----------
async function barkSend(env, u, title, text, level = "timeSensitive") {
  const keys = (await open(env, u.bark_key)).split(/[\s,]+/).filter(Boolean);
  if (!keys.length) return "no_key";
  const base = publicHttps(u.bark_server || "https://api.day.app");
  if (!base) return "bad_server";
  const encKey = await open(env, u.bark_enc);
  let errors = 0;
  for (const k of keys) {
    const payload = { title: clip(title, 80), body: clip(text, 400), group: "OSVIA", level, icon: "" };
    let data;
    if (encKey) {
      const kb = enc.encode(encKey);
      if (![16, 24, 32].includes(kb.length)) return "bad_enc";
      const ivStr = Array.from(rand(12), (x) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[x % 62]).join("");
      const ck = await crypto.subtle.importKey("raw", kb, "AES-GCM", false, ["encrypt"]);
      const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv: enc.encode(ivStr) }, ck, enc.encode(JSON.stringify(payload)));
      let s = "";
      new Uint8Array(ct).forEach((c) => (s += String.fromCharCode(c)));
      data = { device_key: k, ciphertext: btoa(s), iv: ivStr };
    } else {
      data = { device_key: k, ...payload };
    }
    try {
      const r = await fetch(`${base.origin}${base.pathname.replace(/\/+$/, "")}/push`, {
        method: "POST",
        headers: { "content-type": "application/json; charset=utf-8" },
        body: JSON.stringify(data),
      });
      if (!r.ok) errors++;
    } catch {
      errors++;
    }
  }
  return errors === keys.length ? "failed" : "";
}

// ---------- 到期提醒（Cron，每分钟） ----------
async function runDue(env) {
  const t = now();
  const { results } = await env.DB.prepare(
    `SELECT r.*, u.bark_server, u.bark_key, u.bark_enc FROM reminders r JOIN users u ON u.id=r.uid
     WHERE r.sent=0 AND r.due<=? ORDER BY r.due LIMIT 100`
  )
    .bind(t)
    .all();
  for (const r of results) {
    // 先「认领」再发送，保证同一条只推一次
    let claimed;
    if (r.rep > 0) {
      let next = r.due + r.rep * 86400;
      while (next <= t) next += r.rep * 86400;
      claimed = await env.DB.prepare("UPDATE reminders SET due=?, updated=? WHERE id=? AND due=? AND sent=0")
        .bind(next, t, r.id, r.due)
        .run();
    } else {
      claimed = await env.DB.prepare("UPDATE reminders SET sent=1, updated=? WHERE id=? AND sent=0").bind(t, r.id).run();
    }
    if (!claimed.meta || claimed.meta.changes !== 1) continue;
    if (r.bark_key) await barkSend(env, r, r.title, r.body || r.title);
  }
}

async function cleanup(env) {
  const t = now();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM sessions WHERE exp<?").bind(t),
    env.DB.prepare("DELETE FROM rl WHERE exp<?").bind(t),
    env.DB.prepare("DELETE FROM otps WHERE exp<?").bind(t),
    env.DB.prepare("DELETE FROM reminders WHERE sent=1 AND due<?").bind(t - 30 * 86400),
    env.DB.prepare("DELETE FROM notes WHERE deleted=1 AND updated<?").bind(t - 30 * 86400),
  ]);
}

// ---------- 路由 ----------
async function handle(req, env) {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");
  const method = req.method;

  if (path === "/api/config" && method === "GET") return json({ mail: mailOn(env), ai: !!env.AI, aiDaily: AI.USER_DAILY, version: VERSION });

  // ----- 注册、登录、验证码 -----
  if (path === "/api/auth/register" && method === "POST") {
    if (!(await limit(env, `reg:${ip(req)}`, 5, 3600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    const b = await body(req);
    const email = normEmail(b.email);
    if (!email) return fail(400, "bad_email", "邮箱地址不正确");
    if (!AUTHKEY_RE.test(b.authKey || "")) return fail(400, "bad_request", "请求不完整");
    const id = uuid();
    try {
      await env.DB.prepare("INSERT INTO users(id,email,name,pw,verified,created) VALUES(?,?,?,?,?,?)")
        .bind(id, email, clip(b.name, 40), await hashPw(b.authKey), 0, now())
        .run();
    } catch {
      return fail(409, "exists", "这个邮箱已经注册过了，请直接登录");
    }
    if (mailOn(env)) {
      await issueCode(env, email);
      return json({ needVerify: true });
    }
    const u = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(id).first();
    return json({ token: await newSession(env, id, req), user: publicUser(u) });
  }

  if (path === "/api/auth/login" && method === "POST") {
    const b = await body(req);
    const email = normEmail(b.email);
    if (!(await limit(env, `login:ip:${ip(req)}`, 30, 600)) || !(await limit(env, `login:em:${email}`, 8, 600)))
      return fail(429, "rate_limited", "尝试次数太多，请 10 分钟后再试");
    if (!email || !AUTHKEY_RE.test(b.authKey || "")) return fail(401, "bad_credentials", "邮箱或密码不正确");
    const u = await env.DB.prepare("SELECT * FROM users WHERE email=?").bind(email).first();
    const ok = u ? await checkPw(u.pw, b.authKey) : (await hashPw(b.authKey), false);
    if (!ok) return fail(401, "bad_credentials", "邮箱或密码不正确");
    if (mailOn(env) && !u.verified) {
      await issueCode(env, email);
      return fail(403, "need_verify", "请先验证邮箱，验证码已发送");
    }
    await env.DB.prepare("UPDATE users SET last_login=? WHERE id=?").bind(now(), u.id).run();
    return json({ token: await newSession(env, u.id, req), user: publicUser(u) });
  }

  if (path === "/api/auth/code" && method === "POST") {
    if (!mailOn(env)) return fail(501, "mail_off", "服务器没有开启邮件发送");
    const b = await body(req);
    const email = normEmail(b.email);
    if (!email) return fail(400, "bad_email", "邮箱地址不正确");
    if (!(await limit(env, `code:em:${email}`, 3, 600)) || !(await limit(env, `code:ip:${ip(req)}`, 10, 3600)))
      return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    const u = await env.DB.prepare("SELECT id FROM users WHERE email=?").bind(email).first();
    if (u) await issueCode(env, email);
    return json({ ok: true }); // 不透露邮箱是否注册
  }

  if (path === "/api/auth/verify" && method === "POST") {
    const b = await body(req);
    const email = normEmail(b.email);
    if (!email || !(await limit(env, `verify:${ip(req)}`, 20, 600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    if (!(await checkCode(env, email, b.code))) return fail(400, "bad_code", "验证码不对或已过期");
    const u = await env.DB.prepare("SELECT * FROM users WHERE email=?").bind(email).first();
    if (!u) return fail(400, "bad_code", "验证码不对或已过期");
    await env.DB.prepare("UPDATE users SET verified=1, last_login=? WHERE id=?").bind(now(), u.id).run();
    u.verified = 1;
    return json({ token: await newSession(env, u.id, req), user: publicUser(u) });
  }

  if (path === "/api/auth/reset" && method === "POST") {
    const b = await body(req);
    const email = normEmail(b.email);
    if (!email || !AUTHKEY_RE.test(b.authKey || "")) return fail(400, "bad_request", "请求不完整");
    if (!(await limit(env, `reset:${ip(req)}`, 10, 600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    if (!(await checkCode(env, email, b.code))) return fail(400, "bad_code", "验证码不对或已过期");
    const u = await env.DB.prepare("SELECT id FROM users WHERE email=?").bind(email).first();
    if (!u) return fail(400, "bad_code", "验证码不对或已过期");
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET pw=?, verified=1 WHERE id=?").bind(await hashPw(b.authKey), u.id),
      env.DB.prepare("DELETE FROM sessions WHERE uid=?").bind(u.id),
    ]);
    return json({ ok: true });
  }

  // ----- 以下都需要登录 -----
  const me = await auth(env, req);
  if (!me) return fail(401, "unauthorized", "请先登录");
  const uid = me.id;

  if (path === "/api/auth/logout" && method === "POST") {
    await env.DB.prepare("DELETE FROM sessions WHERE id=?").bind(me.sid).run();
    return json({ ok: true });
  }

  if (path === "/api/me" && method === "GET") {
    const [r, n, b, ch] = await Promise.all([
      env.DB.prepare("SELECT COUNT(*) c FROM reminders WHERE uid=? AND sent=0").bind(uid).first(),
      env.DB.prepare("SELECT COUNT(*) c FROM notes WHERE uid=? AND deleted=0").bind(uid).first(),
      env.DB.prepare("SELECT COUNT(*) c, COALESCE(SUM(size),0) s FROM backups WHERE uid=?").bind(uid).first(),
      env.DB.prepare("SELECT COUNT(*) c FROM chats WHERE uid=?").bind(uid).first(),
    ]);
    return json({ user: publicUser(me), counts: { reminders: r.c, notes: n.c, backups: b.c, backupBytes: b.s, chats: ch.c } });
  }

  if (path === "/api/me" && method === "PATCH") {
    const b = await body(req);
    await env.DB.prepare("UPDATE users SET name=? WHERE id=?").bind(clip(b.name, 40), uid).run();
    return json({ ok: true });
  }

  if (path === "/api/auth/password" && method === "POST") {
    const b = await body(req);
    if (!AUTHKEY_RE.test(b.authKey || "") || !AUTHKEY_RE.test(b.newAuthKey || "")) return fail(400, "bad_request", "请求不完整");
    if (!(await limit(env, `pw:${uid}`, 5, 600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    if (!(await checkPw(me.pw, b.authKey))) return fail(401, "bad_credentials", "当前密码不正确");
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET pw=? WHERE id=?").bind(await hashPw(b.newAuthKey), uid),
      env.DB.prepare("DELETE FROM sessions WHERE uid=? AND id<>?").bind(uid, me.sid),
    ]);
    return json({ ok: true });
  }

  // 删除账号：App Store 要求应用内可以删除账号及全部数据
  if (path === "/api/me" && method === "DELETE") {
    const b = await body(req);
    if (!(await limit(env, `del:${uid}`, 5, 600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    if (!AUTHKEY_RE.test(b.authKey || "") || !(await checkPw(me.pw, b.authKey))) return fail(401, "bad_credentials", "密码不正确");
    let cursor;
    do {
      const l = await env.R2.list({ prefix: `u/${uid}/`, cursor, limit: 500 });
      if (l.objects.length) await env.R2.delete(l.objects.map((o) => o.key));
      cursor = l.truncated ? l.cursor : undefined;
    } while (cursor);
    await env.DB.batch([
      env.DB.prepare("DELETE FROM reminders WHERE uid=?").bind(uid),
      env.DB.prepare("DELETE FROM notes WHERE uid=?").bind(uid),
      env.DB.prepare("DELETE FROM chats WHERE uid=?").bind(uid),
      env.DB.prepare("DELETE FROM backups WHERE uid=?").bind(uid),
      env.DB.prepare("DELETE FROM sessions WHERE uid=?").bind(uid),
      env.DB.prepare("DELETE FROM otps WHERE email=?").bind(me.email),
      env.DB.prepare("DELETE FROM users WHERE id=?").bind(uid),
    ]);
    return json({ ok: true });
  }

  // ----- Bark 设置 -----
  if (path === "/api/bark" && method === "GET") {
    return json({ server: me.bark_server || "", keySet: !!me.bark_key, encSet: !!me.bark_enc });
  }
  if (path === "/api/bark" && method === "PUT") {
    const b = await body(req);
    const server = clip(b.server, 200).trim();
    if (server && !publicHttps(server)) return fail(400, "bad_server", "服务器地址需要是公开的 https 地址");
    const sets = ["bark_server=?"];
    const args = [server];
    if (typeof b.key === "string") {
      sets.push("bark_key=?");
      args.push(await seal(env, clip(b.key, 600).trim()));
    }
    if (typeof b.enc === "string") {
      sets.push("bark_enc=?");
      args.push(await seal(env, clip(b.enc, 40).trim()));
    }
    await env.DB.prepare(`UPDATE users SET ${sets.join(",")} WHERE id=?`).bind(...args, uid).run();
    return json({ ok: true });
  }
  if (path === "/api/bark/test" && method === "POST") {
    if (!(await limit(env, `bt:${uid}`, 10, 600))) return fail(429, "rate_limited", "操作太频繁，请稍后再试");
    const u = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(uid).first();
    const e = await barkSend(env, u, "OSVIA", "这是一条测试推送，收到说明 Bark 已连通。");
    return e ? fail(400, e, "推送失败：请检查设备密钥、服务器地址和加密密钥") : json({ ok: true });
  }

  // ----- 提醒 -----
  if (path === "/api/reminders" && method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT id,title,body,due,rep,sent,src FROM reminders WHERE uid=? ORDER BY sent, due LIMIT 500"
    )
      .bind(uid)
      .all();
    return json({ items: results });
  }
  if (path === "/api/reminders" && method === "POST") {
    const b = await body(req);
    const title = clip(b.title, 120).trim();
    const due = Math.floor(Number(b.due));
    if (!title || !Number.isFinite(due) || due < 1e9) return fail(400, "bad_request", "请填写内容和时间");
    const count = await env.DB.prepare("SELECT COUNT(*) c FROM reminders WHERE uid=?").bind(uid).first();
    if (count.c >= 1000) return fail(400, "limit", "提醒数量已达上限");
    const id = uuid();
    const rep = [0, 1, 7].includes(Number(b.rep)) ? Number(b.rep) : 0;
    await env.DB.prepare("INSERT INTO reminders(id,uid,title,body,due,rep,sent,src,updated) VALUES(?,?,?,?,?,?,0,'web',?)")
      .bind(id, uid, title, clip(b.body, 400), due, rep, now())
      .run();
    return json({ id });
  }
  let m = /^\/api\/reminders\/([\w-]{1,64})$/.exec(path);
  if (m && method === "DELETE") {
    await env.DB.prepare("DELETE FROM reminders WHERE id=? AND uid=?").bind(m[1], uid).run();
    return json({ ok: true });
  }
  if (m && method === "PUT") {
    const row = await env.DB.prepare("SELECT src FROM reminders WHERE id=? AND uid=?").bind(m[1], uid).first();
    if (!row) return fail(404, "not_found", "提醒不存在");
    if (row.src !== "web") return fail(400, "readonly", "来自 iPhone 的提醒请在 App 里修改");
    const b = await body(req);
    const sets = ["updated=?"];
    const args = [now()];
    if (typeof b.title === "string") {
      const title = clip(b.title, 120).trim();
      if (!title) return fail(400, "bad_request", "请填写内容");
      sets.push("title=?");
      args.push(title);
    }
    if (b.due != null) {
      const due = Math.floor(Number(b.due));
      if (!Number.isFinite(due) || due < 1e9) return fail(400, "bad_request", "时间不正确");
      sets.push("due=?", "sent=0"); // 改了时间（含「稍后提醒」）就重新进入待提醒
      args.push(due);
    }
    if (b.rep != null) {
      sets.push("rep=?");
      args.push([0, 1, 7].includes(Number(b.rep)) ? Number(b.rep) : 0);
    }
    await env.DB.prepare(`UPDATE reminders SET ${sets.join(",")} WHERE id=? AND uid=?`).bind(...args, m[1], uid).run();
    return json({ ok: true });
  }
  // iOS App 把待推送的提醒同步上来，由服务器到点推 Bark（App 关闭时也能准时）
  if (path === "/api/relay" && method === "POST") {
    const b = await body(req);
    const items = (Array.isArray(b.items) ? b.items : []).slice(0, 300);
    const t = now();
    const done = (
      await env.DB.prepare("SELECT ref FROM reminders WHERE uid=? AND src='ios' AND sent=1").bind(uid).all()
    ).results.map((r) => r.ref);
    const stmts = [
      env.DB.prepare("DELETE FROM reminders WHERE uid=? AND src='ios' AND sent=0").bind(uid),
    ];
    const doneSet = new Set(done);
    for (const it of items) {
      const ref = clip(it.ref, 64);
      const due = Math.floor(Number(it.due));
      if (!ref || !Number.isFinite(due) || doneSet.has(ref)) continue;
      doneSet.add(ref); // 同一批里重复的 ref 只收一次
      stmts.push(
        env.DB.prepare("INSERT INTO reminders(id,uid,title,body,due,rep,sent,src,ref,updated) VALUES(?,?,?,?,?,0,0,'ios',?,?)").bind(
          uuid(), uid, clip(it.title, 120) || "OSVIA", clip(it.body, 400), due, ref, t
        )
      );
    }
    await env.DB.batch(stmts);
    return json({ done, accepted: stmts.length - 1 });
  }

  // ----- 笔记 -----
  if (path === "/api/notes" && method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT id,title,body,updated FROM notes WHERE uid=? AND deleted=0 ORDER BY updated DESC LIMIT 300"
    )
      .bind(uid)
      .all();
    return json({ items: results });
  }
  if (path === "/api/notes" && method === "POST") {
    const b = await body(req);
    const id = uuid();
    await env.DB.prepare("INSERT INTO notes(id,uid,title,body,updated) VALUES(?,?,?,?,?)")
      .bind(id, uid, clip(b.title, 200), clip(b.body, 100_000), now())
      .run();
    return json({ id });
  }
  m = /^\/api\/notes\/([\w-]{1,64})$/.exec(path);
  if (m && method === "PUT") {
    const b = await body(req);
    const r = await env.DB.prepare("UPDATE notes SET title=?, body=?, updated=? WHERE id=? AND uid=? AND deleted=0")
      .bind(clip(b.title, 200), clip(b.body, 100_000), now(), m[1], uid)
      .run();
    return r.meta.changes ? json({ ok: true, updated: now() }) : fail(404, "not_found", "笔记不存在");
  }
  if (m && method === "DELETE") {
    await env.DB.prepare("UPDATE notes SET deleted=1, updated=? WHERE id=? AND uid=?").bind(now(), m[1], uid).run();
    return json({ ok: true });
  }

  // ----- 云备份（只收加密过的 .osvbackup） -----
  if (path === "/api/backups" && method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT id,name,size,created,device FROM backups WHERE uid=? ORDER BY created DESC"
    )
      .bind(uid)
      .all();
    return json({ items: results });
  }
  if (path === "/api/backups" && method === "PUT") {
    if (!(await limit(env, `bk:${uid}`, 20, 3600))) return fail(429, "rate_limited", "上传太频繁，请稍后再试");
    const len = Number(req.headers.get("content-length") || 0);
    if (len > 40_000_000) return fail(413, "too_large", "备份文件太大（上限 40 MB）");
    const data = await req.arrayBuffer();
    if (data.byteLength > 40_000_000) return fail(413, "too_large", "备份文件太大（上限 40 MB）");
    const head = new Uint8Array(data.slice(0, 6));
    if (head.length < 6 || String.fromCharCode(...head.slice(0, 4)) !== "OSVB")
      return fail(400, "bad_file", "不是 OSVIA 备份文件");
    if (head[5] !== 1) return fail(400, "must_encrypt", "云备份必须设置加密密码，未加密的备份不会上传");
    const used = await env.DB.prepare("SELECT COALESCE(SUM(size),0) s FROM backups WHERE uid=?").bind(uid).first();
    if (used.s + data.byteLength > 300_000_000) return fail(413, "quota", "云备份空间已满（300 MB），请先删除旧备份");
    const id = uuid();
    await env.R2.put(`u/${uid}/${id}`, data);
    await env.DB.prepare("INSERT INTO backups(id,uid,name,size,created,device) VALUES(?,?,?,?,?,?)")
      .bind(id, uid, clip(url.searchParams.get("name") || "OSVIA.osvbackup", 100), data.byteLength, now(), clip(url.searchParams.get("device"), 60))
      .run();
    // 只保留最近 10 份
    const old = (
      await env.DB.prepare("SELECT id FROM backups WHERE uid=? ORDER BY created DESC LIMIT -1 OFFSET 10").bind(uid).all()
    ).results;
    for (const o of old) {
      await env.R2.delete(`u/${uid}/${o.id}`);
      await env.DB.prepare("DELETE FROM backups WHERE id=? AND uid=?").bind(o.id, uid).run();
    }
    return json({ id });
  }
  m = /^\/api\/backups\/([\w-]{1,64})$/.exec(path);
  if (m && method === "GET") {
    const row = await env.DB.prepare("SELECT name FROM backups WHERE id=? AND uid=?").bind(m[1], uid).first();
    const obj = row && (await env.R2.get(`u/${uid}/${m[1]}`));
    if (!obj) return fail(404, "not_found", "备份不存在");
    return new Response(obj.body, {
      headers: {
        "content-type": "application/octet-stream",
        "content-length": String(obj.size),
        "content-disposition": `attachment; filename="${encodeURIComponent(row.name)}"`,
        "cache-control": "no-store",
      },
    });
  }
  if (m && method === "DELETE") {
    await env.R2.delete(`u/${uid}/${m[1]}`);
    await env.DB.prepare("DELETE FROM backups WHERE id=? AND uid=?").bind(m[1], uid).run();
    return json({ ok: true });
  }


  // ----- 内置 AI（Cloudflare Workers AI）：每人每天有次数配额 -----
  if (path === "/api/ai/quota" && method === "GET") {
    return json({ on: !!env.AI, used: await aiUsed(env, uid), max: AI.USER_DAILY });
  }

  if (path === "/api/ai/chat" && method === "POST") {
    const b = await body(req);
    const msgs = cleanMsgs(b.messages, 20, 24000);
    if (!msgs.length || msgs[msgs.length - 1].role !== "user") return fail(400, "bad_request", "没有要回答的内容");
    const gate = await aiGate(env, uid);
    if (gate) return gate;
    const today = new Date().toISOString().slice(0, 10);
    const system =
      clip(b.system, 2000).trim() ||
      `你是 OSVIA 助手，运行在 OSVIA 网页版里。用用户使用的语言回答，简洁清楚，不啰嗦；需要时用 Markdown 的列表或代码块。不知道就直说，不要编造。今天是 ${today}。`;
    try {
      const stream = await AI.chatStream(env, [{ role: "system", content: system }, ...msgs]);
      return new Response(stream, {
        headers: { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store", "x-accel-buffering": "no" },
      });
    } catch (e) {
      const f = e.friendly || AI.friendlyError(e);
      console.error("ai chat", e && e.message);
      return fail(f.status, f.error, f.message);
    }
  }

  if (path === "/api/ai/tool" && method === "POST") {
    const b = await body(req);
    const tool = String(b.tool || "");
    const text = clip(b.text, 12000).trim();
    if (!AI.toolNames().includes(tool) || !text) return fail(400, "bad_request", "请求不完整");
    const gate = await aiGate(env, uid);
    if (gate) return gate;
    try {
      const out = await AI.complete(env, AI.toolMessages(tool, text, String(b.lang || "")), 1400);
      if (!out) return fail(502, "ai_error", "没有生成内容，请再试一次");
      return json({ text: out });
    } catch (e) {
      const f = e.friendly || AI.friendlyError(e);
      console.error("ai tool", e && e.message);
      return fail(f.status, f.error, f.message);
    }
  }

  if (path === "/api/ai/reminder" && method === "POST") {
    const b = await body(req);
    const text = clip(b.text, 300).trim();
    if (!text) return fail(400, "bad_request", "请说一句话，例如「明天下午 3 点提醒我开会」");
    const gate = await aiGate(env, uid);
    if (gate) return gate;
    try {
      const r = await AI.parseReminder(env, text, Date.now(), Number.isFinite(+b.tz) ? Math.max(-840, Math.min(840, +b.tz)) : 0);
      if (!r) return fail(422, "unparsed", "没看懂这句话，换个说法试试，例如「明天下午 3 点提醒我开会」");
      return json({ reminder: r });
    } catch (e) {
      const f = e.friendly || AI.friendlyError(e);
      console.error("ai reminder", e && e.message);
      return fail(f.status, f.error, f.message);
    }
  }

  if (path === "/api/ai/web" && method === "POST") {
    const b = await body(req);
    const target = publicHttps(/^https?:\/\//i.test(String(b.url || "")) ? String(b.url).replace(/^http:/i, "https:") : "https://" + String(b.url || ""));
    if (!target) return fail(400, "bad_url", "请输入公开的网页地址，例如 https://example.com/article");
    const gate = await aiGate(env, uid);
    if (gate) return gate;
    let page;
    try {
      page = await AI.fetchPageText(target, publicHttps, new URL(req.url).hostname);
    } catch (e) {
      return fail(502, "fetch_failed", e && e.bad ? e.bad : "打不开这个网页，换一个试试");
    }
    if (page.text.length < 60) return fail(422, "empty_page", "没有读到有用的文字（可能需要登录，或页面靠脚本生成内容）");
    try {
      const out = await AI.complete(
        env,
        AI.toolMessages("summarize", `网页标题：${page.title || "（无）"}\n\n正文：\n${page.text}`, ""),
        1400
      );
      return json({ title: page.title, url: page.url, chars: page.text.length, summary: out });
    } catch (e) {
      const f = e.friendly || AI.friendlyError(e);
      console.error("ai web", e && e.message);
      return fail(f.status, f.error, f.message);
    }
  }

  // ----- 对话记录（云端保存，网页与以后的 App 通用） -----
  if (path === "/api/chats" && method === "GET") {
    const { results } = await env.DB.prepare("SELECT id,title,updated FROM chats WHERE uid=? ORDER BY updated DESC LIMIT 100").bind(uid).all();
    return json({ items: results });
  }
  if (path === "/api/chats" && method === "POST") {
    const b = await body(req);
    const c = await env.DB.prepare("SELECT COUNT(*) c FROM chats WHERE uid=?").bind(uid).first();
    if (c.c >= 200) return fail(400, "too_many", "对话太多了，先删掉一些旧的");
    const id = uuid();
    const msgs = cleanMsgs(b.msgs, 100, 300000);
    await env.DB.prepare("INSERT INTO chats(id,uid,title,msgs,updated) VALUES(?,?,?,?,?)")
      .bind(id, uid, clip(b.title, 60), JSON.stringify(msgs), now()).run();
    return json({ id });
  }
  const mc = path.match(/^\/api\/chats\/([\w-]{8,64})$/);
  if (mc && method === "GET") {
    const r = await env.DB.prepare("SELECT id,title,msgs,updated FROM chats WHERE id=? AND uid=?").bind(mc[1], uid).first();
    if (!r) return fail(404, "not_found", "对话不存在");
    let msgs = [];
    try { msgs = JSON.parse(r.msgs); } catch { /* 空 */ }
    return json({ id: r.id, title: r.title, msgs, updated: r.updated });
  }
  if (mc && method === "PUT") {
    const b = await body(req);
    const sets = ["updated=?"];
    const args = [now()];
    if (typeof b.title === "string") { sets.push("title=?"); args.push(clip(b.title, 60)); }
    if (Array.isArray(b.msgs)) { sets.push("msgs=?"); args.push(JSON.stringify(cleanMsgs(b.msgs, 100, 300000))); }
    const r = await env.DB.prepare(`UPDATE chats SET ${sets.join(",")} WHERE id=? AND uid=?`).bind(...args, mc[1], uid).run();
    if (!r.meta.changes) return fail(404, "not_found", "对话不存在");
    return json({ ok: true });
  }
  if (mc && method === "DELETE") {
    await env.DB.prepare("DELETE FROM chats WHERE id=? AND uid=?").bind(mc[1], uid).run();
    return json({ ok: true });
  }

  // ----- 网页助手：转发到用户自己配置的模型接口（密钥只在这一次请求里经过，不保存） -----
  if (path === "/api/llm" && method === "POST") {
    if (!(await limit(env, `llm:${uid}`, 60, 600))) return fail(429, "rate_limited", "请求太频繁，请稍后再试");
    const b = await body(req);
    const target = publicHttps(b.url);
    if (!target) return fail(400, "bad_url", "接口地址需要是公开的 https 地址");
    if (target.hostname === new URL(req.url).hostname) return fail(400, "bad_url", "不能指向自己");
    const allow = ["authorization", "x-api-key", "anthropic-version", "api-key", "openai-organization", "http-referer", "x-title"];
    const headers = { "content-type": "application/json" };
    for (const [k, v] of Object.entries(b.headers || {})) {
      if (allow.includes(k.toLowerCase()) && typeof v === "string") headers[k] = clip(v, 600);
    }
    let res;
    try {
      res = await fetch(target.href, { method: "POST", headers, body: JSON.stringify(b.payload ?? {}) });
    } catch {
      return fail(502, "upstream", "连不上模型接口");
    }
    return new Response(res.body, {
      status: res.status,
      headers: {
        "content-type": res.headers.get("content-type") || "application/json",
        "cache-control": "no-store",
        "x-accel-buffering": "no",
      },
    });
  }

  return fail(404, "not_found", "接口不存在");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (!url.pathname.startsWith("/api/")) return env.ASSETS.fetch(req);
    try {
      await ensure(env);
      return await handle(req, env);
    } catch (e) {
      console.error("api error", e && e.stack ? e.stack : e);
      return fail(500, "server", "服务器出错了，请稍后再试");
    }
  },

  async scheduled(event, env, ctx) {
    await ensure(env);
    await runDue(env);
    const d = new Date(event.scheduledTime);
    if (d.getUTCHours() === 3 && d.getUTCMinutes() === 0) await cleanup(env);
  },
};
