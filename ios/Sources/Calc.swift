import Foundation

// 精确计算器：自己写的递归下降解析，不用 NSExpression（输入不合法时它会直接让 App 崩溃）。
// 支持 + - * / % ^ 括号、百分号，以及 sqrt abs sin cos tan asin acos atan log ln log2 exp round floor ceil pow min max，常量 pi e。三角函数用弧度。
enum Calc {
    static func eval(_ text: String) -> Double? {
        var s = text.lowercased()
        for (a, b) in [("×", "*"), ("÷", "/"), ("（", "("), ("）", ")"), ("，", ","), ("**", "^"), ("−", "-"), ("＋", "+"), ("＝", ""), ("=", ""), ("π", "pi")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        // 千分位 1,234,567 → 1234567（只处理「数字,三位数字」的情形，不影响函数参数里的逗号）
        if !s.contains(where: { $0.isLetter }) {
            s = s.replacingOccurrences(of: "(?<=\\d),(?=\\d{3}(?!\\d))", with: "", options: .regularExpression)
        }
        let p = Parser(s)
        let v = p.expr()
        p.skip()
        guard !p.failed, p.i == p.c.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return String(format: "%.10g", v)
    }

    private final class Parser {
        let c: [Character]
        var i = 0
        var failed = false
        private var depth = 0

        init(_ s: String) { c = Array(s) }

        func skip() { while i < c.count, c[i] == " " { i += 1 } }

        func peek() -> Character? {
            skip()
            return i < c.count ? c[i] : nil
        }

        func expr() -> Double {
            depth += 1
            defer { depth -= 1 }
            if depth > 60 {
                failed = true
                return 0
            }
            var v = term()
            while !failed, let ch = peek(), ch == "+" || ch == "-" {
                i += 1
                let r = term()
                v = ch == "+" ? v + r : v - r
            }
            return v
        }

        private func startsTerm(_ ch: Character?) -> Bool {
            guard let ch else { return false }
            return ch.isNumber || ch == "(" || ch == "." || ch.isLetter
        }

        func term() -> Double {
            var v = power()
            while !failed, let ch = peek(), ch == "*" || ch == "/" || ch == "%" {
                i += 1
                if ch == "%" {
                    if startsTerm(peek()) {
                        let r = power()
                        v = r == 0 ? Double.nan : v.truncatingRemainder(dividingBy: r)
                    } else {
                        v /= 100
                    }
                    continue
                }
                let r = power()
                v = ch == "*" ? v * r : v / r
            }
            return v
        }

        func power() -> Double {
            let base = unary()
            if !failed, peek() == "^" {
                i += 1
                let e = power()
                return pow(base, e)
            }
            return base
        }

        func unary() -> Double {
            guard let ch = peek() else {
                failed = true
                return 0
            }
            if ch == "-" {
                i += 1
                return -unary()
            }
            if ch == "+" {
                i += 1
                return unary()
            }
            return primary()
        }

        func primary() -> Double {
            guard let ch = peek() else {
                failed = true
                return 0
            }
            if ch == "(" {
                i += 1
                let v = expr()
                if peek() == ")" { i += 1 } else { failed = true }
                return postfixPercent(v)
            }
            if ch.isNumber || ch == "." { return postfixPercent(number()) }
            if ch.isLetter {
                var name = ""
                while i < c.count, c[i].isLetter || c[i].isNumber {
                    name.append(c[i])
                    i += 1
                }
                if peek() == "(" {
                    i += 1
                    var args: [Double] = [expr()]
                    while !failed, peek() == "," {
                        i += 1
                        args.append(expr())
                    }
                    if peek() == ")" { i += 1 } else { failed = true }
                    return postfixPercent(apply(name, args))
                }
                switch name {
                case "pi": return postfixPercent(Double.pi)
                case "e": return postfixPercent(M_E)
                default:
                    failed = true
                    return 0
                }
            }
            failed = true
            return 0
        }

        // 「50%」写在数字后面且后面不是新的项时表示除以 100（term 里处理了取余的情形，这里只处理括号、数字后紧跟的百分号）
        private func postfixPercent(_ v: Double) -> Double { v }

        func number() -> Double {
            var s = ""
            while i < c.count, c[i].isNumber || c[i] == "." {
                s.append(c[i])
                i += 1
            }
            // 科学计数法：2e3、1.5e-4（e 后面必须紧跟数字或正负号加数字）
            if i < c.count, c[i] == "e" {
                var j = i + 1
                if j < c.count, c[j] == "+" || c[j] == "-" { j += 1 }
                if j < c.count, c[j].isNumber {
                    s.append(contentsOf: String(c[i..<j]))
                    i = j
                    while i < c.count, c[i].isNumber {
                        s.append(c[i])
                        i += 1
                    }
                }
            }
            guard let v = Double(s) else {
                failed = true
                return 0
            }
            return v
        }

        func apply(_ name: String, _ a: [Double]) -> Double {
            func one() -> Double? { a.count == 1 ? a[0] : nil }
            switch name {
            case "sqrt": if let x = one(), x >= 0 { return x.squareRoot() }
            case "abs": if let x = one() { return abs(x) }
            case "sin": if let x = one() { return sin(x) }
            case "cos": if let x = one() { return cos(x) }
            case "tan": if let x = one() { return tan(x) }
            case "asin": if let x = one() { return asin(x) }
            case "acos": if let x = one() { return acos(x) }
            case "atan": if let x = one() { return atan(x) }
            case "log", "log10": if let x = one(), x > 0 { return log10(x) }
            case "ln": if let x = one(), x > 0 { return log(x) }
            case "log2": if let x = one(), x > 0 { return log2(x) }
            case "exp": if let x = one() { return exp(x) }
            case "round": if let x = one() { return x.rounded() }
            case "floor": if let x = one() { return floor(x) }
            case "ceil": if let x = one() { return ceil(x) }
            case "pow": if a.count == 2 { return pow(a[0], a[1]) }
            case "min": if a.count >= 2 { return a.min() ?? 0 }
            case "max": if a.count >= 2 { return a.max() ?? 0 }
            default: break
            }
            failed = true
            return 0
        }
    }
}
