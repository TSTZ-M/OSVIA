import SwiftUI

// MARK: 回答过程：时间线（回忆 → 搜索 → 读网页 → 计算 → 调用 MCP …）与来源
// 回答还没开始时自动展开，让人看到它在做什么；开始写答案后自动收成一行，点开可以回看。
struct ProcessView: View {
    let steps: [Step]
    let streaming: Bool
    let hasText: Bool
    let dur: Double
    @State private var open: Bool?

    private var running: Step? { steps.last(where: { $0.state == 0 }) }
    private var expanded: Bool { open ?? (streaming && !hasText) }
    private var live: Bool { streaming && !hasText }

    private var summary: String {
        if let r = running { return r.title + "…" }
        if streaming { return hasText ? L10n.tr("正在回答") : L10n.tr("正在整理回答") }
        let n = steps.count
        let t = dur >= 0.5 ? " · " + String(format: "%.1f", dur) + " " + L10n.tr("秒") : ""
        return L10n.f("已完成 {} 个步骤", "\(n)") + t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { open = !expanded }
            } label: {
                HStack(spacing: 9) {
                    if streaming {
                        ProgressView().controlSize(.mini).tint(Brand.mint)
                    } else {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Brand.mint)
                    }
                    Text(verbatim: summary)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(live ? Brand.ink : Brand.sub)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.sub.opacity(0.7))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { s in
                        StepRow(step: s, last: s.id == steps.last?.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Brand.codeBg)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(live ? Brand.mint.opacity(0.35) : Color.clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.snappy(duration: 0.28), value: steps)
    }
}

struct StepRow: View {
    let step: Step
    let last: Bool

    private var tint: Color { step.state == 2 ? Color.orange : Brand.mint }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 26, height: 26)
                    Image(systemName: step.state == 2 ? "exclamationmark" : step.kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.pulse, isActive: step.state == 0)
                }
                if !last {
                    Rectangle().fill(Brand.line).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: step.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(step.state == 0 ? Brand.ink : Brand.ink.opacity(0.85))
                if !step.detail.isEmpty {
                    Text(verbatim: step.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.sub)
                        .lineLimit(step.kind == .plan ? 10 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 3)
            .padding(.bottom, last ? 4 : 12)
            Spacer(minLength: 4)
            if step.state == 0 {
                ProgressView().controlSize(.mini).padding(.top, 7)
            } else if step.secs >= 0.5 {
                Text(verbatim: String(format: "%.1fs", step.secs))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Brand.sub.opacity(0.8))
                    .padding(.top, 7)
            }
        }
    }
}

// 来源：搜索和读网页时登记的链接，回答里的 [1] [2] 对应这里的编号
struct SourceChips: View {
    let sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("来源").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sources) { s in
                        if let u = URL(string: s.url) {
                            Link(destination: u) {
                                HStack(spacing: 7) {
                                    Text(verbatim: "\(s.n)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Brand.onMint)
                                        .frame(width: 18, height: 18)
                                        .background(Brand.mint)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(verbatim: s.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(Brand.ink)
                                            .lineLimit(1)
                                        Text(verbatim: s.host)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Brand.sub)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: 170, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Brand.codeBg)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }
}
