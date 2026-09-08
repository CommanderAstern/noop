import SwiftUI
import StrandDesign
import StrengthTracking
import StrandAnalytics
import WhoopProtocol

struct StrengthWorkoutEntryView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @State private var presented = false

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Strength training").font(StrandFont.title2)
                if let active = tracker.state.active {
                    Text("\(active.name) · \(active.completedSets) sets logged")
                        .font(StrandFont.bodyNumber)
                } else {
                    Text("Exercises, machines, routines and your lifting history.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                }
                NoopButton(tracker.state.active == nil ? "Open strength tracker" : "Resume strength workout",
                           systemImage: "dumbbell.fill", kind: .primary, fullWidth: true) { presented = true }
            }
        }
        .sheet(isPresented: $presented) {
            NavigationStack {
                StrengthWorkoutsView(tracker: tracker)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = false } } }
            }
            #if os(iOS)
            .noopSheetPresentation(largeFirst: true)
            #else
            .frame(minWidth: 540, minHeight: 700)
            #endif
        }
    }
}

struct StrengthWorkoutsView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @State private var showExercises = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var routineName = ""
    @State private var showRoutineName = false
    @State private var savedRoutine = false
    @State private var deletingRoutine: StrengthRoutine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                if let error = tracker.error {
                    Text(error).font(StrandFont.body).foregroundStyle(StrandPalette.statusCritical)
                }
                if let session = tracker.state.active {
                    sessionHeader(session)
                    restCard
                    ForEach(session.movements) { movement in
                        movementCard(movement, unit: session.unit)
                    }
                    NoopButton("Add exercise or machine", systemImage: "plus", kind: .secondary, fullWidth: true) {
                        showExercises = true
                    }
                    NoopCard { StrengthMetricsView(session: session, tracker: tracker) }
                    NoopButton("Save as routine", systemImage: "bookmark", kind: .secondary, fullWidth: true) {
                        routineName = session.name; showRoutineName = true
                    }.disabled(session.movements.isEmpty)
                    if savedRoutine { Text("Routine saved. Find it below after finishing this workout.").font(StrandFont.caption) }
                    NoopButton("Finish workout", systemImage: "checkmark", kind: .primary, fullWidth: true) {
                        confirmFinish = true
                    }.disabled(session.completedSets == 0)
                    Button("Discard workout", role: .destructive) { confirmDiscard = true }
                } else {
                    NoopButton("Start strength workout", systemImage: "play.fill", kind: .primary, fullWidth: true) {
                        tracker.change { $0.start(now: Date()) }; savedRoutine = false
                    }
                    routinesCard
                    historyCard
                }
                settingsCard
                Text("A lifting log: no muscular-strain calculation. Strength data is separate from the heart-rate activity log and is not included in database backups. App updates keep it; deleting the app removes it.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            .screenPadding().padding(.vertical, NoopMetrics.space4)
        }
        .background(StrandPalette.surfaceBase)
        .foregroundStyle(StrandPalette.textPrimary)
        .tint(StrandPalette.accent)
        .navigationTitle("Strength")
        .sheet(isPresented: $showExercises) { StrengthExercisePicker(tracker: tracker) }
        .alert("Finish this workout?", isPresented: $confirmFinish) {
            Button("Keep training", role: .cancel) {}
            Button("Finish and save") { tracker.change { $0.finish(now: Date()) } }
        } message: { Text("Your completed sets will be saved to strength history. Unfinished sets remain marked as not completed. The rest alert will be cancelled.") }
        .alert("Discard this workout?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { tracker.change { $0.discard() } }
        } message: { Text("This removes the active workout and cancels its rest alert. Saved routines and history are kept.") }
        .alert("Save routine", isPresented: $showRoutineName) {
            TextField("Routine name", text: $routineName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let session = tracker.state.active else { return }
                savedRoutine = tracker.change {
                    $0.routines.append(StrengthRoutine(name: name, movements: session.movements,
                                                       restSeconds: $0.restSeconds, unit: session.unit))
                }
            }
        } message: { Text("Copies the exercise order, set targets, weights, unit and rest duration. Completion marks are reset when reused.") }
        .alert("Delete this routine?", isPresented: Binding(get: { deletingRoutine != nil }, set: { if !$0 { deletingRoutine = nil } })) {
            Button("Cancel", role: .cancel) { deletingRoutine = nil }
            Button("Delete", role: .destructive) {
                if let routine = deletingRoutine { tracker.change { $0.routines.removeAll { $0.id == routine.id } } }
                deletingRoutine = nil
            }
        }
    }

    private func sessionHeader(_ session: StrengthSession) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                TextField("Workout name", text: Binding(get: { tracker.state.active?.name ?? "" },
                    set: { name in tracker.change { $0.active?.name = name } }))
                    .font(StrandFont.title2).textFieldStyle(.roundedBorder)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(session.completedSets) sets logged · \(duration(Int(context.date.timeIntervalSince(session.startedAt)))) elapsed")
                        .font(StrandFont.bodyNumber)
                }
                Picker("Weight unit", selection: Binding(get: { session.unit }, set: { unit in
                    tracker.change { $0.active?.unit = unit; $0.unit = unit }
                })) {
                    ForEach(LiftingUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("Valid changes save as you type. Use 0 for no external load. Close this screen to resume later.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private var restCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                if let rest = tracker.state.rest {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(rest.consumed ? "Rest complete" : "Rest · \(duration(rest.remaining(at: context.date)))")
                            .font(StrandFont.title1).monospacedDigit()
                    }
                    if !rest.consumed {
                        Button("Skip rest") { tracker.change { $0.rest = nil } }.buttonStyle(.bordered)
                    }
                    if let status = tracker.restStatus { Text(status).font(StrandFont.caption) }
                } else {
                    Text("Complete a set to start rest").font(StrandFont.headline)
                }
                Stepper("Rest after each set: \(tracker.state.restSeconds)s", value: Binding(
                    get: { tracker.state.restSeconds }, set: { seconds in tracker.change { $0.restSeconds = seconds; $0.active?.restSeconds = seconds } }
                ), in: 0...1800, step: 15).font(StrandFont.bodyNumber)
                Text("0 turns auto-rest off. Changes apply to the next set.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func movementCard(_ movement: StrengthMovement, unit: LiftingUnit) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text(movement.exercise.name).font(StrandFont.title2)
                Text(movement.exercise.equipment).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                ForEach(Array(movement.sets.enumerated()), id: \.element.id) { index, set in
                    StrengthSetRow(tracker: tracker, movementID: movement.id, set: set, number: index + 1, unit: unit)
                        .id("\(set.id)-\(unit.rawValue)")
                    Divider()
                }
                Button("Add set") {
                    tracker.change { state in
                        guard let index = state.active?.movements.firstIndex(where: { $0.id == movement.id }) else { return }
                        state.active?.movements[index].sets.append(movement.sets.last?.fresh() ?? StrengthSet())
                    }
                }.buttonStyle(.bordered)
                if movement.sets.allSatisfy({ $0.completedAt == nil }) {
                    Button("Remove exercise", role: .destructive) {
                        tracker.change { $0.active?.movements.removeAll { $0.id == movement.id } }
                    }.font(StrandFont.caption)
                }
            }
        }
    }

    private var settingsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Rest alerts").font(StrandFont.headline)
                Toggle("WHOOP wrist cue", isOn: Binding(get: { tracker.state.wristAlert }, set: { enabled in
                    tracker.change { $0.wristAlert = enabled }
                }))
                Text("Also enable Wrist alerts in Automations. Attempts one cue while WHOOP is connected, including with the screen off while Bluetooth keeps the workout running. No catch-up buzz after reopening or reconnecting.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Toggle("Phone notification", isOn: Binding(get: { tracker.state.phoneAlert }, set: tracker.setPhoneAlert))
                Text(tracker.notificationStatus).font(StrandFont.caption)
                Text("Screen-off wrist cues are best effort: iOS can pause or close the app. Enable phone notifications as a fallback. Keep NOOP Lab running; do not force-close it.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.font(StrandFont.body)
    }

    private var routinesCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Routines").font(StrandFont.title2)
                if tracker.state.routines.isEmpty {
                    Text("Start a workout, add your exercises and set targets, then save it as a routine before or after logging sets.")
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(tracker.state.routines) { routine in
                    HStack {
                        Button {
                            tracker.change { $0.start(routine: routine, now: Date()) }; savedRoutine = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(routine.name).font(StrandFont.headline)
                                Text("\(routine.movements.count) exercises · \(routine.restSeconds)s rest")
                                    .font(StrandFont.captionNumber)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                        }.buttonStyle(.plain)
                        Button { deletingRoutine = routine } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Delete \(routine.name)")
                    }
                    Divider()
                }
            }
        }
    }

    private var historyCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Strength history").font(StrandFont.title2)
                if tracker.state.history.isEmpty { Text("Your finished strength workouts appear here.").font(StrandFont.body) }
                ForEach(tracker.state.history) { session in
                    NavigationLink {
                        StrengthHistoryView(session: session, tracker: tracker)
                    } label: {
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(session.name).font(StrandFont.headline)
                            Text(session.startedAt, format: .dateTime.month().day().hour().minute()).font(StrandFont.caption)
                            Text("\(session.completedSets) sets completed").font(StrandFont.captionNumber)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct StrengthSetRow: View {
    @ObservedObject var tracker: StrengthWorkoutController
    let movementID: UUID
    let set: StrengthSet
    let number: Int
    let unit: LiftingUnit
    @State private var reps: String
    @State private var weight: String
    @State private var weightWasEdited = false

    init(tracker: StrengthWorkoutController, movementID: UUID, set: StrengthSet, number: Int, unit: LiftingUnit) {
        self.tracker = tracker; self.movementID = movementID; self.set = set; self.number = number; self.unit = unit
        _reps = State(initialValue: String(set.reps))
        _weight = State(initialValue: unit.display(set.kilograms).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
    }
    private var parsedReps: Int? { Int(reps).flatMap { (1...999).contains($0) ? $0 : nil } }
    private var parsedWeight: Double? {
        guard let value = try? Double(weight, format: .number), value.isFinite,
              (0...10_000).contains(unit.kilograms(value)) else { return nil }
        return unit.kilograms(value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Set \(number)").font(StrandFont.headline)
            if set.completedAt != nil {
                Text("\(set.reps) reps × \(unit.display(set.kilograms).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) · Done")
                    .font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.statusPositive)
                Button("Undo completion") { tracker.change { $0.undoSet(movementID: movementID, setID: set.id) } }
                    .font(StrandFont.caption)
            } else {
                HStack(spacing: NoopMetrics.space3) {
                    VStack(alignment: .leading) {
                        Text("Reps").font(StrandFont.caption)
                        TextField("Reps", text: $reps).textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                    }
                    VStack(alignment: .leading) {
                        Text("Weight (\(unit.rawValue))").font(StrandFont.caption)
                        TextField("Weight", text: $weight).textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    }
                }.font(StrandFont.bodyNumber)
                if parsedReps == nil || parsedWeight == nil {
                    Text("Enter 1–999 reps and a nonnegative weight. Invalid text is not saved.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.statusWarning)
                }
                HStack {
                    Button("Complete set") {
                        guard let reps = parsedReps, let enteredKilograms = parsedWeight else { return }
                        // Merely displaying a rounded unit conversion must not rewrite the load.
                        let kilograms = weightWasEdited ? enteredKilograms : set.kilograms
                        tracker.change { $0.recordSet(movementID: movementID, setID: set.id,
                            reps: reps, kilograms: kilograms, now: Date()) }
                    }
                        .buttonStyle(.borderedProminent).disabled(parsedReps == nil || parsedWeight == nil)
                    Spacer()
                    Button { tracker.change { state in
                        guard let m = state.active?.movements.firstIndex(where: { $0.id == movementID }) else { return }
                        state.active?.movements[m].sets.removeAll { $0.id == set.id }
                    } } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove set \(number)")
                }
            }
        }
        .onChange(of: reps) { _ in if let value = parsedReps { edit { $0.reps = value } } }
        .onChange(of: weight) { _ in
            weightWasEdited = true
            if let value = parsedWeight { edit { $0.kilograms = value } }
        }
    }
    private func edit(_ update: (inout StrengthSet) -> Void) {
        tracker.change { state in
            guard let m = state.active?.movements.firstIndex(where: { $0.id == movementID }),
                  let s = state.active?.movements[m].sets.firstIndex(where: { $0.id == set.id }) else { return }
            update(&state.active!.movements[m].sets[s])
        }
    }
}

private struct StrengthExercisePicker: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var name = ""
    @State private var equipment = ""
    private var exercises: [StrengthExercise] {
        (tracker.state.customExercises + StrengthExercise.catalog).filter {
            search.isEmpty || "\($0.name) \($0.equipment)".localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Custom exercise or machine") {
                    TextField("Exercise name", text: $name)
                    TextField("Equipment / machine label", text: $equipment)
                    Button("Create and add") {
                        let exercise = StrengthExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            equipment: equipment.trimmingCharacters(in: .whitespacesAndNewlines))
                        if tracker.change({ $0.customExercises.append(exercise); $0.active?.movements.append(StrengthMovement(exercise: exercise)) }) {
                            dismiss()
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Exercises and gym machines") {
                    ForEach(exercises) { exercise in
                        Button {
                            if tracker.change({ $0.active?.movements.append(StrengthMovement(exercise: exercise)) }) { dismiss() }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(exercise.name).font(StrandFont.headline)
                                Text(exercise.equipment).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Exercise or equipment")
            .navigationTitle("Add exercise")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .tint(StrandPalette.accent)
        }
    }
}

private struct StrengthHistoryView: View {
    let session: StrengthSession
    @ObservedObject var tracker: StrengthWorkoutController
    @State private var saved = false
    var body: some View {
        List {
            Section {
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                Text("\(session.completedSets) sets completed")
                Button(saved ? "Routine saved" : "Save as routine") {
                    saved = tracker.change {
                        $0.routines.append(StrengthRoutine(name: session.name, movements: session.movements,
                            restSeconds: session.restSeconds, unit: session.unit))
                    }
                }.disabled(saved)
            }
            Section { StrengthMetricsView(session: session, tracker: tracker) }
            ForEach(session.movements) { movement in
                Section("\(movement.exercise.name) · \(movement.exercise.equipment)") {
                    ForEach(Array(movement.sets.enumerated()), id: \.element.id) { index, set in
                        VStack(alignment: .leading) {
                            Text("Set \(index + 1) · \(set.reps) reps × \(session.unit.display(set.kilograms).formatted(.number.precision(.fractionLength(0...2)))) \(session.unit.rawValue)")
                                .font(StrandFont.bodyNumber)
                            Text(set.completedAt == nil ? "Not completed" : "Completed").font(StrandFont.caption)
                        }
                    }
                }
            }
        }.navigationTitle(session.name).tint(StrandPalette.accent)
    }
}

#if DEBUG
struct StrengthDemoView: View {
    let mode: String
    @StateObject private var tracker: StrengthWorkoutController

    init(mode: String) {
        self.mode = mode
        let store = StrengthFileStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("strength-demo/" + UUID().uuidString + ".json"))
        var state = StrengthState()
        let now = Date()
        state.start(now: now.addingTimeInterval(-720))
        state.active!.name = "Upper body A"
        state.active!.movements = [
            StrengthMovement(exercise: StrengthExercise.catalog[1], sets: [
                StrengthSet(reps: 8, kilograms: 60), StrengthSet(reps: 8, kilograms: 60), StrengthSet(reps: 8, kilograms: 60)]),
            StrengthMovement(exercise: StrengthExercise.catalog[15], sets: [StrengthSet(reps: 10, kilograms: 45)]),
        ]
        let movement = state.active!.movements[0]
        state.completeSet(movementID: movement.id, setID: movement.sets[0].id, now: now.addingTimeInterval(-15))
        state.routines = [StrengthRoutine(name: "Upper body A", movements: state.active!.movements, restSeconds: 90, unit: .kg)]
        if mode == "home" || mode == "history" { state.finish(now: now) }
        try? store.save(state)
        let demoTracker = StrengthWorkoutController(storage: store, platformServices: false)
        demoTracker.loadMetrics = { session in
            let samples = (0...720).map { second in
                HRSample(ts: Int(session.startedAt.timeIntervalSince1970) + second,
                         bpm: 115 + Int(25 * sin(Double(second) / 35)))
            }
            return .calculate(session: session, samples: samples, now: now,
                              maxHR: 190, restingHR: 60, sex: "male", method: .edwards)
        }
        _tracker = StateObject(wrappedValue: demoTracker)
    }

    var body: some View {
        Group {
            if mode == "picker" { StrengthExercisePicker(tracker: tracker) }
            else if mode == "history", let session = tracker.state.history.first {
                StrengthHistoryView(session: session, tracker: tracker)
            } else { StrengthWorkoutsView(tracker: tracker) }
        }
    }
}
#endif
