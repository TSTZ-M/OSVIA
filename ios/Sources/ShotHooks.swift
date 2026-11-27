// 云端 CI 启动自检与截图用：只编进模拟器版本，正式 IPA 里没有这段代码
#if targetEnvironment(simulator)
import SwiftUI

enum ShotHooks {
    private static var done = false

    @MainActor static func apply() {
        guard !done, let screen = ProcessInfo.processInfo.environment["OSVIA_SHOT"] else { return }
        done = true
        let id = seed()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            switch screen {
            case "empty": break
            case "chat": Agent.shared.open(id)
            case "drawer":
                Agent.shared.open(id)
                AppState.shared.drawer = true
            default: AppState.shared.page = AppPage(rawValue: screen)
            }
        }
    }

    private static func seed() -> Int {
        let now = Date().timeIntervalSince1970
        func conv(_ title: String, _ ago: Double, pin: Int, _ msgs: [(String, String)]) -> Int {
            let c = Int(DB.shared.run("INSERT INTO conv(title,ts) VALUES(?,?)", [title, now - ago]))
            DB.shared.run("UPDATE conv SET pin=? WHERE id=?", [pin, c])
            for m in msgs {
                DB.shared.run("INSERT INTO msg(role,text,ts,conv,files,meta) VALUES(?,?,?,?,?,?)", [m.0, m.1, now - ago, c, "", ""])
            }
            return c
        }
        _ = conv("周末东京行程", 86_400 * 3, pin: 0, [("user", "帮我排一下周末东京的行程"), ("assistant", "好的。")])
        _ = conv("季度汇报提纲", 86_400, pin: 1, [("user", "写个季度汇报提纲"), ("assistant", "好的。")])
        let answer = """
        ## 三步整理好
        1. **收集**：把截图和文件发给我
        2. **整理**：自动识别文字并归类
        3. **提醒**：需要跟进的事项加到提醒事项

        | 项目 | 状态 |
        |---|---|
        | 识别 | 完成 |
        | 归类 | 进行中 |

        ```swift
        let greeting = "你好"
        print(greeting)
        ```
        > 需要我现在开始吗？
        """
        return conv("资料整理方法", 60, pin: 0, [("user", "怎么高效整理一堆截图和文件？给个步骤，再给一段示例代码。"), ("assistant", answer)])
    }
}
#endif
