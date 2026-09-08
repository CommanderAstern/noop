import Foundation

public enum StrengthSetKind: String, Codable, CaseIterable { case warmup, working }

public struct StrengthRestInterval: Codable, Equatable, Identifiable {
    public enum EndReason: String, Codable { case nextSet, finished, unknownStart, correction }
    public var id = UUID()
    public var setID: UUID
    public var nextSetID: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var plannedSeconds: Int
    public var reason: EndReason?
    public init(setID: UUID, startedAt: Date, plannedSeconds: Int) {
        self.setID = setID; self.startedAt = startedAt; self.plannedSeconds = plannedSeconds
    }
    public var actualSeconds: TimeInterval? {
        guard let endedAt, reason == .nextSet || reason == .finished else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}

extension StrengthSession {
    public var workingSets: Int { movements.flatMap(\.sets).filter { $0.completedAt != nil && $0.kind == .working }.count }
    public var volumeKilograms: Double { movements.flatMap(\.sets).filter { $0.completedAt != nil }.reduce(0) { $0 + $1.kilograms * Double($1.reps) } }
    public var workingVolume: Double { movements.flatMap(\.sets).filter { $0.completedAt != nil && $0.kind == .working }.reduce(0) { $0 + $1.kilograms * Double($1.reps) } }
    public var actualRest: TimeInterval? {
        guard let restIntervals, restCoverageIncomplete != true else { return nil }
        guard !restIntervals.contains(where: { $0.endedAt != nil && $0.actualSeconds == nil }) else { return nil }
        return restIntervals.compactMap(\.actualSeconds).reduce(0, +)
    }
    public var openRest: StrengthRestInterval? { restIntervals?.last(where: { $0.endedAt == nil }) }
    mutating func prepareRestHistory(countdown: StrengthRest?) {
        guard restIntervals == nil else { return }
        restCoverageIncomplete = completedSets > 0
        restIntervals = []
        // A legacy countdown proves this one rest's start, but not earlier rests or set starts.
        if let countdown, countdown.sessionID == id,
           let completed = movements.flatMap(\.sets).first(where: { $0.id == countdown.setID })?.completedAt {
            let duration = countdown.deadline.timeIntervalSince(completed)
            if duration >= 0, duration <= 1800 {
                restIntervals = [StrengthRestInterval(setID: countdown.setID, startedAt: completed, plannedSeconds: Int(duration.rounded()))]
            }
        }
    }
    public var nextSet: (movement: StrengthMovement, set: StrengthSet)? {
        for movement in movements {
            if let set = movement.sets.first(where: { $0.startedAt != nil && $0.completedAt == nil }) { return (movement, set) }
        }
        for movement in movements {
            if let set = movement.sets.first(where: { $0.completedAt == nil }) { return (movement, set) }
        }
        return nil
    }
    /// Match the same exercise and set kind across repeated exercise blocks in session order.
    public func ordinal(of setID: UUID) -> Int? {
        guard let movement = movements.first(where: { $0.sets.contains { $0.id == setID } }),
              let set = movement.sets.first(where: { $0.id == setID }) else { return nil }
        return movements.filter { $0.exercise.id == movement.exercise.id }.flatMap(\.sets)
            .filter { $0.kind == set.kind }.firstIndex { $0.id == setID }
    }
    mutating func closeRest(at now: Date, nextSetID: UUID?, reason: StrengthRestInterval.EndReason) {
        guard let index = restIntervals?.lastIndex(where: { $0.endedAt == nil }) else { return }
        let chronological = now >= restIntervals![index].startedAt
        restIntervals![index].endedAt = max(now, restIntervals![index].startedAt)
        restIntervals![index].nextSetID = nextSetID
        restIntervals![index].reason = chronological ? reason : .correction
    }
}

extension StrengthState {
    public mutating func restoreLegacyRest() { active?.prepareRestHistory(countdown: rest) }
    public mutating func startSet(movementID: UUID, setID: UUID, now: Date) {
        guard var session = active,
              !session.movements.flatMap(\.sets).contains(where: { $0.startedAt != nil && $0.completedAt == nil }),
              let m = session.movements.firstIndex(where: { $0.id == movementID }),
              let s = session.movements[m].sets.firstIndex(where: { $0.id == setID }),
              session.movements[m].sets[s].completedAt == nil else { return }
        session.prepareRestHistory(countdown: rest)
        session.closeRest(at: now, nextSetID: setID, reason: .nextSet)
        session.movements[m].sets[s].startedAt = max(now, session.startedAt)
        active = session; rest = nil
    }

    public mutating func undoLastSet() {
        guard let session = active else { return }
        let pairs = session.movements.flatMap { movement in movement.sets.compactMap { set -> (UUID, StrengthSet)? in
            set.completedAt == nil ? nil : (movement.id, set)
        } }
        guard let last = pairs.max(by: { $0.1.completedAt! < $1.1.completedAt! }) else { return }
        undoSet(movementID: last.0, setID: last.1.id)
    }

    public func previousSets(for exercise: StrengthExercise) -> [StrengthSet] {
        for session in history.sorted(by: { $0.startedAt > $1.startedAt }) {
            let sets = session.movements.filter { $0.exercise.id == exercise.id }.flatMap(\.sets)
                .filter { $0.completedAt != nil }
            if !sets.isEmpty { return sets }
        }
        return []
    }
    public func previousSet(for exercise: StrengthExercise, kind: StrengthSetKind = .working, ordinal: Int = 0) -> StrengthSet? {
        let sets = previousSets(for: exercise).filter { $0.kind == kind }
        return sets.indices.contains(ordinal) ? sets[ordinal] : nil
    }
    public func suggestedSets(for exercise: StrengthExercise) -> [StrengthSet] {
        let previous = previousSets(for: exercise)
        return previous.isEmpty ? [StrengthSet(), StrengthSet(), StrengthSet()] : previous.map { $0.fresh() }
    }

    public mutating func addExercise(_ exercise: StrengthExercise) {
        guard active != nil else { return }
        let targets = suggestedSets(for: exercise)
        active?.movements.append(StrengthMovement(exercise: exercise, sets: targets))
    }
}

public struct StrengthRecord: Identifiable, Equatable {
    public var id: String { "\(setID)-\(heaviest)" }
    public let exercise: StrengthExercise
    public let setID: UUID
    public let reps: Int
    public let kilograms: Double
    public let previousKilograms: Double
    public var heaviest = false
}

public enum StrengthProgress {
    /// Compare identical exercise identities and reps, excluding warm-ups and nonpositive loads.
    /// First observations establish a baseline; ties and unit display changes are not records.
    public static func records(in session: StrengthSession, history: [StrengthSession]) -> [StrengthRecord] {
        var records: [StrengthRecord] = []
        var seen: Set<UUID> = []
        for movement in session.movements where seen.insert(movement.exercise.id).inserted {
            let current = session.movements.filter { $0.exercise.id == movement.exercise.id }.flatMap(\.sets)
            let previous = history.filter { $0.id != session.id && ($0.finishedAt ?? .distantFuture) < session.startedAt }
                .flatMap(\.movements).filter { $0.exercise.id == movement.exercise.id }.flatMap(\.sets)
                .filter { $0.kind == .working && $0.completedAt != nil && $0.kilograms > 0 }
            if let previousMax = previous.map(\.kilograms).max(),
               let best = current.filter({ $0.kind == .working && $0.completedAt != nil }).max(by: { $0.kilograms < $1.kilograms }),
               best.kilograms > previousMax + 0.000001 {
                records.append(StrengthRecord(exercise: movement.exercise, setID: best.id, reps: best.reps,
                    kilograms: best.kilograms, previousKilograms: previousMax, heaviest: true))
            }
            let reps = Set(current.filter { $0.kind == .working && $0.completedAt != nil }.map(\.reps))
            for count in reps.sorted() {
                guard let baseline = previous.filter({ $0.reps == count }).map(\.kilograms).max(),
                      let best = current.filter({ $0.reps == count && $0.kind == .working && $0.completedAt != nil })
                        .max(by: { $0.kilograms < $1.kilograms }), best.kilograms > baseline + 0.000001 else { continue }
                records.append(StrengthRecord(exercise: movement.exercise, setID: best.id, reps: count,
                    kilograms: best.kilograms, previousKilograms: baseline))
            }
        }
        return records
    }
}

extension StrengthRoutine {
    /// Editable starting points, never a prescription or a generated health recommendation.
    public static let starterDays: [StrengthRoutine] = {
        [("Upper body A", [1, 15, 7, 8]), ("Push day", [1, 6, 7, 17]),
         ("Pull day", [15, 16, 4, 8]), ("Leg day", [0, 11, 12, 13, 19])].map { name, indexes in
            let movements = indexes.map { index -> StrengthMovement in
                var warmup = StrengthSet(reps: 12); warmup.kind = .warmup
                return StrengthMovement(exercise: StrengthExercise.catalog[index],
                    sets: [warmup, StrengthSet(), StrengthSet(), StrengthSet()])
            }
            return StrengthRoutine(name: name, movements: movements, restSeconds: 90, unit: .kg)
        }
    }()
}
