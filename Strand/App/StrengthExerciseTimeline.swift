import Foundation
import StrengthTracking

struct StrengthExerciseTimeline {
    struct Mark: Identifiable {
        let id: UUID
        let name: String
        let start: Double?
        let end: Double
    }
    let duration: Double
    let marks: [Mark]

    init(session: StrengthSession, movementID: UUID?) {
        duration = max(1.0 / 60, (session.finishedAt ?? session.startedAt).timeIntervalSince(session.startedAt) / 60)
        let limit = duration
        marks = session.movements.filter { movementID == nil || $0.id == movementID }.flatMap { movement in
            movement.sets.compactMap { set -> Mark? in
                guard let completed = set.completedAt else { return nil }
                let end = completed.timeIntervalSince(session.startedAt) / 60
                guard end >= 0, end <= limit else { return nil }
                let start = set.startedAt.map { $0.timeIntervalSince(session.startedAt) / 60 }
                    .flatMap { $0 >= 0 && $0 <= end ? $0 : nil }
                return Mark(id: set.id, name: movement.exercise.name, start: start, end: end)
            }
        }
    }
}
