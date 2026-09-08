import SwiftUI
import Charts
import StrandDesign
import StrengthTracking

struct StrengthMetricsView: View {
    let session: StrengthSession
    let tracker: StrengthWorkoutController
    @State private var metrics = StrengthWorkoutMetrics()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Workout load").font(StrandFont.title2)
            Text("\(session.completedSets) sets · \(session.completedReps) reps completed")
                .font(StrandFont.bodyNumber)
            Text("\(session.unit.display(session.liftedKilograms).formatted(.number.precision(.fractionLength(0...1)))) \(session.unit.rawValue) moved")
                .font(StrandFont.title2).foregroundStyle(StrandPalette.accent)
            Text("Completed reps × logged weight. External load only; this is not a muscular-strain score.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Divider()
            Text("Heart rate").font(StrandFont.headline)
            if metrics.points.isEmpty {
                Text(loaded ? "No recorded heart rate for this workout yet. Connect WHOOP and sync; lifting entries still save without it." : "Loading recorded heart rate…")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            } else {
                Chart(metrics.points) { point in
                    LineMark(x: .value("Minutes", point.minute), y: .value("BPM", point.bpm),
                             series: .value("Recording segment", point.segment))
                        .foregroundStyle(StrandPalette.accent)
                    PointMark(x: .value("Minutes", point.minute), y: .value("BPM", point.bpm))
                        .symbolSize(4).foregroundStyle(StrandPalette.accent)
                }
                .chartXAxisLabel("Minutes since start")
                .chartYAxisLabel("bpm")
                .frame(height: 160)
                .accessibilityLabel("Recorded workout heart rate. Gaps longer than one minute are not connected.")
                Text("Average \(metrics.average.map(String.init) ?? "—") · Peak \(metrics.peak ?? 0) bpm")
                    .font(StrandFont.bodyNumber)
                Text("Average covers recorded intervals up to one minute; longer gaps are excluded.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            if let effort = metrics.cardioEffort {
                Text("Cardio effort · \(effort.formatted(.number.precision(.fractionLength(1)))) / 100")
                    .font(StrandFont.headline)
            } else {
                Text("Cardio effort · insufficient recorded data").font(StrandFont.headline)
            }
            Text(metrics.truncated
                ? "Recording exceeds the display limit; cardio scoring is withheld."
                : "NOOP estimate from recorded HR and your current profile. Short or incomplete recordings may not score. Not WHOOP Strain; no muscular/cardio percentage split.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("HR comes from your local sensor database. Sync can fill gaps; database deletion removes the graph. Summaries refresh every 15 seconds while open.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .task(id: session.id) {
            repeat {
                let result = await tracker.loadMetrics(session)
                guard !Task.isCancelled else { return }
                metrics = result; loaded = true
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            } while !Task.isCancelled
        }
    }
}
