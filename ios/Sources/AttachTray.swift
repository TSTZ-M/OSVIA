import SwiftUI

// 「+」托盘：展开在输入框下面（像 iMessage 的应用抽屉），聊天内容会上移让出位置，不再盖住屏幕
struct AttachTray: View {
    let conns: [Row]
    let activeConn: String
    var onCamera: () -> Void
    var onPhoto: () -> Void
    var onFile: () -> Void
    var onPaste: () -> Void
    var onTool: (ToolKind) -> Void
    var onPage: (AppPage) -> Void
    var onClock: () -> Void
    var onConn: (String) -> Void
    var onConnManage: () -> Void
    @Environment(\.dynamicTypeSize) private var dts

    // 大字号下磁贴跟着变宽变高，标签不会被截断；默认字号保持 72
    private var tileW: CGFloat { dts.isAccessibilitySize ? 96 : (dts >= .xxxLarge ? 84 : 72) }

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        var accent = false
        let action: () -> Void
    }

    private var items: [Item] {
        var list: [Item] = ToolKind.allCases.map { k in
            Item(id: "tool-" + k.rawValue, icon: k.icon, title: k.title, accent: true) { onTool(k) }
        }
        list.append(Item(id: "mail", icon: "envelope", title: "邮箱") { onPage(.mail) })
        list.append(Item(id: "mcp", icon: "puzzlepiece.extension", title: "MCP 服务") { onPage(.mcp) })
        list.append(Item(id: "memory", icon: "brain.head.profile", title: "AI 记忆") { onPage(.memory) })
        list.append(Item(id: "clock", icon: "alarm", title: "闹钟") { onClock() })
        for c in conns {
            let n = c.s("name")
            list.append(Item(id: "conn-" + n, icon: Connectors.icon(c.s("kind")), title: n) { onConn(n) })
        }
        list.append(Item(id: "conn-manage", icon: "link.badge.plus", title: conns.isEmpty ? "连接器" : "管理连接器") { onConnManage() })
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                source("camera", "拍照", onCamera)
                source("photo", "照片", onPhoto)
                source("folder", "文件", onFile)
                source("doc.on.clipboard", "粘贴", onPaste)
            }
            Text("动手工具").fontSz(12, weight: .semibold).foregroundStyle(Brand.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(tileW), spacing: 6), GridItem(.fixed(tileW), spacing: 6)], spacing: 8) {
                    ForEach(items) { it in tile(it) }
                }
                .padding(.trailing, 4)
            }
            .frame(height: tileW * 2 + 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.bg)
    }

    private func source(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).fontSz(20, weight: .medium).foregroundStyle(Brand.ink)
                Text(label).fontSz(12.5).foregroundStyle(Brand.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(Brand.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ it: Item) -> some View {
        let selected = it.id == "conn-" + activeConn
        return Button(action: it.action) {
            VStack(spacing: 5) {
                Image(systemName: it.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(it.accent ? Brand.mint : Brand.ink)
                    .frame(width: 48, height: 44)
                    .background(it.accent ? Brand.mint.opacity(0.14) : Brand.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? Brand.mint : .clear, lineWidth: 1.5))
                Text(it.title).fontSz(11.5).foregroundStyle(Brand.sub).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(width: tileW)
        }
        .buttonStyle(.plain)
    }
}
