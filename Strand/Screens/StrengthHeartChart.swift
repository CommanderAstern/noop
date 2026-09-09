import SwiftUI
import Charts
import StrengthTracking
import StrandDesign

struct StrengthHeartChart: View {
    let session: StrengthSession
    let metrics: StrengthWorkoutMetrics
    let movementID: UUID?
    let showZones: Bool
    @Binding var selectedMinute: Double?
    private var scale: StrengthZoneScale { StrengthZoneScale(zones: metrics.zoneSet) }
    private var timeline: StrengthExerciseTimeline { StrengthExerciseTimeline(session: session, movementID: movementID) }
    private var bounds: ClosedRange<Double> {
        if showZones {
            return min(scale.domain.lowerBound, Double(metrics.points.map(\.bpm).min() ?? 60) - 5)...max(scale.domain.upperBound, Double(metrics.peak ?? 180) + 5)
        }
        let lower = max(0, Double(metrics.points.map(\.bpm).min() ?? 60) - 10)
        return lower...max(lower + 1, Double(metrics.peak ?? 180) + 10)
    }
    private var labeledBands: [StrengthZoneScale.Band] {
        scale.bands(in: bounds).filter { ($0.upper - $0.lower) / (bounds.upperBound - bounds.lowerBound) >= 0.12 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if showZones {
                    ForEach(scale.bands(in: bounds)) { band in
                        RectangleMark(xStart: .value("Start", 0.0), xEnd: .value("End", timeline.duration),
                                      yStart: .value("Lower BPM", band.lower), yEnd: .value("Upper BPM", band.upper))
                            .foregroundStyle(strengthZoneColor(band.id).opacity(0.14)).accessibilityHidden(true)
                    }
                }
                ForEach(metrics.plotPoints) { point in
                    LineMark(x: .value("Minutes", point.minute), y: .value("BPM", point.bpm), series: .value("Segment", point.segment))
                        .foregroundStyle(StrandPalette.accent)
                    // A lone sample in a disconnected segment must remain visible.
                    PointMark(x: .value("Minutes", point.minute), y: .value("BPM", point.bpm))
                        .symbolSize(3).foregroundStyle(StrandPalette.accent)
                }
                if let selectedMinute { RuleMark(x: .value("Selected time", selectedMinute)).foregroundStyle(StrandPalette.textSecondary) }
            }
            .chartXScale(domain: 0...timeline.duration)
            .chartYScale(domain: bounds)
            .chartXAxisLabel("Minutes since start")
            .chartYAxisLabel("bpm")
            .chartYAxis {
                AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() }
                if showZones {
                    AxisMarks(position: .trailing, values: labeledBands.map(\.midpoint)) { value in
                        if let midpoint = value.as(Double.self), let band = labeledBands.first(where: { $0.midpoint == midpoint }) {
                            AxisValueLabel {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(StrengthZoneScale.name(band.id)).foregroundStyle(strengthZoneColor(band.id))
                                    Text(scale.range(band.id).replacingOccurrences(of: " bpm", with: "")).foregroundStyle(StrandPalette.textSecondary)
                                }.font(.caption2)
                            }
                        }
                    }
                }
            }
            .frame(height: 270)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = geometry[proxy.plotAreaFrame]
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard plot.contains(value.location), let minute: Double = proxy.value(atX: value.location.x - plot.minX) else { return }
                                selectedMinute = minute
                            })
                        // Both marks and this strip use this exact ChartProxy, including axis insets.
                        Text("\(session.movements.first(where: { $0.id == movementID })?.exercise.name ?? "All exercises") · \(timeline.marks.count) sets")
                            .font(.caption).lineLimit(1).frame(width: plot.width, alignment: .leading)
                            .offset(x: plot.minX, y: plot.maxY + 48)
                        Capsule().fill(StrandPalette.surfaceRaised).frame(width: plot.width, height: 10)
                            .offset(x: plot.minX, y: plot.maxY + 70)
                        ForEach(timeline.marks) { mark in
                            if let end = proxy.position(forX: mark.end) {
                                if let startMinute = mark.start, let start = proxy.position(forX: startMinute), end > start {
                                    RoundedRectangle(cornerRadius: 2).fill(StrandPalette.accent)
                                        .frame(width: end - start, height: 10).offset(x: plot.minX + start, y: plot.maxY + 70)
                                        .accessibilityLabel("\(mark.name), \(strengthTime(Int(startMinute * 60))) to \(strengthTime(Int(mark.end * 60)))")
                                } else {
                                    Circle().fill(StrandPalette.accent).frame(width: 6, height: 6)
                                        .offset(x: plot.minX + end - 3, y: plot.maxY + 72)
                                        .accessibilityLabel("\(mark.name), completed at \(strengthTime(Int(mark.end * 60))); start time unavailable")
                                }
                            }
                        }
                    }
                }
            }.padding(.bottom, 86)
            if let selectedMinute, let point = metrics.points.min(by: { abs($0.minute - selectedMinute) < abs($1.minute - selectedMinute) }), abs(point.minute - selectedMinute) <= 1 {
                Text("\(strengthTime(Int(point.minute * 60))) · \(point.bpm) bpm · \(StrengthZoneScale.name(scale.number(for: point.bpm)))")
                    .font(.caption.monospacedDigit())
                if let mark = StrengthExerciseTimeline(session: session, movementID: nil).marks.first(where: {
                    guard let start = $0.start else { return false }
                    return point.minute >= start && point.minute <= $0.end
                }) { Text(mark.name).font(.caption).foregroundStyle(StrandPalette.accent) }
            }
        }
    }
}
