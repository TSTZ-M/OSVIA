/**
 * github-cloudflare-mcp — ONE custom MCP connector for Claude.
 *
 * A single Cloudflare Worker that exposes GitHub AND Cloudflare as MCP tools
 * over Streamable HTTP (stateless, JSON responses), so claude.ai can connect
 * to it as ONE custom MCP connector and get direct read/write access to both
 * services — no GitHub Actions workflow in between.
 *
 * Secrets are read ONLY from Worker env bindings (wrangler secrets):
 *   GITHUB_TOKEN            — GitHub personal access token (repo + workflow + admin scopes)
 *   CLOUDFLARE_API_TOKEN    — Cloudflare API token (Workers/KV/D1/R2/Pages)
 *   CLOUDFLARE_ACCOUNT_ID   — optional; Cloudflare tools also accept an account_id parameter
 *   MCP_AUTH_TOKEN          — optional; if set, /mcp requires `Authorization: Bearer <token>`
 *   BARK_KEY                — optional; Bark push key for the daily R2 quota warning
 *   TELEGRAM_BOT_TOKEN      — optional; Telegram bot token for the daily R2 quota warning
 *   TELEGRAM_CHAT_ID        — optional; Telegram chat id for the daily R2 quota warning
 *
 * R2 free quota (checked by the cf_r2_check_quota tool and the daily Cron):
 * 10 GB storage, 1M Class A ops/month, 10M Class B ops/month. Warn at 80%,
 * critical at 95%. A metric that cannot be read is reported as unknown.
 *
 * Nothing secret is hardcoded anywhere in this file.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";
import nacl from "tweetnacl";
import { blake2b } from "blakejs";

interface Env {
  GITHUB_TOKEN: string;
  CLOUDFLARE_API_TOKEN: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
  MCP_AUTH_TOKEN?: string;
  BARK_KEY?: string;
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_CHAT_ID?: string;
}

// R2 free tier (Cloudflare): 10 GB storage, 1M Class A ops / month, 10M Class B ops / month.
// Notify at 80% (warning) and 95% (critical). Never invent numbers: if a metric
// cannot be read, it is reported as unknown, not guessed.
const R2_FREE_STORAGE_BYTES = 10 * 1024 * 1024 * 1024;
const R2_WARN_PCT = 80;
const R2_CRITICAL_PCT = 95;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function textResult(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function jsonResult(value: unknown) {
  return textResult(JSON.stringify(value, null, 2));
}

class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function requireSecret(env: Env, key: "GITHUB_TOKEN" | "CLOUDFLARE_API_TOKEN"): string {
  const value = env[key];
  if (!value) {
    throw new Error(`${key} is not configured on this Worker. Set it with: wrangler secret put ${key}`);
  }
  return value;
}

/** Cloudflare account id: tool parameter wins, otherwise the env secret. */
function accountId(env: Env, override?: string): string {
  const id = override ?? env.CLOUDFLARE_ACCOUNT_ID;
  if (!id) {
    throw new Error(
      "Cloudflare account ID is required: pass account_id to the tool or set the CLOUDFLARE_ACCOUNT_ID secret.",
    );
  }
  return id;
}

/** Encode each path segment, keep the slashes (for GitHub repo file paths). */
function encPath(path: string): string {
  return path
    .split("/")
    .map((seg) => encodeURIComponent(seg))
    .join("/");
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64.replace(/\s/g, ""));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(bin);
}

function utf8ToB64(text: string): string {
  return bytesToB64(new TextEncoder().encode(text));
}

function b64ToUtf8(b64: string): string {
  return new TextDecoder().decode(b64ToBytes(b64));
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

/**
 * libsodium sealed-box encryption (what GitHub requires for repo secrets):
 *   sealed = ephemeral_public_key || box(message, nonce, recipient_pk, ephemeral_sk)
 *   nonce  = blake2b-24(ephemeral_public_key || recipient_public_key)
 * Pure JS (tweetnacl + blakejs) — no WASM, works inside a Worker.
 */
function sealSecret(plain: string, publicKeyB64: string): string {
  const recipientPk = b64ToBytes(publicKeyB64);
  const ephemeral = nacl.box.keyPair();
  const nonce = blake2b(concatBytes(ephemeral.publicKey, recipientPk), undefined, 24);
  const boxed = nacl.box(new TextEncoder().encode(plain), nonce, recipientPk, ephemeral.secretKey);
  if (!boxed) throw new Error("Failed to encrypt the secret value");
  return bytesToB64(concatBytes(ephemeral.publicKey, boxed));
}

// ---------------------------------------------------------------------------
// GitHub REST (https://api.github.com)
// ---------------------------------------------------------------------------

async function gh(env: Env, method: string, path: string, body?: unknown): Promise<any> {
  const token = requireSecret(env, "GITHUB_TOKEN");
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      "User-Agent": "github-cloudflare-mcp/1.0.0",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!res.ok) {
    const msg = data && typeof data === "object" && data.message ? String(data.message) : text;
    throw new ApiError(res.status, `GitHub ${res.status} ${method} ${path}: ${msg}`);
  }
  return data;
}

/** Current sha of a repo file, or null when the file does not exist. */
async function ghFileSha(
  env: Env,
  owner: string,
  repo: string,
  path: string,
  ref?: string,
): Promise<string | null> {
  try {
    const data = await gh(
      env,
      "GET",
      `/repos/${owner}/${repo}/contents/${encPath(path)}${ref ? `?ref=${encodeURIComponent(ref)}` : ""}`,
    );
    return typeof data?.sha === "string" ? data.sha : null;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Cloudflare REST (https://api.cloudflare.com/client/v4)
// ---------------------------------------------------------------------------

async function cf(env: Env, method: string, path: string, body?: unknown): Promise<any> {
  const token = requireSecret(env, "CLOUDFLARE_API_TOKEN");
  const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!res.ok || (data && data.success === false)) {
    const errs =
      data && Array.isArray(data.errors)
        ? data.errors.map((e: any) => e.message || JSON.stringify(e)).join("; ")
        : text;
    throw new ApiError(res.status, `Cloudflare ${res.status} ${method} ${path}: ${errs}`);
  }
  return data?.result ?? data;
}

/** Raw (non-JSON) Cloudflare GET — used for KV values, which are plain text. */
async function cfRaw(env: Env, path: string): Promise<string> {
  const token = requireSecret(env, "CLOUDFLARE_API_TOKEN");
  const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new ApiError(res.status, `Cloudflare ${res.status} GET ${path}: ${text}`);
  }
  return text;
}

// ---------------------------------------------------------------------------
// R2 free-quota check (storage via REST; operations via GraphQL, unknown on failure)
// ---------------------------------------------------------------------------

interface R2Quota {
  storageBytes: number;
  storageGB: number;
  storageLimitGB: number;
  storagePct: number;
  classAOps: number | null;
  classBOps: number | null;
  status: "ok" | "warning" | "critical";
  warnings: string[];
  buckets: { name: string; bytes: number; objects: number }[];
}

/** Sum object sizes in one bucket (paginated; caps at 10k objects per bucket). */
async function r2BucketUsage(env: Env, account: string, bucket: string): Promise<{ bytes: number; objects: number }> {
  let bytes = 0;
  let objects = 0;
  let cursor: string | undefined;
  for (let page = 0; page < 10; page++) {
    const q = new URLSearchParams({ limit: "1000" });
    if (cursor) q.set("cursor", cursor);
    const data: any = await cf(env, "GET", `/accounts/${account}/r2/buckets/${encodeURIComponent(bucket)}/objects?${q}`);
    const objs: any[] = Array.isArray(data?.objects) ? data.objects : [];
    for (const o of objs) {
      bytes += typeof o.size === "number" ? o.size : 0;
      objects++;
    }
    const truncated = data?.truncated === true;
    cursor = typeof data?.cursor === "string" && data.cursor ? data.cursor : undefined;
    if (!truncated || !cursor) break;
  }
  return { bytes, objects };
}

/** R2 operations for the current calendar month via GraphQL. Returns nulls when unavailable. */
async function r2OperationsThisMonth(env: Env, account: string): Promise<{ classA: number | null; classB: number | null }> {
  const token = requireSecret(env, "CLOUDFLARE_API_TOKEN");
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
  const end = now.toISOString();
  const query = `query($accountTag: string!, $start: Time!, $end: Time!) { viewer { accounts(filter: { accountTag: $accountTag }) { r2OperationsAdaptiveGroups(filter: { datetime_geq: $start, datetime_leq: $end }, limit: 100) { sum { count } dimensions { actionType } } } } }`;
  try {
    const res = await fetch("https://api.cloudflare.com/client/v4/graphql", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query, variables: { accountTag: account, start, end } }),
    });
    const data: any = await res.json();
    const groups: any[] = data?.data?.viewer?.accounts?.[0]?.r2OperationsAdaptiveGroups ?? [];
    if (!res.ok || !Array.isArray(groups)) return { classA: null, classB: null };
    // Class A (writes/lists): PutObject, PostObject, PutBucket, ListBuckets, ListObjects, DeleteObject, etc.
    // Class B (reads): GetObject, HeadObject, HeadBucket.
    const classA = new Set(["PutObject", "PostObject", "PutBucket", "ListBuckets", "ListObjects", "ListObjectsV2", "DeleteObject", "DeleteBucket", "CopyObject", "PutObjectAcl", "PutBucketCors", "DeleteObjects", "AbortMultipartUpload", "CompleteMultipartUpload", "CreateMultipartUpload", "UploadPart", "UploadPartCopy", "PutBucketLifecycle", "PutBucketVersioning", "ListMultipartUploads", "ListParts"]);
    let a = 0;
    let b = 0;
    let seen = false;
    for (const g of groups) {
      const n = typeof g?.sum?.count === "number" ? g.sum.count : 0;
      const action = String(g?.dimensions?.actionType ?? "");
      if (!action) continue;
      seen = true;
      if (classA.has(action)) a += n;
      else b += n;
    }
    if (!seen) return { classA: null, classB: null };
    return { classA: a, classB: b };
  } catch {
    return { classA: null, classB: null };
  }
}

async function checkR2Quota(env: Env): Promise<R2Quota> {
  const account = accountId(env);
  const bucketsData: any = await cf(env, "GET", `/accounts/${account}/r2/buckets`);
  const buckets: { name: string }[] = Array.isArray(bucketsData?.buckets) ? bucketsData.buckets : [];
  const details: { name: string; bytes: number; objects: number }[] = [];
  let totalBytes = 0;
  for (const b of buckets) {
    const name = String(b.name);
    const u = await r2BucketUsage(env, account, name);
    details.push({ name, bytes: u.bytes, objects: u.objects });
    totalBytes += u.bytes;
  }
  const storageGB = totalBytes / (1024 * 1024 * 1024);
  const storagePct = (totalBytes / R2_FREE_STORAGE_BYTES) * 100;
  const ops = await r2OperationsThisMonth(env, account);
  const warnings: string[] = [];
  let status: "ok" | "warning" | "critical" = "ok";
  if (storagePct >= R2_CRITICAL_PCT) {
    status = "critical";
    warnings.push(`R2 storage ${storagePct.toFixed(1)}% of free 10 GB — about to exceed the free quota.`);
  } else if (storagePct >= R2_WARN_PCT) {
    status = "warning";
    warnings.push(`R2 storage ${storagePct.toFixed(1)}% of free 10 GB — approaching the free quota.`);
  }
  if (ops.classA !== null && ops.classA >= 1_000_000 * (R2_CRITICAL_PCT / 100)) {
    status = "critical";
    warnings.push(`R2 Class A operations ${ops.classA} — about to exceed the free 1M/month.`);
  } else if (ops.classA !== null && ops.classA >= 1_000_000 * (R2_WARN_PCT / 100)) {
    if (status === "ok") status = "warning";
    warnings.push(`R2 Class A operations ${ops.classA} — approaching the free 1M/month.`);
  }
  if (ops.classB !== null && ops.classB >= 10_000_000 * (R2_CRITICAL_PCT / 100)) {
    status = "critical";
    warnings.push(`R2 Class B operations ${ops.classB} — about to exceed the free 10M/month.`);
  } else if (ops.classB !== null && ops.classB >= 10_000_000 * (R2_WARN_PCT / 100)) {
    if (status === "ok") status = "warning";
    warnings.push(`R2 Class B operations ${ops.classB} — approaching the free 10M/month.`);
  }
  return {
    storageBytes: totalBytes,
    storageGB: Math.round(storageGB * 1000) / 1000,
    storageLimitGB: 10,
    storagePct: Math.round(storagePct * 10) / 10,
    classAOps: ops.classA,
    classBOps: ops.classB,
    status,
    warnings,
    buckets: details,
  };
}

/** Send a quota warning. Bark when BARK_KEY is set; Telegram when bot token + chat id are set. */
async function notifyR2Quota(env: Env, quota: R2Quota): Promise<string[]> {
  const sent: string[] = [];
  const title = quota.status === "critical" ? "R2 免费额度即将超限" : "R2 免费额度提醒";
  const body = `${title}\n存储：${quota.storageGB} GB / 10 GB (${quota.storagePct}%)\nClass A：${quota.classAOps ?? "未知"} / 1,000,000\nClass B：${quota.classBOps ?? "未知"} / 10,000,000\n${quota.warnings.join("\n")}`;
  if (env.BARK_KEY) {
    try {
      const res = await fetch(`https://api.day.app/${encodeURIComponent(env.BARK_KEY)}/${encodeURIComponent(title)}/${encodeURIComponent(body)}`, { method: "GET" });
      if (res.ok) sent.push("bark");
    } catch {
      // Notification failure must not break the check; it is reported, not retried silently.
    }
  }
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
    try {
      const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text: body }),
      });
      if (res.ok) sent.push("telegram");
    } catch {
      // See above.
    }
  }
  return sent;
}

// ---------------------------------------------------------------------------
// MCP server — all tools registered here, closing over the Worker env.
// ---------------------------------------------------------------------------

function createServer(env: Env): McpServer {
  const server = new McpServer({ name: "github-cloudflare-mcp", version: "1.0.0" });

  // ============================ GitHub ============================

  server.registerTool(
    "github_list_repos",
    {
      description: "List repositories owned by the authenticated GitHub user.",
      inputSchema: {
        type: z.enum(["all", "owner", "member"]).optional().describe("Default: owner"),
        per_page: z.number().int().min(1).max(100).optional().describe("Default: 30"),
      },
    },
    async (args) => {
      const data = await gh(
        env,
        "GET",
        `/user/repos?type=${args.type ?? "owner"}&per_page=${args.per_page ?? 30}&sort=updated`,
      );
      return jsonResult(
        (data as any[]).map((r) => ({ full_name: r.full_name, private: r.private, description: r.description, default_branch: r.default_branch, updated_at: r.updated_at, html_url: r.html_url })),
      );
    },
  );

  server.registerTool(
    "github_get_repo",
    {
      description: "Get one repository's details.",
      inputSchema: { owner: z.string(), repo: z.string() },
    },
    async (args) => jsonResult(await gh(env, "GET", `/repos/${args.owner}/${args.repo}`)),
  );

  server.registerTool(
    "github_create_repo",
    {
      description: "Create a repository under the authenticated user. Defaults to private.",
      inputSchema: {
        name: z.string(),
        description: z.string().optional(),
        private: z.boolean().optional().describe("Defaults to true when omitted"),
        auto_init: z.boolean().optional(),
      },
    },
    async (args) =>
      jsonResult(
        await gh(env, "POST", "/user/repos", {
          name: args.name,
          description: args.description,
          private: args.private ?? true,
          auto_init: args.auto_init ?? false,
        }),
      ),
  );

  server.registerTool(
    "github_update_repo",
    {
      description: "Update a repository (description, visibility, default branch).",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        description: z.string().optional(),
        private: z.boolean().optional(),
        default_branch: z.string().optional(),
      },
    },
    async (args) =>
      jsonResult(
        await gh(env, "PATCH", `/repos/${args.owner}/${args.repo}`, {
          description: args.description,
          private: args.private,
          default_branch: args.default_branch,
        }),
      ),
  );

  server.registerTool(
    "github_delete_repo",
    {
      description: "Delete a repository. Irreversible.",
      inputSchema: { owner: z.string(), repo: z.string() },
    },
    async (args) => {
      await gh(env, "DELETE", `/repos/${args.owner}/${args.repo}`);
      return jsonResult({ ok: true, deleted: `${args.owner}/${args.repo}` });
    },
  );

  server.registerTool(
    "github_get_file",
    {
      description: "Read a file from a repository (decoded as text). For a directory path, lists its entries. Files over ~1 MB return a download_url instead of content.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        path: z.string().describe("Repo-relative path, e.g. src/index.ts"),
        ref: z.string().optional().describe("Branch, tag or commit sha. Default: repo default branch"),
      },
    },
    async (args) => {
      const data = await gh(
        env,
        "GET",
        `/repos/${args.owner}/${args.repo}/contents/${encPath(args.path)}${args.ref ? `?ref=${encodeURIComponent(args.ref)}` : ""}`,
      );
      if (Array.isArray(data)) {
        return jsonResult(data.map((e) => ({ name: e.name, path: e.path, type: e.type, size: e.size })));
      }
      if (data?.encoding === "base64" && typeof data.content === "string") {
        return textResult(b64ToUtf8(data.content));
      }
      return jsonResult({ name: data?.name, size: data?.size, download_url: data?.download_url ?? null, note: "Content not returned inline (too large or binary); use download_url." });
    },
  );

  server.registerTool(
    "github_write_file",
    {
      description: "Create or update a file in a repository. content is plain text (UTF-8). Creates the file when it does not exist, updates it when it does.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        path: z.string().describe("Repo-relative path, e.g. src/index.ts"),
        content: z.string().describe("Plain text file content"),
        message: z.string().describe("Commit message"),
        branch: z.string().optional(),
        sha: z.string().optional().describe("Required for updates; auto-detected when omitted"),
      },
    },
    async (args) => {
      const sha = args.sha ?? (await ghFileSha(env, args.owner, args.repo, args.path, args.branch));
      const data = await gh(env, "PUT", `/repos/${args.owner}/${args.repo}/contents/${encPath(args.path)}`, {
        message: args.message,
        content: utf8ToB64(args.content),
        sha: sha ?? undefined,
        branch: args.branch,
      });
      return jsonResult({ ok: true, path: data?.content?.path, sha: data?.content?.sha, commit: data?.commit?.sha });
    },
  );

  server.registerTool(
    "github_delete_file",
    {
      description: "Delete a file from a repository.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        path: z.string().describe("Repo-relative path"),
        message: z.string().describe("Commit message"),
        branch: z.string().optional(),
        sha: z.string().optional().describe("Auto-detected when omitted"),
      },
    },
    async (args) => {
      const sha = args.sha ?? (await ghFileSha(env, args.owner, args.repo, args.path, args.branch));
      if (!sha) throw new Error(`File not found: ${args.path}`);
      await gh(env, "DELETE", `/repos/${args.owner}/${args.repo}/contents/${encPath(args.path)}`, {
        message: args.message,
        sha,
        branch: args.branch,
      });
      return jsonResult({ ok: true, deleted: args.path });
    },
  );

  server.registerTool(
    "github_list_issues",
    {
      description: "List issues in a repository.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        state: z.enum(["open", "closed", "all"]).optional().describe("Default: open"),
        labels: z.string().optional().describe("Comma-separated label names"),
        per_page: z.number().int().min(1).max(100).optional().describe("Default: 30"),
      },
    },
    async (args) => {
      const q = new URLSearchParams({ state: args.state ?? "open", per_page: String(args.per_page ?? 30) });
      if (args.labels) q.set("labels", args.labels);
      const data = await gh(env, "GET", `/repos/${args.owner}/${args.repo}/issues?${q}`);
      return jsonResult(
        (data as any[]).map((i) => ({ number: i.number, title: i.title, state: i.state, labels: (i.labels ?? []).map((l: any) => l.name), created_at: i.created_at, html_url: i.html_url })),
      );
    },
  );

  server.registerTool(
    "github_create_issue",
    {
      description: "Create an issue in a repository.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        title: z.string(),
        body: z.string().optional(),
        labels: z.array(z.string()).optional(),
      },
    },
    async (args) =>
      jsonResult(
        await gh(env, "POST", `/repos/${args.owner}/${args.repo}/issues`, {
          title: args.title,
          body: args.body,
          labels: args.labels,
        }),
      ),
  );

  server.registerTool(
    "github_update_issue",
    {
      description: "Update an issue (title, body, or state open/closed).",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        number: z.number().int(),
        title: z.string().optional(),
        body: z.string().optional(),
        state: z.enum(["open", "closed"]).optional(),
      },
    },
    async (args) =>
      jsonResult(
        await gh(env, "PATCH", `/repos/${args.owner}/${args.repo}/issues/${args.number}`, {
          title: args.title,
          body: args.body,
          state: args.state,
        }),
      ),
  );

  server.registerTool(
    "github_list_prs",
    {
      description: "List pull requests in a repository.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        state: z.enum(["open", "closed", "all"]).optional().describe("Default: open"),
        per_page: z.number().int().min(1).max(100).optional().describe("Default: 30"),
      },
    },
    async (args) => {
      const data = await gh(
        env,
        "GET",
        `/repos/${args.owner}/${args.repo}/pulls?state=${args.state ?? "open"}&per_page=${args.per_page ?? 30}`,
      );
      return jsonResult(
        (data as any[]).map((p) => ({ number: p.number, title: p.title, state: p.state, head: p.head?.ref, base: p.base?.ref, html_url: p.html_url })),
      );
    },
  );

  server.registerTool(
    "github_create_pr",
    {
      description: "Create a pull request.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        title: z.string(),
        head: z.string().describe("Branch with the changes, e.g. feature/foo"),
        base: z.string().describe("Branch to merge into, e.g. main"),
        body: z.string().optional(),
      },
    },
    async (args) =>
      jsonResult(
        await gh(env, "POST", `/repos/${args.owner}/${args.repo}/pulls`, {
          title: args.title,
          head: args.head,
          base: args.base,
          body: args.body,
        }),
      ),
  );

  server.registerTool(
    "github_list_workflows",
    {
      description: "List GitHub Actions workflows in a repository.",
      inputSchema: { owner: z.string(), repo: z.string() },
    },
    async (args) => {
      const data = await gh(env, "GET", `/repos/${args.owner}/${args.repo}/actions/workflows`);
      return jsonResult(
        (data?.workflows ?? []).map((w: any) => ({ id: w.id, name: w.name, path: w.path, state: w.state, html_url: w.html_url })),
      );
    },
  );

  server.registerTool(
    "github_list_workflow_runs",
    {
      description: "List GitHub Actions workflow runs (optionally for one workflow).",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        workflow_id: z.union([z.number().int(), z.string()]).optional().describe("Workflow id or file name, e.g. build.yml"),
        status: z.enum(["completed", "action_required", "cancelled", "failure", "neutral", "skipped", "stale", "success", "timed_out", "in_progress", "queued", "requested", "waiting", "pending"]).optional(),
        per_page: z.number().int().min(1).max(100).optional().describe("Default: 30"),
      },
    },
    async (args) => {
      const q = new URLSearchParams({ per_page: String(args.per_page ?? 30) });
      if (args.status) q.set("status", args.status);
      const path = args.workflow_id
        ? `/repos/${args.owner}/${args.repo}/actions/workflows/${args.workflow_id}/runs?${q}`
        : `/repos/${args.owner}/${args.repo}/actions/runs?${q}`;
      const data = await gh(env, "GET", path);
      return jsonResult(
        (data?.workflow_runs ?? []).map((r: any) => ({ id: r.id, name: r.name, status: r.status, conclusion: r.conclusion, head_branch: r.head_branch, created_at: r.created_at, html_url: r.html_url })),
      );
    },
  );

  server.registerTool(
    "github_dispatch_workflow",
    {
      description: "Trigger a GitHub Actions workflow run (workflow_dispatch).",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        workflow_id: z.union([z.number().int(), z.string()]).describe("Workflow id or file name, e.g. build.yml"),
        ref: z.string().describe("Branch or tag to run on, e.g. main"),
        inputs: z.record(z.string(), z.string()).optional().describe("Workflow inputs (string values only)"),
      },
    },
    async (args) => {
      await gh(env, "POST", `/repos/${args.owner}/${args.repo}/actions/workflows/${args.workflow_id}/dispatches`, {
        ref: args.ref,
        inputs: args.inputs,
      });
      return jsonResult({ ok: true, workflow: String(args.workflow_id), ref: args.ref });
    },
  );

  server.registerTool(
    "github_list_secrets",
    {
      description: "List Actions secrets in a repository (names only — values are never readable).",
      inputSchema: { owner: z.string(), repo: z.string() },
    },
    async (args) => {
      const data = await gh(env, "GET", `/repos/${args.owner}/${args.repo}/actions/secrets`);
      return jsonResult((data?.secrets ?? []).map((s: any) => ({ name: s.name, created_at: s.created_at, updated_at: s.updated_at })));
    },
  );

  server.registerTool(
    "github_set_secret",
    {
      description: "Create or update an Actions secret. The value is sealed-box encrypted with the repo public key before upload, exactly as GitHub requires.",
      inputSchema: {
        owner: z.string(),
        repo: z.string(),
        name: z.string().describe("Secret name, e.g. CLOUDFLARE_API_TOKEN"),
        value: z.string().describe("Secret value (never logged or returned)"),
      },
    },
    async (args) => {
      const pub = await gh(env, "GET", `/repos/${args.owner}/${args.repo}/actions/secrets/public-key`);
      const encrypted = sealSecret(args.value, pub.key as string);
      await gh(env, "PUT", `/repos/${args.owner}/${args.repo}/actions/secrets/${encodeURIComponent(args.name)}`, {
        encrypted_value: encrypted,
        key_id: pub.key_id,
      });
      return jsonResult({ ok: true, name: args.name });
    },
  );

  server.registerTool(
    "github_delete_secret",
    {
      description: "Delete an Actions secret from a repository.",
      inputSchema: { owner: z.string(), repo: z.string(), name: z.string() },
    },
    async (args) => {
      await gh(env, "DELETE", `/repos/${args.owner}/${args.repo}/actions/secrets/${encodeURIComponent(args.name)}`);
      return jsonResult({ ok: true, deleted: args.name });
    },
  );

  // ============================ Cloudflare ============================

  server.registerTool(
    "cf_workers_list_scripts",
    {
      description: "List Workers scripts in a Cloudflare account.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => jsonResult(await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/workers/scripts`)),
  );

  server.registerTool(
    "cf_workers_deploy",
    {
      description: "Upload / deploy a Workers script (ES module). Creates the script when it does not exist, replaces it when it does.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        script_name: z.string(),
        script: z.string().describe("Worker source code (ES module)"),
        compatibility_date: z.string().optional().describe("e.g. 2026-11-13"),
        bindings: z
          .array(z.record(z.string(), z.unknown()))
          .optional()
          .describe("Optional metadata bindings, e.g. [{type:'kv_namespace', name:'KV', namespace_id:'...'}]"),
      },
    },
    async (args) => {
      const token = requireSecret(env, "CLOUDFLARE_API_TOKEN");
      const metadata: Record<string, unknown> = { main_module: "worker.js" };
      if (args.compatibility_date) metadata.compatibility_date = args.compatibility_date;
      if (args.bindings) metadata.bindings = args.bindings;
      const form = new FormData();
      form.append("metadata", new Blob([JSON.stringify(metadata)], { type: "application/json" }));
      form.append("worker.js", new File([args.script], "worker.js", { type: "application/javascript+module" }));
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId(env, args.account_id)}/workers/scripts/${encodeURIComponent(args.script_name)}`,
        { method: "PUT", headers: { Authorization: `Bearer ${token}` }, body: form },
      );
      const text = await res.text();
      let data: any = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = text;
      }
      if (!res.ok || (data && data.success === false)) {
        const errs =
          data && Array.isArray(data.errors)
            ? data.errors.map((e: any) => e.message || JSON.stringify(e)).join("; ")
            : text;
        throw new ApiError(res.status, `Cloudflare ${res.status} deploy ${args.script_name}: ${errs}`);
      }
      return jsonResult({ ok: true, script: args.script_name, id: data?.result?.id ?? null });
    },
  );

  server.registerTool(
    "cf_workers_delete_script",
    {
      description: "Delete a Workers script.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        script_name: z.string(),
      },
    },
    async (args) => {
      await cf(env, "DELETE", `/accounts/${accountId(env, args.account_id)}/workers/scripts/${encodeURIComponent(args.script_name)}`);
      return jsonResult({ ok: true, deleted: args.script_name });
    },
  );

  server.registerTool(
    "cf_kv_list_namespaces",
    {
      description: "List KV namespaces in a Cloudflare account.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => jsonResult(await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/storage/kv/namespaces`)),
  );

  server.registerTool(
    "cf_kv_list_keys",
    {
      description: "List keys in a KV namespace.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        namespace_id: z.string(),
        prefix: z.string().optional(),
        limit: z.number().int().min(1).max(1000).optional().describe("Default: 1000"),
      },
    },
    async (args) => {
      const q = new URLSearchParams({ limit: String(args.limit ?? 1000) });
      if (args.prefix) q.set("prefix", args.prefix);
      return jsonResult(
        await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/storage/kv/namespaces/${args.namespace_id}/keys?${q}`),
      );
    },
  );

  server.registerTool(
    "cf_kv_get_value",
    {
      description: "Read a KV value as text.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        namespace_id: z.string(),
        key: z.string(),
      },
    },
    async (args) =>
      textResult(
        await cfRaw(
          env,
          `/accounts/${accountId(env, args.account_id)}/storage/kv/namespaces/${args.namespace_id}/values/${encodeURIComponent(args.key)}`,
        ),
      ),
  );

  server.registerTool(
    "cf_kv_put_value",
    {
      description: "Write a KV value (plain text).",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        namespace_id: z.string(),
        key: z.string(),
        value: z.string(),
        expiration_ttl: z.number().int().positive().optional().describe("Seconds until expiry"),
      },
    },
    async (args) => {
      const token = requireSecret(env, "CLOUDFLARE_API_TOKEN");
      const q = args.expiration_ttl ? `?expiration_ttl=${args.expiration_ttl}` : "";
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId(env, args.account_id)}/storage/kv/namespaces/${args.namespace_id}/values/${encodeURIComponent(args.key)}${q}`,
        { method: "PUT", headers: { Authorization: `Bearer ${token}` }, body: args.value },
      );
      if (!res.ok) throw new ApiError(res.status, `Cloudflare ${res.status} PUT KV ${args.key}: ${await res.text()}`);
      return jsonResult({ ok: true, key: args.key });
    },
  );

  server.registerTool(
    "cf_kv_delete_value",
    {
      description: "Delete a KV key.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        namespace_id: z.string(),
        key: z.string(),
      },
    },
    async (args) => {
      await cf(env, "DELETE", `/accounts/${accountId(env, args.account_id)}/storage/kv/namespaces/${args.namespace_id}/values/${encodeURIComponent(args.key)}`);
      return jsonResult({ ok: true, deleted: args.key });
    },
  );

  server.registerTool(
    "cf_d1_list_databases",
    {
      description: "List D1 databases in a Cloudflare account.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => jsonResult(await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/d1/database`)),
  );

  server.registerTool(
    "cf_d1_query",
    {
      description: "Run a SQL query against a D1 database. Read-only queries and writes both work; keep writes intentional.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        database_id: z.string(),
        sql: z.string(),
        params: z.array(z.unknown()).optional().describe("Bound parameters for ? placeholders"),
      },
    },
    async (args) =>
      jsonResult(
        await cf(env, "POST", `/accounts/${accountId(env, args.account_id)}/d1/database/${args.database_id}/query`, {
          sql: args.sql,
          params: args.params,
        }),
      ),
  );

  server.registerTool(
    "cf_r2_list_buckets",
    {
      description: "List R2 buckets in a Cloudflare account.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => jsonResult(await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/r2/buckets`)),
  );

  server.registerTool(
    "cf_r2_list_objects",
    {
      description: "List objects in an R2 bucket.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        bucket: z.string(),
        prefix: z.string().optional(),
        limit: z.number().int().min(1).max(1000).optional().describe("Default: 1000"),
      },
    },
    async (args) => {
      const q = new URLSearchParams({ limit: String(args.limit ?? 1000) });
      if (args.prefix) q.set("prefix", args.prefix);
      return jsonResult(
        await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/r2/buckets/${encodeURIComponent(args.bucket)}/objects?${q}`),
      );
    },
  );

  server.registerTool(
    "cf_pages_list_projects",
    {
      description: "List Pages projects in a Cloudflare account.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => jsonResult(await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/pages/projects`)),
  );

  server.registerTool(
    "cf_r2_check_quota",
    {
      description: "Check R2 usage against the free tier (10 GB storage, 1M Class A ops/month, 10M Class B ops/month). Returns storage used, operation counts, percentage, and a warning when approaching (80%+) or about to exceed (95%+) the free quota. Operation counts are unknown when the analytics query cannot be read — never guessed.",
      inputSchema: { account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID") },
    },
    async (args) => {
      const account = accountId(env, args.account_id);
      const quota = await checkR2Quota({ ...env, CLOUDFLARE_ACCOUNT_ID: account });
      return jsonResult(quota);
    },
  );

  server.registerTool(
    "cf_pages_list_deployments",
    {
      description: "List deployments of a Pages project.",
      inputSchema: {
        account_id: z.string().optional().describe("Defaults to CLOUDFLARE_ACCOUNT_ID"),
        project_name: z.string(),
      },
    },
    async (args) =>
      jsonResult(
        await cf(env, "GET", `/accounts/${accountId(env, args.account_id)}/pages/projects/${encodeURIComponent(args.project_name)}/deployments`),
      ),
  );

  return server;
}

// ---------------------------------------------------------------------------
// Worker entrypoint — Streamable HTTP, stateless, JSON responses.
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response(
        JSON.stringify({ name: "github-cloudflare-mcp", version: "1.0.0", mcp_endpoint: "/mcp" }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    if (url.pathname !== "/mcp") {
      return new Response("Not found", { status: 404 });
    }

    // Optional shared-secret guard. Only enforced when MCP_AUTH_TOKEN is set.
    if (env.MCP_AUTH_TOKEN) {
      if (request.headers.get("Authorization") !== `Bearer ${env.MCP_AUTH_TOKEN}`) {
        return new Response("Unauthorized", { status: 401 });
      }
    }

    const server = createServer(env);
    const transport = new WebStandardStreamableHTTPServerTransport({
      sessionIdGenerator: undefined, // stateless — required for Workers
      enableJsonResponse: true, // plain JSON instead of SSE
    });
    await server.connect(transport);
    return transport.handleRequest(request);
  },

  // Cron: daily R2 free-quota check. Sends a push notification (Bark and/or
  // Telegram, when their secrets are set) only when usage hits warning (80%+)
  // or critical (95%+). No notification when usage is fine.
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      (async () => {
        try {
          const quota = await checkR2Quota(env);
          if (quota.status !== "ok") {
            await notifyR2Quota(env, quota);
          }
        } catch (err) {
          console.error("R2 quota cron check failed:", err instanceof Error ? err.message : String(err));
        }
      })(),
    );
  },
};
