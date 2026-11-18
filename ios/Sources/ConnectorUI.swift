import SwiftUI
import UIKit

// 聊天「+」里的连接器中心：选用、测试、一键添加常用连接器
struct ConnectorHub: View {
    var onUse: (Row) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var note = ""
    @State private var testing = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("点一个连接器，回到聊天后输入内容发送，结果直接显示在对话里。也可以直接说「用 币安价格 查 BTCUSDT」。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("已连接") {
                    if rows.isEmpty { Text("还没有连接器，从下面一键添加").foregroundStyle(.secondary) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, elem in
                        Button {
                            onUse(elem)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Connectors.icon(elem.s("kind"))).foregroundStyle(Color.accentColor).frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(elem.s("name")).foregroundStyle(.primary)
                                    Text(sub(elem)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if testing == elem.s("name") { ProgressView() }
                            }
                        }
                        .contextMenu {
                            Button { test(elem) } label: { Label("测试一下", systemImage: "play.circle") }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { Connectors.remove(rows[i].i("id")) }
                        reload()
                    }
                }
                if !note.isEmpty {
                    Section("结果") { Text(note).font(.subheadline).textSelection(.enabled) }
                }
                Section("一键添加（免费，无需密钥）") {
                    ForEach(Connectors.presets) { p in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name)
                                Text(p.about).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if rows.contains(where: { $0.s("name") == p.name }) {
                                Text("已添加").font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button("添加") {
                                    Connectors.addPreset(p)
                                    reload()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section("高级") {
                    NavigationLink("自定义与管理（快捷指令、Scriptable、网络接口）") { ConnectorsView() }
                    Button {
                        UIPasteboard.general.string = Connectors.scriptableTemplate
                        note = "已复制 Scriptable 回调模板。新建一个 Scriptable 脚本粘贴进去，再在这里添加同名的「Scriptable 脚本」连接器，运行结果会自动回到对话。"
                    } label: { Label("复制 Scriptable 回调脚本模板", systemImage: "doc.on.doc") }
                }
            }
            .navigationTitle("连接器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear(perform: reload)
        }
    }

    func sub(_ r: Row) -> String {
        let h = Connectors.hint(r.s("name"))
        return h.isEmpty ? Connectors.kindName(r.s("kind")) : h
    }

    func reload() { rows = Connectors.all() }

    func test(_ r: Row) {
        let n = r.s("name")
        testing = n
        Task {
            let sample = DB.shared.kv("connsample." + n) ?? ""
            let out = await Connectors.run(n, sample, limit: 800)
            note = "「\(n)」测试结果：\n" + out
            testing = ""
        }
    }
}
