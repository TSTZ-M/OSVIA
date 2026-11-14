import SwiftUI
import UIKit

// 统一的外观：全部使用 iOS 系统颜色，浅色、深色由系统自动切换，不再有任何自定义色值（没有色差）。
enum Brand {
    // 应用名 OSVIA，品牌语「Search · Think · Act」
    static let name = "OSVIA"
    static let tagline = "搜索 · 思考 · 行动"

    // 强调色：浅色模式为黑，深色模式为白（系统 label）；放在它上面的文字用 onAccent
    static let accent = Color(UIColor.label)
    static let onAccent = Color(UIColor.systemBackground)
    // 对话页、侧栏的底色
    static let bg = Color(UIColor.systemBackground)
    // 设置、任务等分组页面的底色，卡片用 card（与系统「设置」App 相同的层次）
    static let page = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let userBubble = Color(UIColor.tertiarySystemFill)
    static let codeBg = Color(UIColor.secondarySystemBackground)
    static let line = Color(UIColor.separator)
    static let ink = Color(UIColor.label)
    static let sub = Color(UIColor.secondaryLabel)
    static let serif = Font.system(size: 17, design: .serif)

    // 品牌点缀色（薄荷绿）：只用在「正在进行」「可操作」的地方——发送按钮、过程时间线、来源编号、功能入口。浅色模式用深一档以保证白字对比度
    static let mint = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.18, green: 0.92, blue: 0.70, alpha: 1) : UIColor(red: 0.0, green: 0.55, blue: 0.40, alpha: 1)
    })
    static let onMint = Color(UIColor { t in t.userInterfaceStyle == .dark ? UIColor.black : UIColor.white })
    // 回答正文：系统字体，行距舒展
    static let body = Font.system(size: 16.5)
}
