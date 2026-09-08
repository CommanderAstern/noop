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
    /// Optional user-owned thumbnail, stored with the encrypted workout document.
    public var photo: Data?
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
    public var startedAt: Date?
    public var setKind: StrengthSetKind?
    public var kind: StrengthSetKind { get { setKind ?? .working } set { setKind = newValue } }
    public init(reps: Int = 8, kilograms: Double = 0) { self.reps = reps; self.kilograms = kilograms }
    public var isValid: Bool { (1...999).contains(reps) && kilograms.isFinite && (0...10_000).contains(kilograms) }
    public func fresh() -> Self { var set = Self(reps: reps, kilograms: kilograms); set.setKind = setKind; return set }
}

public struct StrengthMovement: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    /// Snapshot the exercise so later catalog edits cannot relabel history.
    public var exercise: StrengthExercise
    public var sets: [StrengthSet]
    public var restSeconds: Int?
    public init(exercise: StrengthExercise, sets: [StrengthSet] = [StrengthSet()]) {
        self.exercise = exercise; self.sets = sets
    }
    public func fresh() -> Self { var movement = Self(exercise: exercise, sets: sets.map { $0.fresh() }); movement.restSeconds = restSeconds; return movement }
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
    public var restIntervals: [StrengthRestInterval]?
    public var restCoverageIncomplete: Bool?
    public var notes: String?
    public var restSeconds: Int = 90
    public var movements: [StrengthMovement] = []
    public var unit: LiftingUnit = .kg
    public var completedSets: Int { movements.reduce(0) { $0 + $1.sets.filter { $0.completedAt != nil }.count } }
    public init(now: Date, unit: LiftingUnit) { startedAt = now; self.unit = unit; restIntervals = [] }
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
    public var version: Int = 2
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
              !session.movements.flatMap(\.sets).contains(where: { $0.id != setID && $0.startedAt != nil && $0.completedAt == nil }),
              session.movements[m].sets[s].isValid else { return }
        let finished = max(now, session.movements[m].sets[s].startedAt ?? session.startedAt)
        session.prepareRestHistory(countdown: rest)
        session.closeRest(at: finished, nextSetID: setID, reason: .unknownStart)
        session.movements[m].sets[s].completedAt = finished
        let seconds = session.movements[m].restSeconds ?? restSeconds
        if session.restIntervals == nil { session.restIntervals = [] }
        session.restIntervals?.append(StrengthRestInterval(setID: setID, startedAt: finished, plannedSeconds: seconds))
        active = session
        rest = seconds > 0 ? StrengthRest(sessionID: session.id, setID: setID,
                                              deadline: finished.addingTimeInterval(Double(seconds))) : nil
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
              let s = active?.movements[m].sets.firstIndex(where: { $0.id == setID }),
              active?.movements[m].sets[s].completedAt != nil else { return }
        active?.movements[m].sets[s].completedAt = nil
        active?.movements[m].sets[s].startedAt = nil
        active?.restIntervals?.removeAll { $0.setID == setID }
        if let count = active?.restIntervals?.count {
            for index in 0..<count where active?.restIntervals?[index].nextSetID == setID {
                active?.restIntervals?[index].reason = .correction
            }
        }
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
        session.prepareRestHistory(countdown: rest)
        session.finishedAt = max(now, session.startedAt, session.movements.flatMap(\.sets).compactMap(\.completedAt).max() ?? session.startedAt)
        session.closeRest(at: session.finishedAt!, nextSetID: nil, reason: .finished)
        history.insert(session, at: 0)
        active = nil; rest = nil
    }

    public mutating func discard() { active = nil; rest = nil }

    public func validated() throws -> Self {
        guard (1...2).contains(version) else { throw StrengthStorageError.unsupportedVersion }
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        func movementsValid(_ movements: [StrengthMovement]) -> Bool {
            unique(movements.map(\.id)) && unique(movements.flatMap { $0.sets.map(\.id) }) && movements.allSatisfy {
                !$0.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && ($0.exercise.photo?.count ?? 0) <= 1_000_000
                    && ($0.restSeconds.map { (0...1800).contains($0) } ?? true)
                    && $0.sets.allSatisfy { set in set.isValid && (set.startedAt == nil || set.completedAt == nil || set.startedAt! <= set.completedAt!) }
            }
        }
        guard (0...1800).contains(restSeconds), unique(history.map(\.id)), unique(routines.map(\.id)),
              unique(customExercises.map(\.id)),
              history.allSatisfy({ $0.finishedAt != nil && $0.finishedAt! >= $0.startedAt && movementsValid($0.movements) }),
              routines.allSatisfy({ (0...1800).contains($0.restSeconds) && movementsValid($0.movements) }),
              active.map({ $0.finishedAt == nil && movementsValid($0.movements) }) ?? true else {
            throw StrengthStorageError.invalidData
        }
        for session in history + [active].compactMap({ $0 }) {
            let intervals = session.restIntervals ?? []
            guard unique(intervals.map(\.id)), intervals.filter({ $0.endedAt == nil }).count <= 1,
                  session.finishedAt == nil || intervals.allSatisfy({ $0.endedAt != nil }),
                  intervals.allSatisfy({ interval in
                      (0...1800).contains(interval.plannedSeconds)
                      && (interval.endedAt.map { $0 >= interval.startedAt } ?? true)
                      && session.movements.flatMap(\.sets).contains { $0.id == interval.setID && $0.completedAt != nil }
                  }) else { throw StrengthStorageError.invalidData }
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
public final class StrengthFileStore {
    public let url: URL
    private var diskVersion: Int?
    public init(url: URL) { self.url = url }
    public func load() throws -> StrengthState {
        guard FileManager.default.fileExists(atPath: url.path) else { return StrengthState() }
        var state = try JSONDecoder().decode(StrengthState.self, from: Data(contentsOf: url)).validated()
        diskVersion = state.version
        state.restoreLegacyRest()
        // Migrate existing installs while unlocked, before any locked countdown needs to commit.
        try prepareDirectory()
        return state
    }
    public func save(_ state: StrengthState) throws {
        let data = try JSONEncoder().encode(state.validated())
        try prepareDirectory()
        // Retain the readable v1 document once before v2's first write. Never auto-restore a backup.
        if state.version == 2, diskVersion != 2, let previous = try? Data(contentsOf: url) {
            struct Header: Decodable { let version: Int }
            let version = try JSONDecoder().decode(Header.self, from: previous).version
            let backup = url.deletingLastPathComponent().appendingPathComponent("before-v2.json")
            if version == 1, !FileManager.default.fileExists(atPath: backup.path) {
                #if os(iOS)
                try previous.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try previous.write(to: backup, options: .atomic)
                #endif
            }
        }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        diskVersion = state.version
    }

    private func prepareDirectory() throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        // Like the BLE database: encrypted, available after first unlock since boot, including
        // subsequent screen locks. Set the directory, existing document, and atomic replacement.
        let protection: [FileAttributeKey: Any] =
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try fm.setAttributes(protection, ofItemAtPath: directory.path)
        if fm.fileExists(atPath: url.path) {
            try fm.setAttributes(protection, ofItemAtPath: url.path)
        }
        #endif
    }
}
