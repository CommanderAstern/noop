import SwiftUI
import StrengthTracking
import StrandDesign

struct StrengthSessionView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    var finished: (StrengthSession) -> Void
    var browse: () -> Void
    @AppStorage("strength.sessionTab") private var tab = "Live"
    @State private var picker = false
    @State private var settings = false
    @State private var finishAlert = false
    @State private var discardAlert = false
    @State private var notesAlert = false
    @State private var notes = ""
    @State private var edit: SetSelection?
    @State private var restMovement: StrengthMovement?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct SetSelection: Identifiable { let movement: StrengthMovement; let set: StrengthSet; var id: UUID { self.set.id } }

    private func focusRequestedSession() {
        guard let id = tracker.deliveredPresentation?.sessionID, id == tracker.state.active?.id else { return }
        tab = "Live"; picker = false; settings = false; restMovement = nil; edit = nil
        finishAlert = false; discardAlert = false; notesAlert = false
    }

    var body: some View {
        if let session = tracker.state.active {
            VStack(spacing: 0) {
                Picker("Session view", selection: $tab) { Text("Live").tag("Live"); Text("Exercises").tag("Exercises") }
                    .pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if tab == "Live" { live(session) }
                        else {
                            ForEach(session.movements) { movement in movementView(movement, session: session) }
                            Button { picker = true } label: { Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                        }
                    }.padding(20)
                }
                bottom(session)
            }
            .navigationTitle(session.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Finish") { finishAlert = true }.disabled(session.completedSets == 0) }
                ToolbarItem {
                    Menu {
                        Button("Undo last set") { tracker.change { $0.undoLastSet() } }.disabled(session.completedSets == 0)
                        Menu("Edit completed set") {
                            ForEach(session.movements) { movement in
                                ForEach(movement.sets.filter { $0.completedAt != nil }) { set in
                                    Button("\(movement.exercise.name) · \(set.reps) reps") { edit = SetSelection(movement: movement, set: set) }
                                }
                            }
                        }.disabled(session.completedSets == 0)
                        Button("Workout notes") { notes = session.notes ?? ""; notesAlert = true }
                        Button("Workout settings") { settings = true }
                        Button("Browse training days", action: browse)
                        Button("Discard workout", role: .destructive) { discardAlert = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More workout actions")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tab)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: session.completedSets)
            .onAppear { focusRequestedSession() }
            .onChangeCompat(of: tracker.deliveredPresentation) { _ in focusRequestedSession() }
            .sheet(isPresented: $picker) { StrengthExercisePicker(tracker: tracker) }
            .sheet(isPresented: $settings) { StrengthSettingsView(tracker: tracker) }
            .sheet(item: $restMovement) { movement in restEditor(movement) }
            .sheet(item: $edit) { selection in
                StrengthSetEditor(set: selection.set, unit: session.unit) { updated in
                    tracker.change { state in
                        guard let m = state.active?.movements.firstIndex(where: { $0.id == selection.movement.id }),
                              let s = state.active?.movements[m].sets.firstIndex(where: { $0.id == updated.id }) else { return }
                        state.active?.movements[m].sets[s].reps = updated.reps
                        state.active?.movements[m].sets[s].kilograms = updated.kilograms
                        state.active?.movements[m].sets[s].kind = updated.kind
                    }
                }
            }
            .alert("Finish and save workout?", isPresented: $finishAlert) {
                Button("Keep training", role: .cancel) {}
                Button("Finish") {
                    if tracker.change({ $0.finish(now: Date()) }), let saved = tracker.state.history.first { finished(saved) }
                }
            } message: { Text("Completed sets and actual rest are saved. Unfinished sets stay marked incomplete.") }
            .alert("Discard this workout?", isPresented: $discardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) { tracker.change { $0.discard() } }
            }
            .alert("Workout notes", isPresented: $notesAlert) {
                TextField("Notes", text: $notes)
                Button("Cancel", role: .cancel) {}
                Button("Save") { tracker.change { $0.active?.notes = notes } }
            }
        }
    }

    private func live(_ session: StrengthSession) -> some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let reading = tracker.liveReading()
                VStack(spacing: 7) {
                    Text("HEART RATE").font(.caption).tracking(2).foregroundStyle(StrandPalette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(reading.bpm.map(String.init) ?? "—").font(.system(size: session.openRest == nil ? 56 : 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("bpm").foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text(reading.zone.map { $0 == 0 ? "Below Zone 1" : "Zone \($0) · \(["", "Very light", "Light", "Moderate", "Hard", "Maximum"][$0])" } ?? "Waiting for live heart rate")
                        .foregroundStyle(StrandPalette.accent)
                    HStack(spacing: 4) {
                        ForEach(0...5, id: \.self) { zone in
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 4).fill(zone == 0 ? Color.gray : StrandPalette.hrZones[zone])
                                    .frame(height: 16).overlay { if reading.zone == zone { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.white) } }
                                Text(zone == 0 ? "Below" : "Z\(zone)").font(.caption2)
                            }
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel(reading.zone.map { "Current heart rate zone \($0)" } ?? "Heart rate unavailable")
                    Text("\(strengthTime(Int(context.date.timeIntervalSince(session.startedAt)))) elapsed").font(.caption).monospacedDigit()
                }.frame(maxWidth: .infinity)
            }
            Divider()
            if let open = session.openRest {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(open.startedAt)))
                    let remaining = tracker.state.rest?.remaining(at: context.date) ?? 0
                    VStack(spacing: 8) {
                        Text(remaining > 0 ? "REST REMAINING" : "REST COMPLETE").font(.caption).tracking(2)
                        Text(remaining > 0 ? strengthTime(remaining) : "+\(strengthTime(max(0, elapsed - open.plannedSeconds)))")
                            .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(StrandPalette.accent)
                        HStack { StrengthStat(value: strengthTime(open.plannedSeconds), label: "Planned"); Spacer(); StrengthStat(value: strengthTime(elapsed), label: "Rested so far") }
                        Text(tracker.restStatus ?? (tracker.state.wristAlert ? "Wrist cue enabled" : "Wrist cue off")).font(.caption).foregroundStyle(StrandPalette.textSecondary)
                    }.padding(.vertical, 4)
                }
            }
            if let next = session.nextSet {
                if session.openRest == nil { StrengthExerciseArt(exercise: next.movement.exercise).frame(height: 80) }
                Text(next.movement.exercise.name).font(.title2.bold()).multilineTextAlignment(.center)
                Text(next.set.kind == .warmup ? "Warm-up set" : "Working set \((next.movement.ordinal(of: next.set.id) ?? 0) + 1)")
                    .foregroundStyle(StrandPalette.textSecondary)
                Button { edit = SetSelection(movement: next.movement, set: next.set) } label: {
                    HStack { StrengthStat(value: strengthWeight(next.set.kilograms, unit: session.unit), label: session.unit.rawValue); Spacer(); StrengthStat(value: "\(next.set.reps)", label: "reps"); Image(systemName: "pencil") }
                        .padding(16).background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityLabel("Edit next set weight and reps")
                if let previous = tracker.state.previousSet(for: next.movement.exercise, kind: next.set.kind, ordinal: session.ordinal(of: next.set.id) ?? 0) {
                    Text("Previous: \(strengthWeight(previous.kilograms, unit: session.unit)) \(session.unit.rawValue) × \(previous.reps)")
                        .font(.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            } else {
                Text(session.movements.isEmpty ? "Choose your first exercise" : "All sets completed").font(.title2.bold())
                Button("Add exercise") { picker = true }.buttonStyle(.bordered)
            }
            if let rest = session.actualRest { Text("Recorded rest: \(strengthTime(Int(rest)))").font(.caption).foregroundStyle(StrandPalette.textSecondary) }
        }
    }

    private func movementView(_ movement: StrengthMovement, session: StrengthSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StrengthExerciseArt(exercise: movement.exercise).frame(width: 66, height: 64)
                VStack(alignment: .leading) { Text(movement.exercise.name).font(.headline); Text(movement.exercise.equipment).font(.caption).foregroundStyle(StrandPalette.textSecondary) }
                Spacer()
                Menu {
                    Button("Add warm-up set") { addSet(movement, warmup: true) }
                    Button("Remove exercise", role: .destructive) { tracker.change { $0.active?.movements.removeAll { $0.id == movement.id } } }
                        .disabled(movement.sets.contains { $0.completedAt != nil || $0.startedAt != nil })
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Exercise actions")
            }
            HStack { Text("SET").frame(width: 30); Text("PREVIOUS").frame(maxWidth: .infinity); Text(session.unit.rawValue.uppercased()).frame(width: 58); Text("REPS").frame(width: 45); Text("✓").frame(width: 44) }
                .font(.caption2).foregroundStyle(StrandPalette.textSecondary)
            ForEach(movement.sets) { set in
                let number = (movement.ordinal(of: set.id) ?? 0) + 1
                let setLabel = set.kind == .warmup ? "warm-up set \(number)" : "working set \(number)"
                HStack(spacing: 4) {
                    Text(set.kind == .warmup ? "W" : "\(number)").frame(width: 30)
                    Text(tracker.state.previousSet(for: movement.exercise, kind: set.kind, ordinal: session.ordinal(of: set.id) ?? 0).map { "\(strengthWeight($0.kilograms, unit: session.unit)) × \($0.reps)" } ?? "—")
                        .font(.caption).foregroundStyle(StrandPalette.textSecondary).frame(maxWidth: .infinity)
                    Button { edit = SetSelection(movement: movement, set: set) } label: {
                        HStack { Text(strengthWeight(set.kilograms, unit: session.unit)).frame(width: 58); Text("\(set.reps)").frame(width: 45) }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Edit \(setLabel), \(set.reps) reps, \(strengthWeight(set.kilograms, unit: session.unit)) \(session.unit.rawValue)")
                    if set.completedAt != nil {
                        Menu {
                            Button("Undo completion") { tracker.change { $0.undoSet(movementID: movement.id, setID: set.id) } }
                            Button("Edit set") { edit = SetSelection(movement: movement, set: set) }
                        } label: { Image(systemName: "checkmark.square.fill").frame(width: 44, height: 44) }.accessibilityLabel("Completed set actions")
                    } else {
                        Button { tracker.change { $0.completeSet(movementID: movement.id, setID: set.id, now: Date()) } } label: {
                            Image(systemName: "square").frame(width: 44, height: 44)
                        }.accessibilityLabel("Complete \(setLabel)")
                    }
                }.font(.subheadline.monospacedDigit()).background(set.completedAt != nil ? StrandPalette.accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }
            Button { restMovement = movement } label: {
                HStack { Label("Rest between sets", systemImage: "timer"); Spacer(); Text(strengthTime(movement.restSeconds ?? tracker.state.restSeconds)); Image(systemName: "chevron.right") }.font(.subheadline).frame(minHeight: 44)
            }.buttonStyle(.plain)
            Button("Add set") { addSet(movement, warmup: false) }.frame(maxWidth: .infinity)
            Divider()
        }
    }

    private func bottom(_ session: StrengthSession) -> some View {
        VStack(spacing: 8) {
            if tab == "Exercises", let open = session.openRest {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = tracker.state.rest?.remaining(at: context.date) ?? 0
                    Text(remaining > 0 ? "Rest remaining  \(strengthTime(remaining))" : "Rested  \(strengthTime(Int(context.date.timeIntervalSince(open.startedAt))))")
                        .font(.headline.monospacedDigit())
                }
            }
            if tab == "Live", let next = session.nextSet {
                Button {
                    tracker.change {
                        if next.set.startedAt == nil { $0.startSet(movementID: next.movement.id, setID: next.set.id, now: Date()) }
                        else { $0.completeSet(movementID: next.movement.id, setID: next.set.id, now: Date()) }
                    }
                } label: { Label(next.set.startedAt != nil ? "Complete set" : (session.openRest != nil ? "Start next set" : (next.set.kind == .warmup ? "Start warm-up set" : "Start exercise")), systemImage: next.set.startedAt != nil ? "checkmark" : "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 40) }
                    .buttonStyle(.borderedProminent)
            }
            Button { tracker.presented = false } label: { Label("Minimize workout", systemImage: "chevron.down").frame(maxWidth: .infinity, minHeight: 36) }.buttonStyle(.plain)
        }.padding(.horizontal, 20).padding(.vertical, 10).background(StrandPalette.surfaceBase)
    }

    private func addSet(_ movement: StrengthMovement, warmup: Bool) {
        tracker.change { state in
            guard let index = state.active?.movements.firstIndex(where: { $0.id == movement.id }) else { return }
            var set = movement.sets.last?.fresh() ?? StrengthSet(); set.kind = warmup ? .warmup : .working
            if warmup { state.active?.movements[index].sets.insert(set, at: 0) } else { state.active?.movements[index].sets.append(set) }
        }
    }

    private func restEditor(_ movement: StrengthMovement) -> some View {
        NavigationStack {
            Form {
                Stepper("Rest: \(strengthTime(tracker.state.active?.movements.first(where: { $0.id == movement.id })?.restSeconds ?? tracker.state.restSeconds))", value: Binding(
                    get: { tracker.state.active?.movements.first(where: { $0.id == movement.id })?.restSeconds ?? tracker.state.restSeconds },
                    set: { seconds in tracker.change { state in if let m = state.active?.movements.firstIndex(where: { $0.id == movement.id }) { state.active?.movements[m].restSeconds = seconds } } }
                ), in: 0...1800, step: 15)
                Text("Applies to future sets of this exercise. The running countdown and its recorded target stay unchanged. Zero disables the countdown; actual rest is still recorded.").font(.caption)
            }.navigationTitle("Rest between sets").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { restMovement = nil } } }
        }
    }
}

struct StrengthStat: View {
    let value: String
    let label: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(StrandPalette.textSecondary) } }
}
