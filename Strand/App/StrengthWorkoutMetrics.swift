import Foundation
import StrengthTracking
import StrandAnalytics
import WhoopProtocol

/// Derived from the existing local HR store; never writes a second workout or adds to day strain.
struct StrengthWorkoutMetrics {
    struct Point: Identifiable {
        let id: Int
        let minute: Double
        let bpm: Int
        let segment: Int
    }
    var points: [Point] = []
    var average: Int?
    var peak: Int?
    var cardioEffort: Double?
    var truncated = false
    var coveredSeconds = 0
    var zoneSeconds = Array(repeating: 0, count: 6)
    // Retain the boundaries used by this calculation, so labels and totals refresh together.
    var zoneSet = HRZones.zones(maxHR: 190)

    /// Keep chart work bounded for long sessions. Scoring and averages still use all accepted HR.
    /// Preserve bucket endpoints and extremes; segment IDs prevent bridging recording gaps.
    var plotPoints: [Point] {
        guard points.count > 1000 else { return points }
        let width = (points.count + 249) / 250
        var kept: [Int: Point] = [:]
        for start in stride(from: 0, to: points.count, by: width) {
            let bucket = points[start..<min(points.count, start + width)]
            for point in [bucket.first, bucket.last, bucket.min { $0.bpm < $1.bpm },
                          bucket.max { $0.bpm < $1.bpm }].compactMap({ $0 }) {
                kept[point.id] = point
            }
        }
        return kept.values.sorted { $0.id < $1.id }
    }

    static func calculate(session: StrengthSession, samples: [HRSample], now: Date,
                          maxHR: Double, restingHR: Double, sex: String,
                          method: StrainScorer.Method, truncated: Bool = false, zones: HRZoneSet? = nil) -> Self {
        let start = session.startedAt.timeIntervalSince1970
        let end = (session.finishedAt ?? now).timeIntervalSince1970
        var unique: [Int: HRSample] = [:]
        for sample in samples where Double(sample.ts) >= start && Double(sample.ts) <= end
            && (30...220).contains(sample.bpm) {
            if unique[sample.ts] == nil { unique[sample.ts] = sample }
        }
        let accepted = unique.values.sorted { $0.ts < $1.ts }
        var result = Self()
        result.zoneSet = zones ?? HRZones.zones(maxHR: maxHR)
        result.truncated = truncated
        var previous: Int?
        var segment = 0
        result.points = accepted.map { sample in
            if let previous, sample.ts - previous > 60 { segment += 1 }
            previous = sample.ts
            return Point(id: sample.ts, minute: (Double(sample.ts) - start) / 60,
                         bpm: sample.bpm, segment: segment)
        }
        if !accepted.isEmpty {
            result.peak = accepted.map(\.bpm).max()
            // Live and synced readings have different cadences. Integrate only covered intervals;
            // do not credit a sample with a long disconnect or extrapolate beyond the last reading.
            var weightedBPM = 0.0
            var coveredSeconds = 0
            let displayZones = result.zoneSet
            for (sample, next) in zip(accepted, accepted.dropFirst()) {
                let seconds = next.ts - sample.ts
                guard (1...60).contains(seconds) else { continue }
                weightedBPM += Double(sample.bpm * seconds)
                coveredSeconds += seconds
                result.zoneSeconds[displayZones.zoneNumber(forBPM: Double(sample.bpm))] += seconds
            }
            if coveredSeconds > 0 {
                result.coveredSeconds = coveredSeconds
                result.average = Int((weightedBPM / Double(coveredSeconds)).rounded())
            }
        }
        if !truncated {
            result.cardioEffort = StrainScorer.strain(accepted, maxHR: maxHR, restingHR: restingHR,
                                                      method: method, sex: sex)
        }
        return result
    }
}

extension StrengthSession {
    var completedReps: Int {
        movements.flatMap(\.sets).filter { $0.completedAt != nil }.reduce(0) { $0 + $1.reps }
    }
    var liftedKilograms: Double {
        movements.flatMap(\.sets).filter { $0.completedAt != nil }
            .reduce(0) { $0 + Double($1.reps) * $1.kilograms }
    }
}
