#if os(iOS)
import Foundation
import ActivityKit

struct StrengthActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setLabel: String
        var restStart: Date?
        var restEnd: Date?
    }
    var sessionID: UUID
    var name: String
    var startedAt: Date
    var url: URL { URL(string: "noop://strength?session=\(sessionID.uuidString)")! }
}
#endif
