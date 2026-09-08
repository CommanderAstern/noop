import XCTest
import StrengthTracking
import StrandAnalytics
import WhoopProtocol
@testable import Strand

final class StrengthWorkoutMetricsTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    func calculate(_ samples: [HRSample], finished: Double? = nil, truncated: Bool = false) -> StrengthWorkoutMetrics {
        var session = StrengthSession(now: start, unit: .kg)
        session.finishedAt = finished.map { Date(timeIntervalSince1970: $0) }
        return .calculate(session: session, samples: samples, now: start.addingTimeInterval(1200),
                          maxHR: 190, restingHR: 60, sex: "male", method: .edwards, truncated: truncated)
    }
    func testFiltersWindowInvalidValuesAndDuplicateTimestamps() {
        let result = calculate([HRSample(ts: 999, bpm: 100), HRSample(ts: 1000, bpm: 100),
            HRSample(ts: 1000, bpm: 200), HRSample(ts: 1001, bpm: 0),
            HRSample(ts: 1002, bpm: 120), HRSample(ts: 1011, bpm: 180)], finished: 1010)
        XCTAssertEqual(result.points.map(\.bpm), [100, 120])
        XCTAssertEqual(result.average, 100)
        XCTAssertEqual(result.peak, 120)
        XCTAssertNil(result.cardioEffort)
    }
    func testAverageWeightsMixedCadencesAndExcludesDisconnects() {
        let dense = (1000..<1600).map { HRSample(ts: $0, bpm: 120) }
        let sparse = stride(from: 1600, through: 2200, by: 30).map { HRSample(ts: $0, bpm: 180) }
        XCTAssertEqual(calculate(dense + sparse).average, 150)
        let disconnected = [HRSample(ts: 1000, bpm: 100), HRSample(ts: 1030, bpm: 100),
                            HRSample(ts: 2000, bpm: 160), HRSample(ts: 2030, bpm: 160)]
        XCTAssertEqual(calculate(disconnected).average, 130)
        XCTAssertNil(calculate([HRSample(ts: 1000, bpm: 100)]).average)
    }
    func testGraphBreaksAcrossMissingRecordingAndTruncationWithholdsScore() {
        let result = calculate([HRSample(ts: 1000, bpm: 100), HRSample(ts: 1030, bpm: 110),
                                HRSample(ts: 1600, bpm: 130)])
        XCTAssertEqual(result.points.map(\.segment), [0, 0, 1])
        let dense = (1000...1600).map { HRSample(ts: $0, bpm: 140) }
        XCTAssertNotNil(calculate(dense).cardioEffort)
        XCTAssertNil(calculate(dense, truncated: true).cardioEffort)
    }
    func testLongRecordingChartIsBoundedAndPreservesExtremes() {
        let samples = (1000...2200).map { HRSample(ts: $0, bpm: $0 == 1777 ? 200 : 100) }
        let result = calculate(samples)
        XCTAssertLessThanOrEqual(result.plotPoints.count, 1000)
        XCTAssertEqual(result.plotPoints.first?.id, 1000)
        XCTAssertEqual(result.plotPoints.last?.id, 2200)
        XCTAssertTrue(result.plotPoints.contains { $0.bpm == 200 })
        XCTAssertEqual(result.points.count, 1201)
    }
    func testLiftingTotalsExcludeUnfinishedSetsAndRetainUnitConversion() {
        var session = StrengthSession(now: start, unit: .kg)
        var completed = StrengthSet(reps: 8, kilograms: 60)
        completed.completedAt = start
        session.movements = [StrengthMovement(exercise: StrengthExercise.catalog[0],
            sets: [completed, StrengthSet(reps: 10, kilograms: 100)])]
        XCTAssertEqual(session.completedReps, 8)
        XCTAssertEqual(session.liftedKilograms, 480)
        session.unit = .lb
        XCTAssertEqual(session.liftedKilograms, 480)
        XCTAssertEqual(session.unit.kilograms(session.unit.display(session.liftedKilograms)), 480, accuracy: 0.00001)
    }
}
