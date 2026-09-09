import Foundation
import StrandAnalytics

/// Whole-BPM labels follow the same inclusive boundaries as the analytics classifier.
struct StrengthZoneScale {
    struct Band: Identifiable {
        let id: Int
        let lower: Double
        let upper: Double
        var midpoint: Double { (lower + upper) / 2 }
    }
    let zones: HRZoneSet
    var starts: [Double] { zones.zones.map { ceil($0.lower) } }
    var domain: ClosedRange<Double> {
        max(0, starts[0] - 20)...max(zones.maxHR, starts[4] + 20)
    }
    static func name(_ number: Int) -> String {
        ["Below", "Easy", "Light", "Moderate", "Hard", "Peak"][min(5, max(0, number))]
    }
    func number(for bpm: Int) -> Int { zones.zoneNumber(forBPM: Double(bpm)) }
    func range(_ number: Int) -> String {
        if number == 0 { return "Under \(Int(starts[0])) bpm" }
        if number == 5 { return "\(Int(starts[4]))+ bpm" }
        let lower = Int(starts[number - 1]), upper = Int(starts[number]) - 1
        return lower <= upper ? "\(lower)–\(upper) bpm" : "No whole-BPM readings"
    }
    func nextBoundary(for bpm: Int) -> String {
        let zone = number(for: bpm)
        guard zone < 5 else { return "Highest heart-rate zone" }
        let threshold = Int(starts[zone])
        return "\(Self.name(number(for: threshold))) starts at \(threshold) bpm"
    }
    func fraction(_ bpm: Double, in bounds: ClosedRange<Double>? = nil) -> Double {
        let bounds = bounds ?? domain
        return min(1, max(0, (bpm - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)))
    }
    func bands(in bounds: ClosedRange<Double>? = nil) -> [Band] {
        let bounds = bounds ?? domain
        return (0...5).compactMap { zone in
            let lower = max(bounds.lowerBound, zone == 0 ? bounds.lowerBound : starts[zone - 1])
            let upper = min(bounds.upperBound, zone == 5 ? bounds.upperBound : starts[zone])
            return upper > lower ? Band(id: zone, lower: lower, upper: upper) : nil
        }
    }
    /// Close custom boundaries must not produce overlapping labels on small screens.
    func visibleTicks(width: Double, minimumSpacing: Double = 32) -> [Double] {
        var kept: [Double] = []
        for value in starts {
            if let last = kept.last, (fraction(value) - fraction(last)) * width < minimumSpacing { continue }
            kept.append(value)
        }
        return kept
    }
}
