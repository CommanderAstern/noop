import XCTest
@testable import StrengthTracking

final class StrengthFlowTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func state() -> StrengthState {
        var state = StrengthState(); state.start(now: now)
        var warmup = StrengthSet(reps: 12, kilograms: 20); warmup.kind = .warmup
        var movement = StrengthMovement(exercise: StrengthExercise.catalog[1], sets: [warmup, StrengthSet(reps: 8, kilograms: 60), StrengthSet(reps: 8, kilograms: 65)])
        movement.restSeconds = 120
        state.active!.movements = [movement]; state.wristAlert = true
        return state
    }
    func start(_ state: inout StrengthState, _ index: Int, _ seconds: Double) {
        let m = state.active!.movements[0]; state.startSet(movementID: m.id, setID: m.sets[index].id, now: now.addingTimeInterval(seconds))
    }
    func complete(_ state: inout StrengthState, _ index: Int, _ seconds: Double) {
        let m = state.active!.movements[0]; state.completeSet(movementID: m.id, setID: m.sets[index].id, now: now.addingTimeInterval(seconds))
    }
    func testWarmupRestAndRunningSetSurviveEncoding() throws {
        var state = state(); start(&state, 0, 10); complete(&state, 0, 40)
        XCTAssertEqual(state.rest?.deadline, now.addingTimeInterval(160))
        var restored = try JSONDecoder().decode(StrengthState.self, from: JSONEncoder().encode(state)).validated()
        start(&restored, 1, 220)
        XCTAssertEqual(restored.active?.restIntervals?.first?.actualSeconds, 180)
        XCTAssertEqual(restored.active?.movements[0].sets[1].startedAt, now.addingTimeInterval(220))
        XCTAssertEqual(restored.active?.workingSets, 0)
        XCTAssertEqual(restored.active?.volumeKilograms, 240)
        XCTAssertNil(restored.rest)
    }
    func testCountdownExpirationDoesNotEndActualRest() {
        var state = state(); start(&state, 0, 0); complete(&state, 0, 30)
        XCTAssertTrue(state.consumeRest(now: now.addingTimeInterval(150), foreground: true, strapReady: true))
        XCTAssertNil(state.active?.restIntervals?.first?.endedAt)
        start(&state, 1, 210)
        XCTAssertEqual(state.active?.restIntervals?.first?.actualSeconds, 180)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(211), foreground: true, strapReady: true))
    }
    func testEarlyStartAndDoubleTapAreIdempotent() {
        var state = state(); complete(&state, 0, 10); start(&state, 1, 30)
        let before = state; start(&state, 1, 31)
        XCTAssertEqual(state, before)
        XCTAssertEqual(state.active?.actualRest, 20)
        complete(&state, 2, 35) // Cannot complete another set while set 1 is running.
        XCTAssertNil(state.active?.movements[0].sets[2].completedAt)
    }
    func testUntimedCompletionsDoNotInventRestOrSetDuration() {
        var state = state(); complete(&state, 0, 10); complete(&state, 1, 200)
        XCTAssertNil(state.active?.movements[0].sets[1].startedAt)
        XCTAssertEqual(state.active?.restIntervals?.first?.reason, .unknownStart)
        XCTAssertNil(state.active?.actualRest)
    }
    func testUndoCancelsPendingCueAndInvalidatesAdjacentRest() {
        var state = state(); complete(&state, 0, 10); start(&state, 1, 100); complete(&state, 1, 130)
        state.undoLastSet()
        XCTAssertNil(state.rest)
        XCTAssertEqual(state.active?.movements[0].sets[1].kilograms, 60)
        XCTAssertNil(state.active?.movements[0].sets[1].completedAt)
        XCTAssertEqual(state.active?.restIntervals?.first?.reason, .correction)
        XCTAssertNil(state.active?.actualRest)
        XCTAssertFalse(state.consumeRest(now: now.addingTimeInterval(250), foreground: true, strapReady: true))
    }
    func testTemplatePreservesWarmupsAndRestButClearsTiming() {
        var state = state(); start(&state, 0, 0); complete(&state, 0, 30)
        let routine = StrengthRoutine(name: "Push", movements: state.active!.movements, restSeconds: 90, unit: .lb)
        XCTAssertEqual(routine.movements[0].restSeconds, 120)
        XCTAssertEqual(routine.movements[0].sets[0].kind, .warmup)
        XCTAssertNil(routine.movements[0].sets[0].startedAt)
        XCTAssertNil(routine.movements[0].sets[0].completedAt)
    }
    func testOldSchemaDefaultsWithoutFabricatingHistory() throws {
        var original = state(); original.version = 1
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var active = try XCTUnwrap(object["active"] as? [String: Any])
        var movements = try XCTUnwrap(active["movements"] as? [[String: Any]])
        var sets = try XCTUnwrap(movements[0]["sets"] as? [[String: Any]])
        sets[0].removeValue(forKey: "setKind"); movements[0]["sets"] = sets; movements[0].removeValue(forKey: "restSeconds")
        active["movements"] = movements; active.removeValue(forKey: "restIntervals"); object["active"] = active
        let old = try JSONDecoder().decode(StrengthState.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        XCTAssertEqual(old.active?.movements[0].sets[0].kind, .working)
        XCTAssertNil(old.active?.restIntervals)
        XCTAssertNil(old.active?.actualRest)
    }
    func testRecordsIgnoreWarmupsTiesAndFirstBaseline() {
        var first = state(); complete(&first, 1, 10); first.finish(now: now.addingTimeInterval(50))
        let prior = first.history[0]
        XCTAssertTrue(StrengthProgress.records(in: prior, history: [prior]).isEmpty)
        var next = state(); next.active!.startedAt = now.addingTimeInterval(100)
        complete(&next, 1, 110); next.finish(now: now.addingTimeInterval(150))
        XCTAssertTrue(StrengthProgress.records(in: next.history[0], history: [prior]).isEmpty)
        next = state(); next.active!.startedAt = now.addingTimeInterval(100)
        complete(&next, 2, 110); next.finish(now: now.addingTimeInterval(150))
        let records = StrengthProgress.records(in: next.history[0], history: [prior])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.previousKilograms, 60)
        XCTAssertEqual(records.first?.kilograms, 65)
        next.history[0].movements[0].sets[2].kind = .warmup
        XCTAssertTrue(StrengthProgress.records(in: next.history[0], history: [prior]).isEmpty)
    }
}
