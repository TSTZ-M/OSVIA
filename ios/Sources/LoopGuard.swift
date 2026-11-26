import Foundation
import JavaScriptCore

// MARK: 死循环保护
// 脚本在 JavaScriptCore 里没法从外部强行终止，所以运行前给每个 for / while / do 循环体插入 __tick()，
// 超过次数或时间就在脚本内部抛出错误，让线程自己结束。改写器本身是一段 JS（在独立上下文里运行），
// 解析不确定时返回原代码，调用方再回退。
enum LoopGuard {
    static let maxTicks = 5_000_000
    static let maxSeconds: Double = 25

    static func instrument(_ code: String) -> String {
        guard code.contains("for") || code.contains("while") || code.contains("do"), code.utf8.count < 200_000 else { return code }
        guard let ctx = JSContext() else { return code }
        ctx.evaluateScript(source)
        guard let r = ctx.objectForKeyedSubscript("__instrument")?.call(withArguments: [code]),
              r.isString, let s = r.toString(), !s.isEmpty else { return code }
        return s
    }

    private static let source = #"""
// 给脚本里的 for / while / do 循环体插入 __tick()，用来在死循环时主动中止。
// 解析不完整时返回原代码，由调用方回退，所以这里宁可少插也不乱改。
function __instrument(src) {
  var n = src.length, out = [], i = 0, prev = "", prevWord = "";
  var stack = [], doClosed = false;
  var KW = { "if": 1, "for": 1, "while": 1, "do": 1, "return": 1, "break": 1, "continue": 1, "var": 1, "let": 1, "const": 1,
    "switch": 1, "try": 1, "throw": 1, "function": 1, "class": 1, "else": 1, "async": 1, "await": 1, "yield": 1, "new": 1, "typeof": 1, "delete": 1, "void": 1 };
  var REGEX_AFTER = { "return": 1, "typeof": 1, "case": 1, "delete": 1, "void": 1, "throw": 1, "in": 1, "of": 1, "new": 1, "instanceof": 1, "else": 1, "do": 1 };
  function isIdStart(c) { return /[A-Za-z_$\u0080-￿]/.test(c); }
  function isIdPart(c) { return /[A-Za-z0-9_$\u0080-￿]/.test(c); }
  function skipString(s, q) { var j = s + 1; while (j < n && src[j] !== q) { if (src[j] === "\\") j++; j++; } return Math.min(j + 1, n); }
  function skipTemplate(s) {
    var j = s + 1;
    while (j < n) {
      var c = src[j];
      if (c === "\\") { j += 2; continue; }
      if (c === "`") return j + 1;
      if (c === "$" && src[j + 1] === "{") { j = skipBraces(j + 1); continue; }
      j++;
    }
    return n;
  }
  function skipRegex(s) {
    var j = s + 1, cls = false;
    while (j < n) {
      var c = src[j];
      if (c === "\\") { j += 2; continue; }
      if (c === "\n") return s + 1;
      if (cls) { if (c === "]") cls = false; }
      else if (c === "[") cls = true;
      else if (c === "/") { j++; while (j < n && isIdPart(src[j])) j++; return j; }
      j++;
    }
    return s + 1;
  }
  // 跳过一个字符串、模板、注释；不是这些就返回 -1
  function unit(j) {
    var c = src[j];
    if (c === '"' || c === "'") return skipString(j, c);
    if (c === "`") return skipTemplate(j);
    if (c === "/" && src[j + 1] === "/") { var e = src.indexOf("\n", j); return e < 0 ? n : e; }
    if (c === "/" && src[j + 1] === "*") { var e2 = src.indexOf("*/", j + 2); return e2 < 0 ? n : e2 + 2; }
    return -1;
  }
  function skipBraces(s) {
    var d = 0, j = s;
    while (j < n) {
      var u = unit(j);
      if (u > 0) { j = u; continue; }
      var c = src[j];
      if (c === "{") d++;
      else if (c === "}") { d--; if (d === 0) return j + 1; }
      j++;
    }
    return n;
  }
  function skipParens(s) {
    var d = 0, j = s;
    while (j < n) {
      var u = unit(j);
      if (u > 0) { j = u; continue; }
      var c = src[j];
      if (c === "(") d++;
      else if (c === ")") { d--; if (d === 0) return j + 1; }
      j++;
    }
    return -1;
  }
  function regexAllowed() {
    if (prev === "") return true;
    if ("(,=:[!&|?{};+-*%<>~^".indexOf(prev) >= 0) return true;
    return !!REGEX_AFTER[prevWord];
  }
  // 从 j 起跳过空白与注释，返回 [位置, 跳过的文本]
  function gap(j) {
    var s = j;
    for (;;) {
      while (j < n && /\s/.test(src[j])) j++;
      var u = (src[j] === "/" && (src[j + 1] === "/" || src[j + 1] === "*")) ? unit(j) : -1;
      if (u > 0) { j = u; continue; }
      break;
    }
    return [j, src.slice(s, j)];
  }
  while (i < n) {
    var c = src[i];
    var u = unit(i);
    if (u > 0) {
      out.push(src.slice(i, u)); i = u;
      if (c === '"' || c === "'" || c === "`") { prev = '"'; prevWord = ""; doClosed = false; }
      continue;
    }
    if (c === "/" && regexAllowed()) {
      var re = skipRegex(i);
      if (re > i + 1) { out.push(src.slice(i, re)); i = re; prev = '"'; prevWord = ""; doClosed = false; continue; }
    }
    if (/\s/.test(c)) { out.push(c); i++; continue; }
    if (isIdStart(c)) {
      var e = i + 1;
      while (e < n && isIdPart(src[e])) e++;
      var w = src.slice(i, e);
      var wasDoClosed = doClosed;
      doClosed = false;
      if (prev !== "." && (w === "for" || w === "while" || w === "do")) {
        if (w === "while" && wasDoClosed) {
          // do { } while (cond) 的条件部分，原样保留
        } else if (w === "do") {
          var g = gap(e);
          if (src[g[0]] === "{") {
            out.push("do", g[1], "{__tick();");
            stack.push(true);
            i = g[0] + 1; prev = "{"; prevWord = ""; continue;
          }
        } else {
          var g1 = gap(e);
          if (src[g1[0]] === "(") {
            var close = skipParens(g1[0]);
            if (close > 0) {
              out.push(src.slice(i, close));
              var g2 = gap(close), k = g2[0];
              if (src[k] === "{") {
                out.push(g2[1], "{__tick();");
                stack.push(false);
                i = k + 1; prev = "{"; prevWord = ""; continue;
              }
              if (src[k] === ";") {
                out.push(g2[1], "{__tick();}");
                i = k + 1; prev = ";"; prevWord = ""; continue;
              }
              var m = /^[A-Za-z_$][\w$]*/.exec(src.slice(k, k + 64));
              if ((m && !KW[m[0]]) || src[k] === "(") out.push(g2[1], "__tick(),");
              else out.push(g2[1]);
              i = k; prev = ")"; prevWord = ""; continue;
            }
          }
        }
      }
      out.push(w); i = e; prev = w[w.length - 1]; prevWord = w; continue;
    }
    if (c === "{") { stack.push(false); out.push(c); i++; prev = c; prevWord = ""; doClosed = false; continue; }
    if (c === "}") { doClosed = stack.length ? stack.pop() === true : false; out.push(c); i++; prev = c; prevWord = ""; continue; }
    doClosed = false;
    out.push(c); i++; prev = c; prevWord = "";
  }
  return out.join("");
}
"""#
}
