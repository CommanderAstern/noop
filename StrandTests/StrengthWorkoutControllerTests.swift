import XCTest
import StrengthTracking
@testable import Strand

@MainActor
final class StrengthWorkoutControllerTests: XCTestCase {
    private let runtimeEpoch = ContinuousClock.now
    func fixture() throws -> (StrengthFileStore, StrengthState) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = StrengthFileStore(url: directory.appendingPathComponent("strength.json"))
        var state = StrengthState()
        state.wristAlert = true
        state.start(now: Date())
        state.active!.movements = [StrengthMovement(exercise: StrengthExercise.catalog[0])]
        let movement = state.active!.movements[0]
        state.completeSet(movementID: movement.id, setID: movement.sets[0].id, now: Date())
        try store.save(state)
        return (store, state)
    }

    func testAppOwnerCommitsBeforeOnePhysicalAttempt() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = {
            XCTAssertEqual(try? disk.load().rest?.consumed, true)
            attempts += 1
        }
        tracker.tick(allowWrist: true, now: original.rest!.deadline)
        tracker.tick(allowWrist: true, now: original.rest!.deadline)
        XCTAssertEqual(attempts, 1)
        let restarted = StrengthWorkoutController(storage: disk, platformServices: false)
        restarted.strapReady = { true }
        restarted.buzz = { attempts += 1 }
        restarted.tick(allowWrist: true, now: original.rest!.deadline)
        XCTAssertEqual(attempts, 1)
    }

    func testSaveFailurePreventsPhysicalAttemptAndPreservesUI() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        try FileManager.default.removeItem(at: disk.url)
        try FileManager.default.createDirectory(at: disk.url, withIntermediateDirectories: true)
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.tick(allowWrist: true, now: original.rest!.deadline)
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(tracker.state, original)
        XCTAssertNotNil(tracker.error)
    }

    func testForegroundNotificationRejectsReplacedCancelledAndLateTimers() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        tracker.change { $0.phoneAlert = true }
        let id = StrengthWorkoutController.notificationPrefix + original.rest!.id.uuidString
        XCTAssertTrue(tracker.acceptsNotification(id, now: original.rest!.deadline))
        XCTAssertFalse(tracker.acceptsNotification(id + "old", now: original.rest!.deadline))
        XCTAssertFalse(tracker.acceptsNotification(id, now: original.rest!.deadline.addingTimeInterval(6)))
        tracker.change { $0.rest = nil }
        XCTAssertFalse(tracker.acceptsNotification(id, now: original.rest!.deadline))
    }

    func testFailedSuppressionCannotBuzzAfterSaveRecovery() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        try FileManager.default.removeItem(at: disk.url)
        try FileManager.default.createDirectory(at: disk.url, withIntermediateDirectories: true)
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.tick(allowWrist: false, now: original.rest!.deadline)
        try FileManager.default.removeItem(at: disk.url)
        try disk.save(original)
        tracker.tick(allowWrist: true, now: original.rest!.deadline.addingTimeInterval(1))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }

    func testCompletionAfterSaveRecoveryUsesVisibleInputs() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let movement = original.active!.movements[0]
        tracker.change { $0.undoSet(movementID: movement.id, setID: movement.sets[0].id) }
        try FileManager.default.removeItem(at: disk.url)
        try FileManager.default.createDirectory(at: disk.url, withIntermediateDirectories: true)
        XCTAssertFalse(tracker.change { $0.active?.movements[0].sets[0].kilograms = 40 })
        try FileManager.default.removeItem(at: disk.url)
        XCTAssertTrue(tracker.change {
            $0.recordSet(movementID: movement.id, setID: movement.sets[0].id,
                reps: 12, kilograms: 40, now: Date())
        })
        let saved = try disk.load().active!.movements[0].sets[0]
        XCTAssertEqual(saved.reps, 12)
        XCTAssertEqual(saved.kilograms, 40)
        XCTAssertNotNil(saved.completedAt)
    }

    func testUnreadableDataBlocksWrites() throws {
        let (disk, _) = try fixture()
        let data = Data("invalid".utf8)
        try data.write(to: disk.url)
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        XCTAssertFalse(tracker.change { $0.start(now: Date()) })
        XCTAssertEqual(try Data(contentsOf: disk.url), data)
        XCTAssertNotNil(tracker.error)
    }

    func testRuntimeCallbacksWithoutForegroundDeliverOnceAndPersist() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = {
            XCTAssertEqual(try? disk.load().rest?.consumed, true)
            attempts += 1
        }
        // No foreground lifecycle event: models timer / Bluetooth callbacks while locked.
        tracker.runtimeTick(now: deadline.addingTimeInterval(-1), instant: runtimeEpoch.advanced(by: .seconds(100)))
        tracker.runtimeTick(now: deadline, instant: runtimeEpoch.advanced(by: .seconds(101)))
        tracker.runtimeTick(now: deadline, instant: runtimeEpoch.advanced(by: .seconds(101)))
        tracker.resumeForeground(now: deadline.addingTimeInterval(0.5))
        tracker.runtimeTick(now: deadline.addingTimeInterval(1), instant: runtimeEpoch.advanced(by: .seconds(102)))
        XCTAssertEqual(attempts, 1)
    }

    func testSuspendedRuntimeDoesNotReplayInsideDeadlineGrace() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        // Continuous-clock advancement includes device sleep even when awake uptime barely changes.
        tracker.runtimeTick(now: deadline.addingTimeInterval(-10), instant: runtimeEpoch.advanced(by: .seconds(100)))
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.5), instant: runtimeEpoch.advanced(by: .seconds(110.5)))
        tracker.runtimeTick(now: deadline.addingTimeInterval(1), instant: runtimeEpoch.advanced(by: .seconds(111)))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }

    func testUnlockConsumesMissedRestButNextRestCanBuzz() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: deadline.addingTimeInterval(-0.5), instant: runtimeEpoch.advanced(by: .seconds(100)))
        tracker.resumeForeground(now: deadline)
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.5), instant: runtimeEpoch.advanced(by: .seconds(101)))
        XCTAssertEqual(attempts, 0)
        let movement = original.active!.movements[0]
        tracker.change {
            $0.undoSet(movementID: movement.id, setID: movement.sets[0].id)
            $0.completeSet(movementID: movement.id, setID: movement.sets[0].id, now: deadline)
        }
        let next = tracker.state.rest!.deadline
        tracker.runtimeTick(now: next.addingTimeInterval(-1), instant: runtimeEpoch.advanced(by: .seconds(190)))
        tracker.runtimeTick(now: next, instant: runtimeEpoch.advanced(by: .seconds(191)))
        XCTAssertEqual(attempts, 1)
    }

    func testRuntimeDisconnectedDeadlineCannotReplayOnReconnect() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        var connected = false
        tracker.strapReady = { connected }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: deadline.addingTimeInterval(-1), instant: runtimeEpoch.advanced(by: .seconds(100)))
        tracker.runtimeTick(now: deadline, instant: runtimeEpoch.advanced(by: .seconds(101)))
        connected = true
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.5), instant: runtimeEpoch.advanced(by: .seconds(101.5)))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }

    func testRuntimeFirstCallbackAfterLaunchCannotReplay() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: original.rest!.deadline, instant: runtimeEpoch.advanced(by: .seconds(100)))
        tracker.runtimeTick(now: original.rest!.deadline.addingTimeInterval(0.5), instant: runtimeEpoch.advanced(by: .seconds(100.5)))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }


    func testUnlockJustBeforeDeadlineKeepsFutureCueEligible() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.resumeForeground(now: deadline.addingTimeInterval(-0.1), instant: runtimeEpoch)
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.15),
            instant: runtimeEpoch.advanced(by: .milliseconds(250)))
        XCTAssertEqual(attempts, 1)
    }

}
