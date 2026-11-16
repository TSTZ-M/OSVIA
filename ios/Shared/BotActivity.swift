import ActivityKit
import Foundation

// 灵动岛 / 锁屏实时活动的数据，应用与扩展共用
// phase：listening 聆听 / thinking 思考 / searching 搜索 / working 执行 / done 完成 / timer 倒计时
struct BotActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var end: Date?
        var phase: String = "thinking"
        var detail: String? = nil
    }
    var kind: String
}
