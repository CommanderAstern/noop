import Foundation

public enum LiftingUnit: String, Codable, CaseIterable {
    case kg, lb
    public func kilograms(_ value: Double) -> Double { self == .kg ? value : value / 2.2046226218487757 }
    public func display(_ kilograms: Double) -> Double { self == .kg ? kilograms : kilograms * 2.2046226218487757 }
}

public struct StrengthExercise: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var equipment: String
    public init(id: UUID = UUID(), name: String, equipment: String) {
        self.id = id; self.name = name; self.equipment = equipment
    }
    public static let catalog: [StrengthExercise] = [
        ("Squat", "Barbell"), ("Bench press", "Barbell"), ("Deadlift", "Barbell"),
        ("Overhead press", "Barbell"), ("Bent-over row", "Barbell"),
        ("Romanian deadlift", "Dumbbell"), ("Bench press", "Dumbbell"),
        ("Shoulder press", "Dumbbell"), ("Biceps curl", "Dumbbell"),
        ("Lateral raise", "Dumbbell"), ("Goblet squat", "Kettlebell"),
        ("Leg press", "Machine"), ("Leg extension", "Machine"),
        ("Leg curl", "Machine"), ("Chest press", "Machine"),
        ("Lat pulldown", "Cable"), ("Seated row", "Cable"),
        ("Triceps pushdown", "Cable"), ("Face pull", "Cable"),
        ("Calf raise", "Machine"), ("Hip abduction", "Machine"),
        ("Squat", "Smith machine"), ("Pull-up", "Bodyweight"),
        ("Push-up", "Bodyweight"), ("Dip", "Bodyweight"), ("Lunge", "Bodyweight"),
    ].enumerated().map { index, entry in
        StrengthExercise(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                         name: entry.0, equipment: entry.1)
    }
}

public struct StrengthSet: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var reps: Int = 8
    /// Canonical storage avoids rounding drift when switching display units.
    public var kilograms: Double = 0
    public var completedAt: Date?
    public init(reps: Int = 8, kilograms: Double = 0) { self.reps = reps; self.kilograms = kilograms }
    public var isValid: Bool { (1...999).contains(reps) && kilograms.isFinite && (0...10_000).contains(kilograms) }
    public func fresh() -> Self { Self(reps: reps, kilograms: kilograms) }
}

public struct StrengthMovement: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    /// Snapshot the exercise so later catalog edits cannot relabel history.
    public var exercise: StrengthExercise
    public var sets: [StrengthSet]
    public init(exercise: StrengthExercise, sets: [StrengthSet] = [StrengthSet()]) {
        self.exercise = exercise; self.sets = sets
    }
    public func fresh() -> Self { Self(exercise: exercise, sets: sets.map { $0.fresh() }) }
}

public struct StrengthRoutine: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var movements: [StrengthMovement]
    public var restSeconds: Int
    public var unit: LiftingUnit
    public init(name: String, movements: [StrengthMovement], restSeconds: Int, unit: LiftingUnit) {
        self.name = name; self.movements = movements.map { $0.fresh() }
        self.restSeconds = restSeconds; self.unit = unit
    }
}

public struct StrengthSession: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var name: String = "Strength workout"
    public var startedAt: Date
    public var finishedAt: Date?
    public var restSeconds: Int = 90
    public var movements: [StrengthMovement] = []
    public var unit: LiftingUnit = .kg
    public var completedSets: Int { movements.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count } }
    public init(now: Date, unit: LiftingUnit) { startedAt = now; self.unit = unit }
}

public struct StrengthRest: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var sessionID: UUID
    public var setID: UUID
    public var deadline: Date
    /// Consumed also means deliberately skipped (inactive, late, disconnected or disabled).
    public var consumed = false
    public init(sessionID: UUID, setID: UUID, deadline: Date) {
        self.sessionID = sessionID; self.setID = setID; self.deadline = deadline
    }
    public func remaining(at now: Date) -> Int { max(0, Int(ceil(deadline.timeIntervalSince(now)))) }
}

public struct StrengthState: Codable, Equatable {
    public var version: Int = 1
    public var active: StrengthSession?
    public var history: [StrengthSession] = []
    public var routines: [StrengthRoutine] = []
    public var customExercises: [StrengthExercise] = []
    public var rest: StrengthRest?
    public var restSeconds: Int = 90
    public var unit: LiftingUnit = .kg
    public var wristAlert = false
    public var phoneAlert = false
    public init() {}

    public mutating func start(routine: StrengthRoutine? = nil, now: Date) {
        guard active == nil else { return }
        var session = StrengthSession(now: now, unit: routine?.unit ?? unit)
        if let routine {
            session.name = routine.name; session.movements = routine.movements.map { $0.fresh() }
            restSeconds = routine.restSeconds
        }
        session.restSeconds = restSeconds
        active = session; rest = nil
    }

    /// Idempotent completion: double taps cannot replace the countdown or emit a second alert.
    public mutating func completeSet(movementID: UUID, setID: UUID, now: Date) {
        guard var session = active,
              let m = session.movements.firstIndex(where: { $0.id == movementID }),
              let s = session.movements[m].sets.firstIndex(where: { $0.id == setID }),
              session.movements[m].sets[s].completedAt == nil,
              session.movements[m].sets[s].isValid else { return }
        session.movements[m].sets[s].completedAt = now
        active = session
        rest = restSeconds > 0 ? StrengthRest(sessionID: session.id, setID: setID,
                                              deadline: now.addingTimeInterval(Double(restSeconds))) : nil
    }

    /// Commit the visible input and its completion as one transaction (including save recovery).
    public mutating func recordSet(movementID: UUID, setID: UUID, reps: Int, kilograms: Double, now: Date) {
        let values = StrengthSet(reps: reps, kilograms: kilograms)
        guard values.isValid,
              let m = active?.movements.firstIndex(where: { $0.id == movementID }),
              let s = active?.movements[m].sets.firstIndex(where: { $0.id == setID }),
              active?.movements[m].sets[s].completedAt == nil else { return }
        active?.movements[m].sets[s].reps = reps
        active?.movements[m].sets[s].kilograms = kilograms
        completeSet(movementID: movementID, setID: setID, now: now)
    }

    public mutating func undoSet(movementID: UUID, setID: UUID) {
        guard let m = active?.movements.firstIndex(where: { $0.id == movementID }),
              let s = active?.movements[m].sets.firstIndex(where: { $0.id == setID }) else { return }
        active?.movements[m].sets[s].completedAt = nil
        if rest?.setID == setID { rest = nil }
    }

    /// Callers must persist the mutated state BEFORE performing the returned physical side effect.
    /// No retries: BLE cannot acknowledge physical motor movement or provide exactly-once delivery.
    public mutating func consumeRest(now: Date, foreground: Bool, strapReady: Bool) -> Bool {
        guard var timer = rest, !timer.consumed, now >= timer.deadline else { return false }
        timer.consumed = true
        rest = timer
        return active?.id == timer.sessionID && foreground && strapReady && wristAlert
            && now.timeIntervalSince(timer.deadline) <= 2
    }

    public mutating func finish(now: Date) {
        guard var session = active, session.completedSets > 0 else { return }
        session.finishedAt = max(now, session.startedAt)
        history.insert(session, at: 0)
        active = nil; rest = nil
    }

    public mutating func discard() { active = nil; rest = nil }

    public func validated() throws -> Self {
        guard version == 1 else { throw StrengthStorageError.unsupportedVersion }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        func movementsValid(_ movements: [StrengthMovement]) -> Bool {
            unique(movements.map(\.id)) && unique(movements.flatMap { $0.sets.map(\.id) }) && movements.allSatisfy {
                !$0.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.sets.allSatisfy(\.isValid)
            }
        }
        guard (0...1800).contains(restSeconds), unique(history.map(\.id)), unique(routines.map(\.id)),
              unique(customExercises.map(\.id)),
              history.allSatisfy({ $0.finishedAt != nil && $0.finishedAt! >= $0.startedAt && movementsValid($0.movements) }),
              routines.allSatisfy({ (0...1800).contains($0.restSeconds) && movementsValid($0.movements) }),
              active.map({ $0.finishedAt == nil && movementsValid($0.movements) }) ?? true else {
            throw StrengthStorageError.invalidData
        }
        if let rest {
            guard active?.id == rest.sessionID,
                  active?.movements.flatMap(\.sets).contains(where: { $0.id == rest.setID && $0.completedAt != nil }) == true
            else { throw StrengthStorageError.invalidData }
        }
        return self
    }
}

public enum StrengthStorageError: Error { case unsupportedVersion, invalidData }

/// One atomic document contains both active state and history: finishing cannot lose a session
/// between an archive write and an active-session clear. Read failures never silently reset data.
public struct StrengthFileStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> StrengthState {
        guard FileManager.default.fileExists(atPath: url.path) else { return StrengthState() }
        return try JSONDecoder().decode(StrengthState.self, from: Data(contentsOf: url)).validated()
    }
    public func save(_ state: StrengthState) throws {
        let data = try JSONEncoder().encode(state.validated())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
