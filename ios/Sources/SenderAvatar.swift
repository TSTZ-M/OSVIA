import SwiftUI
import UIKit

// MARK: 发件人头像
// 企业 / 品牌邮箱：取对方官网图标（本机缓存，失败 7 天内不再重试）；个人邮箱和取不到图标时：彩色首字母。
enum SenderID {
    // 个人邮箱域名：发件人是「人」，用首字母，不去取域名图标
    static let free: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
        "qq.com", "foxmail.com", "vip.qq.com", "163.com", "126.com", "yeah.net", "188.com", "vip.163.com", "sina.com", "sina.cn",
        "139.com", "yahoo.com", "ymail.com", "rocketmail.com", "aliyun.com", "sohu.com", "21cn.com", "proton.me", "protonmail.com",
        "zoho.com", "fastmail.com", "fastmail.fm", "gmx.com", "gmx.net", "mail.com", "yandex.com", "yandex.ru", "mail.ru", "naver.com",
        "hanmail.net", "web.de", "live.cn", "outlook.cn", "tom.com", "wo.cn", "189.cn", "wo.com.cn"
    ]
    private static let twoLevel: Set<String> = [
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "co.uk", "org.uk", "ac.uk", "com.au", "co.jp", "com.hk", "com.tw", "co.kr",
        "co.in", "com.br", "com.sg", "co.nz", "com.mx", "com.tr", "co.za"
    ]

    static func host(_ addr: String) -> String {
        (addr.split(separator: "@").last.map(String.init) ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    }

    // 注册域名：e.nike.com → nike.com；mail.foo.com.cn → foo.com.cn
    static func domain(_ addr: String) -> String {
        let labels = host(addr).split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host(addr) }
        let two = labels.suffix(2).joined(separator: ".")
        if labels.count >= 3, twoLevel.contains(two) { return labels.suffix(3).joined(separator: ".") }
        return two
    }

    // 值得取品牌图标的域名；个人邮箱、内网域名返回空
    static func brand(_ addr: String) -> String {
        let d = domain(addr)
        guard d.contains("."), !free.contains(host(addr)), !free.contains(d) else { return "" }
        for bad in ["amazonses.com", "sendgrid.net", "mailchimp.com", "mcsv.net", "mandrillapp.com", "mailgun.org", "sparkpostmail.com", "bounces.google.com"] where d == bad { return "" }
        return d
    }

    static func initials(_ name: String, _ addr: String) -> String {
        var n = name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'[]()【】「」<>"))
        if n.isEmpty { n = String(addr.split(separator: "@").first ?? "") }
        let words = n.split { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" }.map(String.init).filter { !$0.isEmpty }
        func head(_ s: String) -> String {
            guard let c = s.first(where: { $0.isLetter || $0.isNumber }) else { return "" }
            return String(c).uppercased()
        }
        // 中日韩：取第一个字；拉丁文：两个单词取首字母，一个单词取一个
        if let f = words.first, let c = f.first, c.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return String(c) }
        let letters = words.prefix(2).map(head).joined()
        return letters.isEmpty ? "?" : letters
    }

    static let palette: [(Color, Color)] = [
        (Color(red: 0.99, green: 0.58, blue: 0.36), Color(red: 0.93, green: 0.40, blue: 0.30)),
        (Color(red: 0.27, green: 0.78, blue: 0.72), Color(red: 0.12, green: 0.58, blue: 0.62)),
        (Color(red: 0.42, green: 0.64, blue: 0.99), Color(red: 0.27, green: 0.44, blue: 0.90)),
        (Color(red: 0.70, green: 0.57, blue: 0.98), Color(red: 0.52, green: 0.38, blue: 0.88)),
        (Color(red: 0.97, green: 0.52, blue: 0.70), Color(red: 0.86, green: 0.33, blue: 0.55)),
        (Color(red: 0.47, green: 0.81, blue: 0.47), Color(red: 0.28, green: 0.64, blue: 0.40)),
        (Color(red: 0.98, green: 0.77, blue: 0.32), Color(red: 0.90, green: 0.58, blue: 0.18)),
        (Color(red: 0.58, green: 0.65, blue: 0.75), Color(red: 0.40, green: 0.47, blue: 0.58))
    ]

    static func colors(_ seed: String) -> (Color, Color) {
        var h: UInt32 = 5381
        for u in seed.lowercased().unicodeScalars { h = h &* 33 &+ u.value }
        return palette[Int(h % UInt32(palette.count))]
    }
}

@MainActor
final class SenderLogos {
    static let shared = SenderLogos()
    static let enabledKey = "mail.logos"

    private let mem = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let dir: URL
    private let failKey = "senderlogo.fail"

    private init() {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("senderlogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
        mem.countLimit = 300
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func cached(_ domain: String) -> UIImage? { mem.object(forKey: domain as NSString) }

    func clear() {
        mem.removeAllObjects()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: failKey)
    }

    private func failed(_ d: String) -> Bool {
        let m = UserDefaults.standard.dictionary(forKey: failKey) as? [String: Double] ?? [:]
        guard let t = m[d] else { return false }
        return Date().timeIntervalSince1970 - t < 7 * 86400
    }

    private func markFailed(_ d: String) {
        var m = UserDefaults.standard.dictionary(forKey: failKey) as? [String: Double] ?? [:]
        if m.count > 400 { m = m.filter { Date().timeIntervalSince1970 - $0.value < 7 * 86400 } }
        m[d] = Date().timeIntervalSince1970
        UserDefaults.standard.set(m, forKey: failKey)
    }

    func image(for domain: String, force: Bool = false) async -> UIImage? {
        if let i = cached(domain) { return i }
        let file = dir.appendingPathComponent(domain + ".png")
        if let d = try? Data(contentsOf: file), let i = UIImage(data: d) {
            mem.setObject(i, forKey: domain as NSString)
            return i
        }
        guard enabled || force, !failed(domain) else { return nil }
        if let t = inflight[domain] { return await t.value }
        let t = Task { await self.fetch(domain) }
        inflight[domain] = t
        let img = await t.value
        inflight[domain] = nil
        if let img {
            mem.setObject(img, forKey: domain as NSString)
            if let png = img.pngData() { try? png.write(to: file) }
        } else {
            markFailed(domain)
        }
        return img
    }

    // 同时最多 4 个请求，列表一次出现几十个发件人也不会把网络占满
    private func gate() async {
        if running < 4 { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }

    private func fetch(_ d: String) async -> UIImage? {
        await gate()
        defer { release() }
        let urls = ["https://\(d)/apple-touch-icon.png", "https://www.\(d)/apple-touch-icon.png",
                    "https://www.google.com/s2/favicons?domain=\(d)&sz=128", "https://icons.duckduckgo.com/ip3/\(d).ico"]
        for u in urls {
            if let url = URL(string: u), let img = await download(url) { return img }
        }
        return nil
    }

    private func download(_ url: URL) async -> UIImage? {
        var r = URLRequest(url: url)
        r.timeoutInterval = 6
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              d.count > 200, d.count < 2_000_000, let img = UIImage(data: d) else { return nil }
        return img.size.width * img.scale >= 32 ? img : nil
    }
}

struct SenderAvatar: View {
    let name: String
    let addr: String
    var size: CGFloat = 40
    var unread = false
    @State private var img: UIImage?

    var body: some View {
        let domain = SenderID.brand(addr)
        let logo = img ?? (domain.isEmpty ? nil : SenderLogos.shared.cached(domain))
        ZStack {
            if let logo {
                Color.white
                if logo.size.width * logo.scale >= 150 {
                    Image(uiImage: logo).resizable().scaledToFill()
                } else {
                    Image(uiImage: logo).resizable().scaledToFit().padding(size * 0.2)
                }
            } else {
                let c = SenderID.colors(addr.isEmpty ? name : addr)
                LinearGradient(colors: [c.0, c.1], startPoint: .top, endPoint: .bottom)
                Text(verbatim: SenderID.initials(name, addr))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .overlay(alignment: .topLeading) {
            if unread {
                Circle().fill(Brand.mint).frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().stroke(Brand.card, lineWidth: 2))
                    .offset(x: -size * 0.04, y: -size * 0.04)
            }
        }
        .accessibilityHidden(true)
        .task(id: addr) {
            guard !domain.isEmpty else { img = nil; return }
            let i = await SenderLogos.shared.image(for: domain)
            if i !== img { withAnimation(.easeOut(duration: 0.2)) { img = i } }
        }
    }
}
