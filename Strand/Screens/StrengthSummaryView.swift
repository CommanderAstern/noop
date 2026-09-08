import SwiftUI
import Charts
import StrengthTracking
import StrandDesign

struct StrengthSummaryView: View {
    let session: StrengthSession
    @ObservedObject var tracker: StrengthWorkoutController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metrics = StrengthWorkoutMetrics()
    @State private var loaded = false
    @State private var selectedMovement: UUID?
    @State private var selectedMinute: Double?
    @State private var routine: StrengthRoutine?
    private var records: [StrengthRecord] { StrengthProgress.records(in: session, history: tracker.state.history) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(session.name).font(.title.bold())
                Text(session.startedAt, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(StrandPalette.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                    StrengthStat(value: "\(strengthWeight(session.volumeKilograms, unit: session.unit)) \(session.unit.rawValue)", label: "Total lifted")
                    StrengthStat(value: "\(session.workingSets)", label: "Working sets")
                    StrengthStat(value: strengthTime(Int((session.finishedAt ?? session.startedAt).timeIntervalSince(session.startedAt))), label: "Duration")
                    StrengthStat(value: session.actualRest.map { strengthTime(Int($0)) } ?? "—", label: "Recorded rest")
                }
                Text("Logged reps × external weight, including warm-ups. Warm-up volume: \(strengthWeight(session.volumeKilograms - session.workingVolume, unit: session.unit)) \(session.unit.rawValue).")
                    .font(.caption).foregroundStyle(StrandPalette.textSecondary)
                HStack { Text("Cardio estimate"); Spacer(); Text(metrics.cardioEffort.map { "\($0.formatted(.number.precision(.fractionLength(1)))) / 100" } ?? "—").bold() }
                Text("NOOP estimate from recorded HR and your current profile; not WHOOP muscular Strain.").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                Divider()
                Text("Heart rate").font(.title2.bold())
                if metrics.points.isEmpty {
                    Text(loaded ? "No recorded heart rate. Sync your strap to fill available data; your lifting log is saved." : "Loading recorded heart rate…")
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            selectionButton("All", id: nil)
                            ForEach(session.movements) { selectionButton($0.exercise.name, id: $0.id) }
                        }
                    }
                    StrengthHeartChart(session: session, metrics: metrics, movementID: selectedMovement, selectedMinute: $selectedMinute)
                    Text("Average \(metrics.average.map(String.init) ?? "—") · Peak \(metrics.peak.map(String.init) ?? "—") bpm").font(.subheadline.monospacedDigit())
                    Text("Recorded coverage: \(strengthTime(metrics.coveredSeconds)). Gaps over one minute are excluded. Highlighted bands use recorded set start/end times; dots mark completions without start times.").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                    DisclosureGroup("Time in heart-rate zones") {
                        ForEach(0...5, id: \.self) { zone in HStack { Text(zone == 0 ? "Below Zone 1" : "Zone \(zone)"); Spacer(); Text(strengthTime(metrics.zoneSeconds[zone])).monospacedDigit() }.padding(.vertical, 4) }
                    }
                }
                if !records.isEmpty {
                    Text("Achievements").font(.title2.bold())
                    ForEach(records) { record in
                        Button { selectedMovement = session.movements.first(where: { $0.exercise.id == record.exercise.id })?.id } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "trophy.fill").font(.title).foregroundStyle(StrandPalette.zone3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.heaviest ? "New heaviest working set" : "New \(record.reps)-rep best").font(.headline)
                                    Text("\(record.exercise.name) · \(strengthWeight(record.kilograms, unit: session.unit)) \(session.unit.rawValue) × \(record.reps)")
                                    Text("Previous: \(strengthWeight(record.previousKilograms, unit: session.unit)) \(session.unit.rawValue)").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(16).background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
                Text("Exercise breakdown").font(.title2.bold())
                ForEach(session.movements) { movement in
                    DisclosureGroup {
                        ForEach(Array(movement.sets.enumerated()), id: \.element.id) { index, set in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(set.kind == .warmup ? "Warm-up" : "Set \(index + 1)") · \(strengthWeight(set.kilograms, unit: session.unit)) \(session.unit.rawValue) × \(set.reps)")
                                Text(set.completedAt == nil ? "Not completed" : "Completed").font(.caption)
                                if let interval = session.restIntervals?.first(where: { $0.setID == set.id }) {
                                    Text("Rest target \(strengthTime(interval.plannedSeconds)) · actual \(interval.actualSeconds.map { strengthTime(Int($0)) } ?? "unknown")\(interval.reason == .finished ? " · trailing rest" : "")").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                        Button("Highlight on graph") { selectedMovement = movement.id }
                    } label: {
                        HStack { StrengthExerciseArt(exercise: movement.exercise).frame(width: 50, height: 44)
                            VStack(alignment: .leading) { Text(movement.exercise.name).font(.headline); Text("\(movement.sets.filter { $0.completedAt != nil }.count) sets · \(movement.exercise.equipment)").font(.caption) }
                        }
                    }
                    Divider()
                }
                if let notes = session.notes, !notes.isEmpty { Text("Notes").font(.headline); Text(notes) }
                Button("Save as template") { routine = StrengthRoutine(name: session.name, movements: session.movements, restSeconds: session.restSeconds, unit: session.unit) }.buttonStyle(.bordered)
            }.padding(20)
        }
        .background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary).tint(StrandPalette.accent)
        .navigationTitle("Workout complete")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $routine) { StrengthRoutineEditor(routine: $0, tracker: tracker) }
        .task(id: session.id) {
            while !Task.isCancelled {
                let refreshed = await tracker.loadMetrics(session)
                guard !Task.isCancelled else { return }
                metrics = refreshed; loaded = true
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedMovement)
    }
    private func selectionButton(_ name: String, id: UUID?) -> some View {
        Button(name) { selectedMovement = id; selectedMinute = nil }.buttonStyle(.bordered).tint(selectedMovement == id ? StrandPalette.accent : StrandPalette.textSecondary)
    }
}

struct StrengthHeartChart: View {
    let session: StrengthSession
    let metrics: StrengthWorkoutMetrics
    let movementID: UUID?
    @Binding var selectedMinute: Double?
    private var sets: [StrengthSet] { session.movements.filter { $0.id == movementID }.flatMap(\.sets).filter { $0.completedAt != nil } }
    private var yMin: Int { max(30, (metrics.points.map(\.bpm).min() ?? 60) - 10) }
    private var yMax: Int { min(230, (metrics.peak ?? 180) + 10) }
    private func minute(_ date: Date) -> Double { date.timeIntervalSince(session.startedAt) / 60 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(sets) { set in
                    if let start = set.startedAt, let end = set.completedAt {
                        RectangleMark(xStart: .value("Start", minute(start)), xEnd: .value("End", minute(end)), yStart: .value("Low", yMin), yEnd: .value("High", yMax))
                            .foregroundStyle(StrandPalette.accent.opacity(0.16))
                    } else if let end = set.completedAt {
                        RuleMark(x: .value("Completion", minute(end))).foregroundStyle(StrandPalette.accent.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
                ForEach(metrics.plotPoints) { point in
                    LineMark(x: .value("Minutes", point.minute), y: .value("BPM", point.bpm), series: .value("Segment", point.segment)).foregroundStyle(StrandPalette.accent)
                }
                if let selectedMinute { RuleMark(x: .value("Selected time", selectedMinute)).foregroundStyle(StrandPalette.textSecondary) }
            }.chartYScale(domain: yMin...max(yMin + 1, yMax)).chartXAxisLabel("Minutes since start").chartYAxisLabel("bpm").frame(height: 210)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                            if let minute: Double = proxy.value(atX: x) { selectedMinute = minute }
                        })
                    }
                }
            if let selectedMinute, let point = metrics.points.min(by: { abs($0.minute - selectedMinute) < abs($1.minute - selectedMinute) }), abs(point.minute - selectedMinute) <= 1 {
                Text("\(strengthTime(Int(point.minute * 60))) · \(point.bpm) bpm").font(.caption.monospacedDigit())
                if let movement = session.movements.first(where: { $0.sets.contains { set in
                    guard let start = set.startedAt, let end = set.completedAt else { return false }
                    return point.minute >= minute(start) && point.minute <= minute(end)
                } }) { Text(movement.exercise.name).font(.caption).foregroundStyle(StrandPalette.accent) }
            }
        }
    }
}
