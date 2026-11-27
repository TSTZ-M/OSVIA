#!/usr/bin/env python3
"""扫描 Swift 源码里所有写死的中文界面文案，生成 Sources/L10nCatalog.swift。
运行时切换语言：手写翻译表优先，其余由系统翻译在本机补译（含英文）。新增界面文字后重新运行即可。"""
import os, re, sys, glob

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SRC = os.path.join(ROOT, 'Sources')
OUT = os.path.join(SRC, 'L10nCatalog.swift')
CJK = re.compile(r'[一-鿿㐀-䶿]')
SKIP_FILES = {'AICatalog.swift', 'AIIcon.swift', 'Nlp.swift', 'L10nCatalog.swift', 'L10nTable.swift', 'L10nExtra.swift', 'L10nExtra2.swift', 'L10nUI.swift', 'L10n.swift', 'ShotHooks.swift'}
# 语言本名、品牌名之类不翻译
KEEP = {'简体中文', '繁體中文', '日本語', '한국어'}
# 这些行里的字符串是用来「匹配」的关键词，或是发给大模型的内容，不会显示给用户
SKIP_LINE = re.compile(r'has\(\[|hasAny\(|ToolResult\(|\bs \+= "- |NSRegularExpression|\.range\(of:|\.contains\("|\.contains\(\[|hasPrefix\(|hasSuffix\(|== "|!= "|components\(separatedBy: "|replacingOccurrences\(of: "|^\s*case "|regex|Regex|pattern')

def table_keys():
    keys = set()
    for f in ('L10nTable.swift', 'L10nExtra.swift', 'L10nExtra2.swift'):
        for line in open(os.path.join(SRC, f), encoding='utf8'):
            if ' ⇒ ' in line:
                keys.add(line.split(' ⇒ ')[0].replace('\\n', '\n'))
    return keys

ESC = {'n': '\n', 't': '\t', 'r': '', '"': '"', '\\': '\\', "'": "'", '0': ''}

def scan(src, rel):
    out = []  # (line, text)
    n = len(src)

    def line_of(i):
        return src.count('\n', 0, i) + 1

    def parse_string(i):
        j = i + 1
        buf = []
        while j < n:
            ch = src[j]
            if ch == '\\' and j + 1 < n:
                nx = src[j + 1]
                if nx == '(':
                    depth, k = 1, j + 2
                    while k < n and depth > 0:
                        c = src[k]
                        if c == '"':
                            k = parse_string(k)
                            continue
                        if c == '(':
                            depth += 1
                        elif c == ')':
                            depth -= 1
                        k += 1
                    buf.append('{}')
                    j = k
                    continue
                if nx == 'u' and j + 2 < n and src[j + 2] == '{':
                    e = src.find('}', j)
                    try:
                        buf.append(chr(int(src[j + 3:e], 16)))
                    except Exception:
                        pass
                    j = e + 1
                    continue
                buf.append(ESC.get(nx, nx))
                j += 2
                continue
            if ch == '"':
                out.append((line_of(i), ''.join(buf)))
                return j + 1
            if ch == '\n':
                return j
            buf.append(ch)
            j += 1
        return j

    i = 0
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            e = src.find('\n', i)
            i = n if e < 0 else e
        elif src.startswith('/*', i):
            e = src.find('*/', i + 2)
            i = n if e < 0 else e + 2
        elif src.startswith('"""', i):
            e = src.find('"""', i + 3)
            i = n if e < 0 else e + 3
        elif c == '#' and re.match(r'#+"', src[i:i + 8]):
            m = re.match(r'(#+)("""|")', src[i:i + 8])
            close = m.group(2) + m.group(1)
            e = src.find(close, i + len(m.group(0)))
            i = n if e < 0 else e + len(close)
        elif c == '"':
            i = parse_string(i)
        else:
            i += 1
    return out

def main():
    have = table_keys()
    found = {}
    for f in sorted(glob.glob(SRC + '/*.swift') + glob.glob(os.path.join(ROOT, 'Live', '*.swift')) + glob.glob(os.path.join(ROOT, 'Shared', '*.swift'))):
        b = os.path.basename(f)
        if b in SKIP_FILES:
            continue
        text = open(f, encoding='utf8').read()
        lines = text.split('\n')
        for ln, s in scan(text, b):
            if not CJK.search(s) or len(s) > 160 or '\n' in s.strip('\n') and len(s) > 120:
                continue
            if SKIP_LINE.search(lines[ln - 1]):
                continue
            fixed = s.replace('{}', '')
            if '{}' in s and len(CJK.findall(fixed)) < 2:
                continue
            if s in have or s in KEEP or s.startswith('\n') or len(CJK.findall(s.replace('{}', ''))) < 2:
                continue
            found[s] = True
            # 拼接出来的多句文字按「。」和换行拆开逐句翻译，所以每一句也单独收一份
            if '。' in s or '\n' in s:
                for part in re.split(r'[。\n]', s):
                    part = part.strip()
                    if part and len(CJK.findall(part.replace('{}', ''))) >= 2 and part not in have and part not in KEEP:
                        found[part] = True
    keys = sorted(found)
    with open(OUT, 'w', encoding='utf8') as w:
        w.write('// 由 tools/gen-l10n-catalog.py 自动生成，请勿手改。收集代码里全部中文界面文案，切换语言时由系统翻译补译。\n')
        w.write('enum L10nCatalog {\n    static let keys: [String] = raw.split(separator: "\\n", omittingEmptySubsequences: true).map { String($0).replacingOccurrences(of: "\\\\n", with: "\\n") }\n\n    static let raw = #"""\n')
        for k in keys:
            w.write(k.replace('\n', '\\n') + '\n')
        w.write('"""#\n}\n')
    print('catalog keys:', len(keys))

main()
