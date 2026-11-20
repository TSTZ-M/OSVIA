import SwiftUI
import UIKit
import AVFoundation

// 朗读回答（朗读语言跟随应用当前语言）
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    @Published var speakingId: UUID?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String, id: UUID) {
        if speakingId == id {
            synth.stopSpeaking(at: .immediate)
            speakingId = nil
            return
        }
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let plain = text.replacingOccurrences(of: "[*#`>_]", with: "", options: .regularExpression)
        let u = AVSpeechUtterance(string: plain)
        u.voice = AVSpeechSynthesisVoice(language: L10n.info.locale)
        speakingId = id
        synth.speak(u)
    }

    // 助理主动朗读（speak 工具）：可指定语言；没指定就用应用当前语言
    func say(_ text: String, lang: String? = nil) {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let plain = text.replacingOccurrences(of: "[*#`>_]", with: "", options: .regularExpression)
        let u = AVSpeechUtterance(string: plain)
        u.voice = AVSpeechSynthesisVoice(language: (lang?.isEmpty ?? true) ? L10n.info.locale : lang)
        speakingId = UUID()
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speakingId = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }
}

struct ThinkingView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(Brand.mint)
                .symbolEffect(.pulse, isActive: true)
            Text("思考中…").foregroundStyle(Brand.sub)
        }
    }
}

// 一条消息：我的消息在右侧浅色气泡；助理的回答直接排在页面上（Markdown、可复制、朗读、重新生成）
struct MessageView: View {
    let m: Msg
    let isLast: Bool
    @Binding var preview: URL?
    var onRegenerate: () -> Void
    @ObservedObject private var speaker = Speaker.shared
    @State private var copied = false

    var body: some View {
        if m.role == "user" { user } else { assistant }
    }

    var user: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(m.files, id: \.self) { FileCard(url: $0, preview: $preview) }
            if !m.text.isEmpty {
                Text(m.text)
                    .fontSz(17)
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Brand.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu {
                        Button { UIPasteboard.general.string = m.text } label: { Label("复制", systemImage: "doc.on.doc") }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 44)
    }

    var assistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(m.files, id: \.self) { FileCard(url: $0, preview: $preview) }
            if !m.steps.isEmpty {
                ProcessView(steps: m.steps, streaming: m.streaming, hasText: !m.text.isEmpty, dur: m.dur)
            }
            if m.text.isEmpty && m.streaming {
                if m.steps.isEmpty { ThinkingView() }
            } else if !m.text.isEmpty {
                MarkdownText(text: m.text)
            }
            if !m.sources.isEmpty && !m.text.isEmpty { SourceChips(sources: m.sources) }
            if !m.streaming && !m.text.isEmpty { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var actions: some View {
        HStack(spacing: 20) {
            Button {
                UIPasteboard.general.string = m.text
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
            Button { speaker.toggle(m.text, id: m.id) } label: {
                Image(systemName: speaker.speakingId == m.id ? "speaker.slash" : "speaker.wave.2")
            }
            ExportMenu(text: m.text)
            if isLast {
                Button { onRegenerate() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .fontSz(15)
        .foregroundStyle(Brand.sub)
        .padding(.top, 2)
    }
}

// MARK: 分享对话（链接 / 图片 / 文字）
struct ShareView: View {
    @ObservedObject var agent = Agent.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scope = 0
    @State private var url: URL?
    @State private var image: UIImage?
    @State private var saved = false
    @State private var linking = false
    @State private var link: URL?
    @State private var linkErr = ""
    @State private var linkCopied = false

    var chosen: [Msg] { scope == 1 ? Array(agent.msgs.suffix(2)) : Array(agent.msgs.suffix(30)) }

    private var linkTitle: String {
        if let t = agent.msgs.first(where: { $0.role == "user" })?.text, !t.isEmpty { return String(t.prefix(20)) }
        return Brand.name + " · " + L10n.tr("对话")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $scope) {
                        Text("整段对话").tag(0)
                        Text("最近一轮").tag(1)
                    }
                    .pickerStyle(.segmented)

                    // 一键发送对话链接：生成网页链接后直接弹出系统分享面板。样式由 PrimaryButtonStyle 保证深浅色下都清晰
                    Button { sendLink() } label: {
                        HStack(spacing: 8) {
                            if linking { ProgressView() } else { Image(systemName: "link") }
                            Text(linking ? "正在生成链接…" : (link == nil ? "发送对话链接" : "重新生成并发送链接"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(linking)
                    if !linkErr.isEmpty {
                        Text(linkErr).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let link {
                        HStack(spacing: 10) {
                            Text(link.absoluteString).font(.footnote).foregroundStyle(Brand.sub).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button {
                                UIPasteboard.general.string = link.absoluteString
                                linkCopied = true
                            } label: { Image(systemName: linkCopied ? "checkmark" : "doc.on.doc") }
                            ShareLink(item: link) { Image(systemName: "square.and.arrow.up") }
                        }
                        .padding(12)
                        .background(Brand.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("链接 90 天有效，知道链接的人都能看到这段对话。").font(.footnote).foregroundStyle(Brand.sub).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    }
                    if let url, let image {
                        ShareLink(item: url, preview: SharePreview(linkTitle, image: Image(uiImage: image))) {
                            Label("分享图片到微信、QQ、微博等", systemImage: "photo").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            saved = true
                        } label: {
                            Label(saved ? "已保存到相册" : "保存到相册", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    ShareLink(item: agent.transcript(chosen)) {
                        Label("分享文字", systemImage: "text.bubble").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(Brand.bg)
            .navigationTitle("分享对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task(id: scope) { render() }
            .onChange(of: scope) { _, _ in link = nil; linkErr = "" }
        }
        .presentationBackground(Brand.bg)
    }

    func sendLink() {
        linking = true
        linkErr = ""
        linkCopied = false
        let ms = chosen
        let t = linkTitle
        Task {
            let r = await ShareService.publish(title: t, msgs: ms)
            linking = false
            guard let u = r.0 else { linkErr = r.1; return }
            link = u
            UIPasteboard.general.string = u.absoluteString
            linkCopied = true
            let vc = UIActivityViewController(activityItems: [u], applicationActivities: nil)
            UIApplication.shared.topVC?.present(vc, animated: true)
        }
    }

    @MainActor func render() {
        let r = ImageRenderer(content: ShareCard(msgs: chosen))
        r.scale = 3
        guard let img = r.uiImage, let d = img.pngData() else { return }
        let u = Store.dir("Outputs").appendingPathComponent(Brand.name + " Chat.png")
        try? d.write(to: u)
        image = img
        url = u
        saved = false
    }
}

// 分享图片：按 OSVIA 设计包排版——深灰黑底、荷绿点缀、用户气泡靠右、助理回答在带边框的卡片里。
// 所有文字（标签、标语、页脚）都跟随应用当前语言。
struct ShareCard: View {
    let msgs: [Msg]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    BrandGlyph(size: 30)
                    Text(verbatim: Brand.name).font(.system(size: 19, weight: .bold)).foregroundStyle(BrandPalette.ink)
                }
                Spacer()
                Text(verbatim: L10n.tr("对话分享")).font(.system(size: 11)).tracking(1).foregroundStyle(BrandPalette.sub)
            }
            Text(verbatim: L10n.tr("把事情做得更清晰。"))
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(BrandPalette.ink)
                .lineSpacing(2)
                .padding(.top, 24)
            Rectangle().fill(BrandPalette.line).frame(height: 1).padding(.top, 18).padding(.bottom, 18)

            VStack(spacing: 12) {
                ForEach(msgs) { m in
                    if m.role == "user" {
                        HStack {
                            Spacer(minLength: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: L10n.tr("用户")).font(.system(size: 10)).tracking(0.5).foregroundStyle(BrandPalette.mint)
                                Text(verbatim: m.text.isEmpty ? "[" + L10n.tr("文件") + "]" : String(m.text.prefix(300)))
                                    .font(.system(size: 15))
                                    .foregroundStyle(BrandPalette.ink)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(BrandPalette.bubble)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: Brand.name).font(.system(size: 14, weight: .bold)).foregroundStyle(BrandPalette.mint)
                            Text(verbatim: m.text.isEmpty ? "[" + L10n.tr("文件") + "]" : String(m.text.prefix(500)))
                                .font(.system(size: 15))
                                .foregroundStyle(BrandPalette.ink)
                                .lineSpacing(5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(BrandPalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BrandPalette.line, lineWidth: 1))
                    }
                }
            }

            Rectangle().fill(BrandPalette.line).frame(height: 1).padding(.top, 26).padding(.bottom, 16)
            Text(verbatim: L10n.f("由「{}」生成", Brand.name)).font(.system(size: 13)).foregroundStyle(BrandPalette.sub)
            Text(verbatim: L10n.tr("开发者微信：TSTZ-M")).font(.system(size: 16, weight: .bold)).foregroundStyle(BrandPalette.mint).padding(.top, 6)
            Text(verbatim: L10n.tr("搜索 · 思考 · 行动")).font(.system(size: 10)).tracking(1).foregroundStyle(BrandPalette.sub).padding(.top, 26)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(BrandPalette.bg)
        .environment(\.colorScheme, .dark)
    }
}
