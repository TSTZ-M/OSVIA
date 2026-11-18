import ActivityKit
import Foundation

// 灵动岛 / 锁屏实时活动的数据，应用与扩展共用
// phase：listening 聆听 / thinking 思考 / searching 搜索 / working 执行 / done 完成 / timer 倒计时
// started：这次请求的开始时间，岛上用系统计时器显示已用时（系统自己走，不用频繁更新）
struct BotActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var end: Date?
        var phase: String = "thinking"
        var detail: String? = nil
        var started: Date? = nil
    }
    var kind: String
}
