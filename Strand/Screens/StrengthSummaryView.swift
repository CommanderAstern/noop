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
    @AppStorage("strength.summaryZones") private var showZones = true
    private let initialScrollTarget: String?
    init(session: StrengthSession, tracker: StrengthWorkoutController, initialScrollTarget: String? = nil, highlightedMovement: UUID? = nil) {
        self.session = session; self.tracker = tracker; self.initialScrollTarget = initialScrollTarget
        _selectedMovement = State(initialValue: highlightedMovement)
    }
    private var records: [StrengthRecord] { StrengthProgress.records(in: session, history: tracker.state.history) }
    var body: some View {
        ScrollViewReader { proxy in
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
                HStack {
                    Text("Heart rate").font(.title2.bold())
                    Spacer()
                    Toggle(isOn: $showZones) { Label("Zones", systemImage: "square.3.layers.3d") }
                        .toggleStyle(.button).font(.subheadline)
                        .disabled(metrics.points.isEmpty)
                }.id("heart-rate")
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
                    StrengthHeartChart(session: session, metrics: metrics, movementID: selectedMovement, showZones: showZones, selectedMinute: $selectedMinute)
                    Text("Average \(metrics.average.map(String.init) ?? "—") · Peak \(metrics.peak.map(String.init) ?? "—") bpm").font(.subheadline.monospacedDigit())
                    Text("Recorded coverage: \(strengthTime(metrics.coveredSeconds)). Gaps over one minute are excluded. The exercise strip shows recorded sets; dots mark completions without a start time.").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                    DisclosureGroup("Time in zones") {
                        ForEach(0...5, id: \.self) { zone in
                            HStack(spacing: 10) {
                                Circle().fill(strengthZoneColor(zone)).frame(width: 8, height: 8).accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(StrengthZoneScale.name(zone))
                                    Text(StrengthZoneScale(zones: metrics.zoneSet).range(zone)).font(.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                Spacer()
                                Text(strengthTime(metrics.zoneSeconds[zone])).monospacedDigit()
                            }.padding(.vertical, 4)
                        }
                        Text("Uses your current profile zones. Only recorded intervals are counted.").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                if !records.isEmpty {
                    Text("Achievements").font(.title2.bold()).id("achievements")
                    ForEach(records) { record in
                        Button { selectedMovement = session.movements.first(where: { $0.sets.contains { $0.id == record.setID } })?.id } label: {
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
                        ForEach(movement.sets) { set in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(set.kind == .warmup ? "Warm-up" : "Set \((movement.ordinal(of: set.id) ?? 0) + 1)") · \(strengthWeight(set.kilograms, unit: session.unit)) \(session.unit.rawValue) × \(set.reps)")
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
        .onChange(of: loaded) { ready in
            if ready, let initialScrollTarget { proxy.scrollTo(initialScrollTarget, anchor: .top) }
        }
        }
    }
    private func selectionButton(_ name: String, id: UUID?) -> some View {
        Button(name) { selectedMovement = id; selectedMinute = nil }.buttonStyle(.bordered).tint(selectedMovement == id ? StrandPalette.accent : StrandPalette.textSecondary)
    }
}
