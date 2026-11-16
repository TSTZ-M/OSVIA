import Foundation

// MARK: 邮箱服务器自动识别
// 顺序：内置预设（不联网）→ 域名自己发布的配置 + Mozilla ISPDB → 查 MX 记录判断托管方（企业邮箱、自己域名的 Google / 微软 / 腾讯 / 阿里 / 网易邮箱）。
struct MailServers {
    var imap: String
    var imapPort = 993
    var smtp: String
    var smtpPort = 465
    var providerID = ""          // 对应 Mail.providers 里的预设（有授权码说明、设置页链接）
    var source = ""              // 怎么识别出来的，显示给用户看
}

enum MailAutoconfig {
    static func detect(_ domain: String) async -> MailServers? {
        let d = domain.lowercased().trimmingCharacters(in: .whitespaces)
        guard d.contains(".") else { return nil }
        async let a = fetchConfig("https://autoconfig.\(d)/mail/config-v1.1.xml", d)
        async let b = fetchConfig("https://\(d)/.well-known/autoconfig/mail/config-v1.1.xml", d)
        async let c = fetchConfig("https://autoconfig.thunderbird.net/v1.1/\(d)", d)
        let (ra, rb, rc) = await (a, b, c)
        if var r = ra ?? rb { r.source = "域名自带配置"; return r }
        if var r = rc { r.source = "Mozilla 邮箱配置库"; return r }
        return await byMX(d)
    }

    // MARK: autoconfig XML
    private final class Parser: NSObject, XMLParserDelegate {
        struct Srv { var type = ""; var host = ""; var port = 0; var socket = "" }
        var servers: [Srv] = []
        private var cur: Srv?
        private var text = ""

        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            text = ""
            if name == "incomingServer" || name == "outgoingServer" {
                cur = Srv(type: a["type"] ?? "")
            }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }

        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "hostname": cur?.host = t
            case "port": cur?.port = Int(t) ?? 0
            case "socketType": cur?.socket = t.uppercased()
            case "incomingServer", "outgoingServer":
                if let c = cur { servers.append(c) }
                cur = nil
            default: break
            }
            text = ""
        }
    }

    private static func fetchConfig(_ url: String, _ domain: String) async -> MailServers? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 6
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200, d.count < 200_000 else { return nil }
        let p = Parser()
        let x = XMLParser(data: d)
        x.delegate = p
        guard x.parse() else { return nil }
        func fix(_ h: String) -> String {
            h.replacingOccurrences(of: "%EMAILDOMAIN%", with: domain).replacingOccurrences(of: "%MXDOMAIN%", with: domain)
        }
        // IMAP 只支持隐式 TLS（993）；SMTP 支持 465（SSL）和 587（STARTTLS）
        guard let imap = p.servers.first(where: { $0.type == "imap" && ($0.socket == "SSL" || $0.socket == "TLS") && $0.port == 993 && !$0.host.isEmpty }) else { return nil }
        let smtps = p.servers.filter { $0.type == "smtp" && !$0.host.isEmpty && [465, 587].contains($0.port) }
        guard let smtp = smtps.first(where: { $0.port == 465 }) ?? smtps.first else { return nil }
        return MailServers(imap: fix(imap.host), imapPort: 993, smtp: fix(smtp.host), smtpPort: smtp.port)
    }

    // MARK: 按 MX 记录识别托管方
    private static let hosting: [(suffixes: [String], s: MailServers)] = [
        (["google.com", "googlemail.com"], MailServers(imap: "imap.gmail.com", smtp: "smtp.gmail.com", providerID: "gmail", source: "Google Workspace")),
        (["mail.protection.outlook.com", "outlook.com", "office365.com"], MailServers(imap: "outlook.office365.com", smtp: "smtp.office365.com", smtpPort: 587, providerID: "outlook", source: "Microsoft 365")),
        (["exmail.qq.com", "qq.com"], MailServers(imap: "imap.exmail.qq.com", smtp: "smtp.exmail.qq.com", providerID: "exmail", source: "腾讯企业邮箱")),
        (["mxhichina.com", "qiye.aliyun.com", "aliyun.com"], MailServers(imap: "imap.qiye.aliyun.com", smtp: "smtp.qiye.aliyun.com", providerID: "qiye-aliyun", source: "阿里企业邮箱")),
        (["qiye.163.com", "qiye.126.com", "qiye.yeah.net"], MailServers(imap: "imap.qiye.163.com", smtp: "smtp.qiye.163.com", providerID: "qiye-163", source: "网易企业邮箱")),
        (["zoho.com", "zohomail.com"], MailServers(imap: "imap.zoho.com", smtp: "smtp.zoho.com", providerID: "zoho", source: "Zoho Mail")),
        (["zoho.com.cn", "zohomail.com.cn"], MailServers(imap: "imap.zoho.com.cn", smtp: "smtp.zoho.com.cn", providerID: "zoho", source: "Zoho Mail")),
        (["messagingengine.com"], MailServers(imap: "imap.fastmail.com", smtp: "smtp.fastmail.com", providerID: "fastmail", source: "Fastmail")),
        (["icloud.com", "me.com"], MailServers(imap: "imap.mail.me.com", smtp: "smtp.mail.me.com", smtpPort: 587, providerID: "icloud", source: "iCloud 自定义域名")),
        (["yahoodns.net"], MailServers(imap: "imap.mail.yahoo.com", smtp: "smtp.mail.yahoo.com", providerID: "yahoo", source: "Yahoo"))
    ]

    private static func mxHosts(_ domain: String) async -> [String] {
        guard let u = URL(string: "https://cloudflare-dns.com/dns-query?name=\(domain)&type=MX") else { return [] }
        var r = URLRequest(url: u)
        r.timeoutInterval = 6
        r.setValue("application/dns-json", forHTTPHeaderField: "accept")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let ans = j["Answer"] as? [[String: Any]] else { return [] }
        return ans.compactMap { ($0["type"] as? Int) == 15 ? ($0["data"] as? String) : nil }
            .compactMap { $0.split(separator: " ").last.map { String($0).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) } }
    }

    private static func byMX(_ domain: String) async -> MailServers? {
        for h in await mxHosts(domain) {
            for e in hosting where e.suffixes.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return e.s }
        }
        return nil
    }
}
