import XCTest
import Combine
import StrengthTracking
@testable import Strand

@MainActor
final class StrengthWorkoutControllerTests: XCTestCase {
    private let runtimeEpoch = ContinuousClock.now
    func testPresentationWaitsForGatesAndDoesNotChangePersistedWorkout() throws {
        let (disk, _) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let before = tracker.state
        let bytes = try Data(contentsOf: disk.url)
        var cues = 0; tracker.buzz = { cues += 1 }
        tracker.requestPresentation(sessionID: before.active!.id)
        let request = tracker.pendingPresentation
        for _ in 0..<3 { tracker.presentPendingRequest(allowed: false) }
        XCTAssertFalse(tracker.presented)
        XCTAssertEqual(tracker.pendingPresentation, request)
        XCTAssertNil(tracker.deliveredPresentation)
        tracker.presentPendingRequest(allowed: true)
        XCTAssertTrue(tracker.presented)
        XCTAssertNil(tracker.pendingPresentation)
        XCTAssertEqual(tracker.deliveredPresentation, request)
        tracker.presentPendingRequest(allowed: true)
        XCTAssertEqual(tracker.deliveredPresentation, request)
        XCTAssertEqual(tracker.state, before)
        XCTAssertEqual(try Data(contentsOf: disk.url), bytes)
        XCTAssertEqual(cues, 0)
    }

    func testDeferredSessionLinkCannotOpenReplacedSessionAndRepeatedLinkRefocuses() throws {
        let (disk, _) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        tracker.requestPresentation(sessionID: tracker.state.active!.id)
        XCTAssertTrue(tracker.change { $0.active = nil; $0.rest = nil; $0.start(now: Date()) })
        tracker.presentPendingRequest(allowed: true)
        XCTAssertFalse(tracker.presented)
        XCTAssertNil(tracker.pendingPresentation)
        XCTAssertNil(tracker.deliveredPresentation)
        let id = tracker.state.active!.id
        tracker.requestPresentation(sessionID: id)
        tracker.presentPendingRequest(allowed: true)
        let first = tracker.deliveredPresentation
        tracker.requestPresentation(sessionID: id)
        tracker.presentPendingRequest(allowed: true)
        XCTAssertNotEqual(first?.id, tracker.deliveredPresentation?.id)
        XCTAssertEqual(tracker.deliveredPresentation?.sessionID, id)
        tracker.presented = false
        XCTAssertTrue(tracker.change { $0.active = nil; $0.rest = nil })
        tracker.requestPresentation(sessionID: id)
        XCTAssertNil(tracker.pendingPresentation)
        tracker.requestPresentation()
        tracker.presentPendingRequest(allowed: true)
        XCTAssertTrue(tracker.presented)
        XCTAssertNil(tracker.deliveredPresentation?.sessionID)
    }
    func testExpiredLegacyRestIsRestoredAndConsumedSilentlyOnLaunch() throws {
        let (disk, original) = try fixture()
        var legacy = original; legacy.version = 1
        legacy.active!.restIntervals = nil
        let completed = Date().addingTimeInterval(-100)
        legacy.active!.startedAt = completed.addingTimeInterval(-20)
        legacy.active!.movements[0].sets[0].completedAt = completed
        legacy.rest!.deadline = completed.addingTimeInterval(90)
        try disk.save(legacy)
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        var cues = 0; tracker.strapReady = { true }; tracker.buzz = { cues += 1 }
        tracker.tick(allowWrist: true, now: Date())
        XCTAssertEqual(cues, 0)
        XCTAssertEqual(tracker.state.rest?.id, legacy.rest?.id)
        XCTAssertEqual(tracker.state.rest?.consumed, true)
        XCTAssertEqual(tracker.state.active?.openRest?.startedAt, completed)
        XCTAssertNil(tracker.state.active?.actualRest)
        XCTAssertEqual(try disk.load().version, 2)
    }
    func testConstantHeartRateRemainsFreshWithoutRepublishingValues() {
        let live = LiveState(); live.connected = true
        let start = Date(timeIntervalSince1970: 1000)
        var callbacks = 0; live.onHeartRateReceived = { callbacks += 1 }
        var publications = 0
        let subscription = live.$heartRate.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        for second in 0...20 { live.receiveHeartRate(118, at: start.addingTimeInterval(Double(second)), publishRepeatedValue: false) }
        XCTAssertEqual(callbacks, 21)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(live.currentHeartRate(at: start.addingTimeInterval(25)), 118)
        live.receiveHeartRate(0, at: start.addingTimeInterval(29))
        XCTAssertNil(live.currentHeartRate(at: start.addingTimeInterval(31)))
        live.receiveHeartRate(118, at: start.addingTimeInterval(32)); live.connected = false
        XCTAssertNil(live.currentHeartRate(at: start.addingTimeInterval(33)))
        live.connected = true
        XCTAssertNil(live.currentHeartRate(at: start.addingTimeInterval(33)))
        live.receiveHeartRate(118, at: start.addingTimeInterval(34))
        XCTAssertEqual(live.currentHeartRate(at: start.addingTimeInterval(35)), 118)
    }
    func testOtherSensorSourcesRetainRepeatedPacketPublications() {
        let live = LiveState(); live.connected = true
        var samples: [Int?] = []
        let subscription = live.$heartRate.dropFirst().sink { samples.append($0) }
        defer { subscription.cancel() }
        for _ in 0..<3 { live.receiveHeartRate(120) }
        live.receiveHeartRate(0)
        XCTAssertEqual(samples, [120, 120, 120])
        XCTAssertEqual(live.currentHeartRate(), 120)
    }
    func testSetStartAndUndoSurviveRestartAndFailedSave() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let second = StrengthSet(reps: 10, kilograms: 40)
        XCTAssertTrue(tracker.change { $0.active!.movements[0].sets.append(second) })
        let movement = tracker.state.active!.movements[0]
        XCTAssertTrue(tracker.change { $0.startSet(movementID: movement.id, setID: second.id, now: original.rest!.deadline) })
        let restored = StrengthWorkoutController(storage: disk, platformServices: false)
        XCTAssertEqual(restored.state.active?.nextSet?.set.startedAt, original.rest!.deadline)
        XCTAssertNil(restored.state.rest)
        try FileManager.default.removeItem(at: disk.url)
        try FileManager.default.createDirectory(at: disk.url, withIntermediateDirectories: true)
        let before = restored.state
        XCTAssertFalse(restored.change { $0.undoLastSet() })
        XCTAssertEqual(restored.state, before)
        try FileManager.default.removeItem(at: disk.url)
        XCTAssertTrue(restored.change { $0.undoLastSet() })
        XCTAssertNil(try disk.load().active?.movements[0].sets[0].completedAt)
    }
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


    func testReconnectAfterDeadlineWithoutDeadlineTickCannotBuzz() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var connected = false
        var attempts = 0
        tracker.strapReady = { connected }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: deadline.addingTimeInterval(-0.5), instant: runtimeEpoch)
        connected = true
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.5),
            instant: runtimeEpoch.advanced(by: .seconds(1)))
        tracker.runtimeTick(now: deadline.addingTimeInterval(1),
            instant: runtimeEpoch.advanced(by: .seconds(1.5)))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }

    func testReconnectBeforeDeadlineAllowsFreshCue() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var connected = false
        var attempts = 0
        tracker.strapReady = { connected }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: deadline.addingTimeInterval(-1), instant: runtimeEpoch)
        connected = true
        tracker.runtimeTick(now: deadline.addingTimeInterval(-0.5),
            instant: runtimeEpoch.advanced(by: .seconds(0.5)))
        tracker.runtimeTick(now: deadline,
            instant: runtimeEpoch.advanced(by: .seconds(1)))
        XCTAssertEqual(attempts, 1)
    }


    func testForegroundEntryConsumesBeforeTimerResumesFromShortLock() throws {
        let (disk, original) = try fixture()
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        let deadline = original.rest!.deadline
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.runtimeTick(now: deadline.addingTimeInterval(-0.5), instant: runtimeEpoch)
        // willEnterForeground arrives before a resumed timer, then didBecomeActive follows.
        tracker.resumeForeground(now: deadline.addingTimeInterval(0.25),
            instant: runtimeEpoch.advanced(by: .seconds(0.75)))
        tracker.runtimeTick(now: deadline.addingTimeInterval(0.5),
            instant: runtimeEpoch.advanced(by: .seconds(1)))
        tracker.resumeForeground(now: deadline.addingTimeInterval(0.75),
            instant: runtimeEpoch.advanced(by: .seconds(1.25)))
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
    }


    func testUnlockRetriesFailedLoadWithoutReplayingExpiredRest() throws {
        let (disk, original) = try fixture()
        // A read failure stands in for protected data that is temporarily unavailable.
        try Data("unavailable".utf8).write(to: disk.url)
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        XCTAssertNotNil(tracker.error)
        XCTAssertFalse(tracker.change { $0.start(now: Date()) })
        try disk.save(original)
        var attempts = 0
        tracker.strapReady = { true }
        tracker.buzz = { attempts += 1 }
        tracker.resumeForeground(now: original.rest!.deadline, instant: runtimeEpoch)
        XCTAssertEqual(tracker.state.active, original.active)
        XCTAssertEqual(try disk.load().rest?.consumed, true)
        XCTAssertNil(tracker.error)
        XCTAssertEqual(attempts, 0)
        XCTAssertTrue(tracker.change { $0.restSeconds = 30 })
    }

    func testUnlockRetryKeepsUnreadableDocumentUntouched() throws {
        let (disk, _) = try fixture()
        let original = Data("invalid".utf8)
        try original.write(to: disk.url)
        let tracker = StrengthWorkoutController(storage: disk, platformServices: false)
        tracker.resumeForeground()
        XCTAssertNotNil(tracker.error)
        XCTAssertFalse(tracker.change { $0.start(now: Date()) })
        XCTAssertEqual(try Data(contentsOf: disk.url), original)
    }

}
