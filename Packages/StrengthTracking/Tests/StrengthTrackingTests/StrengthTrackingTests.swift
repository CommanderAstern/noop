import XCTest
@testable import StrengthTracking

final class StrengthTrackingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func workout() -> StrengthState {
        var state = StrengthState()
        state.wristAlert = true
        state.start(now: now)
        state.active!.movements = [StrengthMovement(exercise: StrengthExercise.catalog[0],
                                                    sets: [StrengthSet(reps: 5, kilograms: 100), StrengthSet()])]
        return state
    }
    func complete(_ state: inout StrengthState, set: Int = 0, at date: Date? = nil) {
        let movement = state.active!.movements[0]
        state.completeSet(movementID: movement.id, setID: movement.sets[set].id, now: date ?? now)
    }
    func store() throws -> StrengthFileStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return StrengthFileStore(url: directory.appendingPathComponent("strength.json"))
    }

    func testAllStateSurvivesDiskReload() throws {
        let disk = try store()
        var state = workout()
        let custom = StrengthExercise(name: "Gym chest press #4", equipment: "Plate-loaded machine")
        state.customExercises = [custom]
        state.active!.movements.append(StrengthMovement(exercise: custom))
        state.phoneAlert = true
        state.unit = .lb
        state.active!.unit = .lb
        state.routines = [StrengthRoutine(name: "Push", movements: state.active!.movements, restSeconds: 120, unit: .lb)]
        complete(&state)
        try disk.save(state)
        XCTAssertEqual(try StrengthFileStore(url: disk.url).load(), state)
    }

    func testDoubleCompletionCannotRestartRest() {
        var state = workout()
        complete(&state)
        let before = state
        complete(&state, at: now.addingTimeInterval(30))
        XCTAssertEqual(state, before)
    }

    func testDeadlineUsesWallTimeAndCeiling() {
        var state = workout()
        complete(&state)
        XCTAssertEqual(state.rest?.remaining(at: now.addingTimeInterval(30.5)), 60)
        XCTAssertEqual(state.rest?.remaining(at: now.addingTimeInterval(300)), 0)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(89.9), foreground: true, strapReady: true))
        XCTAssertTrue(state.consumeRest(now: now.addingTimeInterval(90), foreground: true, strapReady: true))
    }

    func testExactlyOneClaimPersistsAcrossRestart() throws {
        let disk = try store()
        var state = workout()
        complete(&state)
        XCTAssertTrue(state.consumeRest(now: now.addingTimeInterval(90), foreground: true, strapReady: true))
        try disk.save(state)
        var restarted = try disk.load()
        for _ in 0..<10 {
            XCTAssertFalse(restarted.consumeRest(now: now.addingTimeInterval(91), foreground: true, strapReady: true))
        }
    }

    func testExpiredBackgroundRestCannotBuzzOnReturn() {
        var state = workout()
        complete(&state)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(90), foreground: false, strapReady: true))
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(90.1), foreground: true, strapReady: true))
        XCTAssertEqual(state.rest?.consumed, true)
    }

    func testDisconnectedRestIsNeverRetried() {
        var state = workout()
        complete(&state)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(90), foreground: true, strapReady: false))
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(91), foreground: true, strapReady: true))
    }

    func testDelayedTickNeverEmitsStaleBuzz() {
        var state = workout()
        complete(&state)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(93), foreground: true, strapReady: true))
        XCTAssertEqual(state.rest?.consumed, true)
    }

    func testOptOutConsumesWithoutLaterReplay() {
        var state = workout()
        complete(&state)
        state.wristAlert = false
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(90), foreground: true, strapReady: true))
        state.wristAlert = true
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(91), foreground: true, strapReady: true))
    }

    func testNextSetReplacesRestWithNewIdentity() {
        var state = workout()
        complete(&state)
        let first = state.rest!
        complete(&state, set: 1, at: now.addingTimeInterval(20))
        XCTAssertNotEqual(first.id, state.rest?.id)
        XCTAssertFalse(state.consumeRest(now: first.deadline, foreground: true, strapReady: true))
        XCTAssertTrue(state.consumeRest(now: now.addingTimeInterval(110), foreground: true, strapReady: true))
    }

    func testSkipUndoFinishAndDiscardCancelRest() {
        for action in 0...3 {
            var state = workout()
            complete(&state)
            switch action {
            case 0: state.rest = nil
            case 1:
                let movement = state.active!.movements[0]
                state.undoSet(movementID: movement.id, setID: movement.sets[0].id)
            case 2: state.finish(now: now.addingTimeInterval(20))
            default: state.discard()
            }
            XCTAssertNil(state.rest)
            XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(90), foreground: true, strapReady: true))
        }
    }

    func testZeroRestAndConfigurationOnlyAffectsNextSet() {
        var state = workout()
        complete(&state)
        let timer = state.rest
        state.restSeconds = 0
        XCTAssertEqual(timer, state.rest)
        complete(&state, set: 1)
        XCTAssertNil(state.rest)
    }

    func testFinishIsAtomicAndIdempotent() throws {
        let disk = try store()
        var state = workout()
        complete(&state)
        let originalID = state.active!.id
        state.finish(now: now.addingTimeInterval(120))
        state.finish(now: now.addingTimeInterval(121))
        try disk.save(state)
        let loaded = try disk.load()
        XCTAssertNil(loaded.active)
        XCTAssertNil(loaded.rest)
        XCTAssertEqual(loaded.history.count, 1)
        XCTAssertEqual(loaded.history[0].id, originalID)
        XCTAssertEqual(loaded.history[0].completedSets, 1)
        XCTAssertNil(loaded.history[0].movements[0].sets[1].completedAt)
    }

    func testRoutineReuseResetsIDsAndCompletionWithoutChangingHistory() {
        var state = workout()
        complete(&state)
        let old = state.active!
        let routine = StrengthRoutine(name: "Legs", movements: old.movements, restSeconds: 180, unit: .lb)
        state.finish(now: now.addingTimeInterval(180))
        state.start(routine: routine, now: now.addingTimeInterval(3600))
        XCTAssertEqual(state.active?.completedSets, 0)
        XCTAssertNotEqual(state.active?.id, old.id)
        XCTAssertNotEqual(state.active?.movements[0].sets[0].id, old.movements[0].sets[0].id)
        XCTAssertEqual(state.active?.movements[0].sets[0].kilograms, 100)
        XCTAssertEqual(state.active?.unit, .lb)
        XCTAssertEqual(state.restSeconds, 180)
        XCTAssertEqual(state.history[0].completedSets, 1)
    }

    func testCannotOverwriteActiveSessionWithAnotherStart() {
        var state = workout()
        let original = state
        state.start(now: now.addingTimeInterval(500))
        XCTAssertEqual(state, original)
    }

    func testUnitsAndBodyweightValidation() {
        XCTAssertEqual(LiftingUnit.lb.display(100), 220.46226218487757, accuracy: 0.000001)
        XCTAssertEqual(LiftingUnit.lb.kilograms(225), 102.05828325, accuracy: 0.000001)
        var kilograms = 47.125
        for _ in 0..<100 { kilograms = LiftingUnit.lb.kilograms(LiftingUnit.lb.display(kilograms)) }
        XCTAssertEqual(kilograms, 47.125, accuracy: 0.000001)
        XCTAssertTrue(StrengthSet(reps: 10, kilograms: 0).isValid)
        XCTAssertFalse(StrengthSet(reps: 0, kilograms: 20).isValid)
        XCTAssertFalse(StrengthSet(reps: 10, kilograms: .infinity).isValid)
        XCTAssertFalse(StrengthSet(reps: 10, kilograms: -1).isValid)
    }

    func testCorruptAndFutureDataAreNotSilentlyReset() throws {
        let disk = try store()
        try disk.save(workout())
        let garbage = Data("{broken".utf8)
        try garbage.write(to: disk.url)
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try Data(contentsOf: disk.url), garbage)
        var future = workout()
        future.version = 2
        try JSONEncoder().encode(future).write(to: disk.url)
        XCTAssertThrowsError(try disk.load())
    }

    func testInvalidSaveDoesNotReplacePreviousData() throws {
        let disk = try store()
        let original = workout()
        try disk.save(original)
        var invalid = original
        invalid.restSeconds = -10
        XCTAssertThrowsError(try disk.save(invalid))
        XCTAssertEqual(try disk.load(), original)
        invalid = original
        invalid.active!.movements[0].sets.append(invalid.active!.movements[0].sets[0])
        XCTAssertThrowsError(try disk.save(invalid))
        XCTAssertEqual(try disk.load(), original)
    }

    func testOrphanedRestRejected() throws {
        var state = workout()
        complete(&state)
        state.rest?.sessionID = UUID()
        XCTAssertThrowsError(try state.validated())
    }
}
