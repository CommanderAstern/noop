import XCTest
@testable import StrengthTracking

@MainActor
final class StrengthRestSchedulerTests: XCTestCase {
    final class Transport {
        var pending: Set<UUID> = []
        var waiting: [CheckedContinuation<Void, Never>] = []
        var started: (() -> Void)?
        var removed: [UUID] = []
        func add(_ rest: StrengthRest) async {
            await withCheckedContinuation { continuation in
                waiting.append(continuation)
                started?()
            }
            pending.insert(rest.id)
        }
        func remove(_ id: UUID) { pending.remove(id); removed.append(id) }
        func finishAdd() { waiting.removeFirst().resume() }
    }
    func timer() -> StrengthRest { StrengthRest(sessionID: UUID(), setID: UUID(), deadline: Date().addingTimeInterval(60)) }

    func testCancellationCleansUpAnAddThatFinishesLate() async {
        let transport = Transport()
        let scheduler = StrengthRestScheduler(add: { await transport.add($0) }, remove: transport.remove, onError: {})
        let started = expectation(description: "OS add started")
        transport.started = { started.fulfill() }
        let rest = timer()
        scheduler.replace(with: rest)
        await fulfillment(of: [started], timeout: 2)
        scheduler.replace(with: nil)
        transport.finishAdd()
        await scheduler.drain()
        XCTAssertTrue(transport.pending.isEmpty)
        XCTAssertEqual(transport.removed, [rest.id, rest.id])
    }

    func testReplacementAndSameIDRescheduleWaitForOldCleanup() async {
        for sameID in [false, true] {
            let transport = Transport()
            let scheduler = StrengthRestScheduler(add: { await transport.add($0) }, remove: transport.remove, onError: {})
            let first = timer()
            let second = sameID ? first : timer()
            let firstStarted = expectation(description: "first add")
            transport.started = { firstStarted.fulfill() }
            scheduler.replace(with: first)
            await fulfillment(of: [firstStarted], timeout: 2)
            let secondStarted = expectation(description: "second add after cleanup")
            transport.started = {
                XCTAssertEqual(transport.removed, [first.id, first.id])
                secondStarted.fulfill()
            }
            scheduler.replace(with: second)
            transport.finishAdd()
            await fulfillment(of: [secondStarted], timeout: 2)
            transport.finishAdd()
            await scheduler.drain()
            XCTAssertEqual(transport.pending, [second.id])
        }
    }
}
