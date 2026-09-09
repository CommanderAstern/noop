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
    func testCustomZonesCountOnlyRecordedIntervals() {
        let zones = HRZones.zones(maxHR: 190, customLowerBounds: [80, 100, 120, 140, 160])
        let samples = [HRSample(ts: 1000, bpm: 110), HRSample(ts: 1030, bpm: 150),
                       HRSample(ts: 1060, bpm: 150), HRSample(ts: 1500, bpm: 170)]
        let result = StrengthWorkoutMetrics.calculate(session: StrengthSession(now: start, unit: .kg),
            samples: samples, now: start.addingTimeInterval(1000), maxHR: 190, restingHR: 60,
            sex: "male", method: .edwards, zones: zones)
        XCTAssertEqual(result.coveredSeconds, 60)
        XCTAssertEqual(result.zoneSeconds, [0, 0, 30, 0, 30, 0])
        XCTAssertEqual(result.zoneSet, zones)
    }

    func testDisplayRangesAgreeWithFractionalAnalyticsBoundaries() {
        let zones = HRZones.zones(maxHR: 187)
        let scale = StrengthZoneScale(zones: zones)
        XCTAssertEqual(scale.starts, [94, 113, 131, 150, 169])
        XCTAssertEqual(scale.range(1), "94–112 bpm")
        XCTAssertEqual(scale.range(5), "169+ bpm")
        for bpm in 30...220 {
            let expected = scale.starts.filter { Double(bpm) >= $0 }.count
            XCTAssertEqual(scale.number(for: bpm), expected, "\(bpm) bpm")
        }
        XCTAssertEqual(scale.nextBoundary(for: 112), "Light starts at 113 bpm")
    }

    func testCustomZoneBarAndGraphShareBoundariesAndHandleAboveMaximum() {
        let scale = StrengthZoneScale(zones: HRZones.zones(maxHR: 190, customLowerBounds: [90, 110, 130, 150, 210]))
        XCTAssertEqual(scale.number(for: 209), 4)
        XCTAssertEqual(scale.number(for: 220), 5)
        XCTAssertEqual(scale.range(4), "150–209 bpm")
        XCTAssertEqual(scale.domain.upperBound, 230)
        let bands = scale.bands(in: 60...240)
        XCTAssertEqual(bands.first?.lower, 60)
        XCTAssertEqual(bands.last?.upper, 240)
        for pair in zip(bands, bands.dropFirst()) { XCTAssertEqual(pair.0.upper, pair.1.lower) }
        XCTAssertEqual(scale.fraction(0), 0)
        XCTAssertEqual(scale.fraction(300), 1)
        XCTAssertEqual(scale.fraction(110), 0.25, accuracy: 0.0001)
    }

    func testCloseCustomBoundariesDoNotOverlapTicksOrInventIntegerRanges() {
        let scale = StrengthZoneScale(zones: HRZones.zones(maxHR: 190, customLowerBounds: [90.1, 90.2, 91, 130, 170]))
        XCTAssertEqual(scale.range(1), "No whole-BPM readings")
        XCTAssertEqual(scale.number(for: 91), 3)
        XCTAssertEqual(scale.nextBoundary(for: 90), "Moderate starts at 91 bpm")
        XCTAssertFalse(scale.bands().contains { $0.id == 1 || $0.id == 2 })
        let ticks = scale.visibleTicks(width: 240)
        for pair in zip(ticks, ticks.dropFirst()) {
            XCTAssertGreaterThanOrEqual((scale.fraction(pair.1) - scale.fraction(pair.0)) * 240, 32)
        }
    }

    func testTimelinePreservesLegacyCompletionWithoutInventingAStartAndKeepsSessionDuration() {
        var session = StrengthSession(now: start, unit: .kg)
        session.finishedAt = start.addingTimeInterval(2400)
        var timed = StrengthSet(reps: 8, kilograms: 60)
        timed.startedAt = start.addingTimeInterval(120); timed.completedAt = start.addingTimeInterval(160)
        var legacy = StrengthSet(reps: 8, kilograms: 60); legacy.completedAt = start.addingTimeInterval(400)
        var outside = legacy; outside.id = UUID(); outside.completedAt = start.addingTimeInterval(2500)
        session.movements = [StrengthMovement(exercise: StrengthExercise.catalog[1], sets: [timed, legacy, outside, StrengthSet()])]
        let all = StrengthExerciseTimeline(session: session, movementID: nil)
        let selected = StrengthExerciseTimeline(session: session, movementID: session.movements[0].id)
        XCTAssertEqual(all.duration, 40)
        XCTAssertEqual(selected.duration, all.duration)
        XCTAssertEqual(all.marks.count, 2)
        XCTAssertEqual(all.marks[0].start, 2)
        XCTAssertEqual(all.marks[0].end, 160.0 / 60, accuracy: 0.0001)
        XCTAssertNil(all.marks[1].start)
        XCTAssertEqual(selected.marks.map(\.id), all.marks.map(\.id))
        XCTAssertTrue(StrengthExerciseTimeline(session: session, movementID: UUID()).marks.isEmpty)
    }
}
