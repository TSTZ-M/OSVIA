// 极简 Markdown → HTML（先整体转义再加标签，所以输出安全）。服务端分享页用；public/app.js 里有同一份逻辑。
export function renderMd(src) {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const inline = (s) =>
    esc(s)
      .replace(/`([^`\n]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
      .replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer nofollow">$1</a>');
  const parts = String(src || "").split(/```/);
  return parts
    .map((p, i) => {
      if (i % 2 === 1) return "<pre><code>" + esc(p.replace(/^[^\n]*\n/, "")) + "</code></pre>";
      const out = [];
      let list = null; // "ul" | "ol"
      let para = [];
      const flush = () => {
        if (para.length) out.push("<p>" + para.join("<br>") + "</p>");
        para = [];
      };
      const close = () => {
        if (list) out.push(`</${list}>`);
        list = null;
      };
      for (const line of p.split("\n")) {
        let m;
        if (!line.trim()) { flush(); close(); continue; }
        if ((m = /^(#{1,4})\s+(.+)$/.exec(line))) { flush(); close(); out.push(m[1].length <= 2 ? `<h3>${inline(m[2])}</h3>` : `<h4>${inline(m[2])}</h4>`); continue; }
        if (/^-{3,}\s*$/.test(line)) { flush(); close(); out.push("<hr>"); continue; }
        if ((m = /^>\s?(.*)$/.exec(line))) { flush(); close(); out.push(`<blockquote>${inline(m[1])}</blockquote>`); continue; }
        if ((m = /^\s*[-*•]\s+(.+)$/.exec(line))) { flush(); if (list !== "ul") { close(); out.push("<ul>"); list = "ul"; } out.push(`<li>${inline(m[1])}</li>`); continue; }
        if ((m = /^\s*\d+[.)]\s+(.+)$/.exec(line))) { flush(); if (list !== "ol") { close(); out.push("<ol>"); list = "ol"; } out.push(`<li>${inline(m[1])}</li>`); continue; }
        close();
        para.push(inline(line));
      }
      flush();
      close();
      return out.join("");
    })
    .join("");
}
