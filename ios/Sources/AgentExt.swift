import Foundation

// 对话里的扩展动作：写入消息、识别文字（直接显示结果）、调用连接器
extension Agent {
    // 追加一条消息并写入对话记录（回调、连接器结果都走这里）。助理消息按当前语言翻译
    func post(_ role: String, _ text: String, files: [URL] = []) {
        let text = role == "assistant" ? L10n.tr(text) : text
        msgs.append(Msg(role: role, text: text, files: files))
        guard UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? true else { return }
        let now = Date().timeIntervalSince1970
        if convId == 0 {
            let title = role == "user" ? String(text.prefix(16)) : "新对话"
            convId = Int(DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", [title.isEmpty ? "文件" : title, now]))
        }
        let json = (try? JSONEncoder().encode(files.map { Store.rel($0) })).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DB.shared.run("INSERT INTO msg(role,text,ts,conv,files) VALUES(?,?,?,?,?)", [role, text, now, convId, json])
        DB.shared.run("UPDATE conv SET ts=? WHERE id=?", [now, convId])
    }

    // 识别图片文字，直接把文字显示在对话里（可长按复制）
    func recognize(_ files: [URL]) async {
        guard !busy else { return }
        busy = true
        attachments = []
        post("user", L10n.tr("识别文字"), files: files)
        let texts = await Task.detached { files.map { OCR.text($0) } }.value
        var parts: [String] = []
        for (i, t) in texts.enumerated() {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            parts.append(texts.count > 1 ? L10n.f("第 {} 张：", "\(i + 1)") + "\n\(s)" : s)
        }
        post("assistant", parts.isEmpty ? "没有识别到文字。可以换一张更清晰的图，或直接告诉我要对这张图做什么。" : parts.joined(separator: "\n\n"))
        busy = false
    }

    // 附件上的一键转换：不经过大模型，转完把文件直接放进对话
    func quickConvert(_ files: [URL], to target: String, label: String) async {
        guard !busy else { return }
        busy = true
        attachments = []
        lastFile = files.last
        post("user", label, files: files)
        var outs: [URL] = []
        var errs: [String] = []
        for f in files {
            do { outs += try await Convert.run(f, to: target) } catch { errs.append(f.lastPathComponent + "：" + error.localizedDescription) }
        }
        if outs.isEmpty {
            post("assistant", "转换失败。\n" + errs.joined(separator: "\n"))
        } else {
            let tip = errs.isEmpty ? "" : "\n\n没转成功：\n" + errs.joined(separator: "\n")
            post("assistant", "已完成，共 \(outs.count) 个文件。点开可预览，长按可分享或存入相册。" + tip, files: outs)
        }
        busy = false
    }

    // 调用连接器：结果直接显示在对话里
    func runConnector(_ name: String, _ input: String, shown: String? = nil) async {
        guard !busy else { return }
        busy = true
        post("user", shown ?? "🔗 \(name)：\(input)")
        let out = await Connectors.run(name, input, limit: 3000)
        post("assistant", out)
        busy = false
    }
}
