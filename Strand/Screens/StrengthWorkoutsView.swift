import SwiftUI
import StrandDesign
import StrengthTracking

struct StrengthWorkoutEntryView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Strength training").font(StrandFont.title2)
                Text(tracker.state.active.map { "\($0.name) · \($0.completedSets) sets logged" }
                     ?? "Your training days, lifts and progress.").foregroundStyle(StrandPalette.textSecondary)
                Button(tracker.state.active == nil ? "Open workouts" : "Resume workout") { tracker.presented = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        #if os(macOS)
        .modifier(StrengthPresentation(tracker: tracker))
        #endif
    }
}

/// App-root presentation makes minimize/deep-link work from every tab, not just Workouts.
struct StrengthPresentation: ViewModifier {
    @ObservedObject var tracker: StrengthWorkoutController
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let session = tracker.state.active, !tracker.presented {
                Button { tracker.presented = true } label: {
                    HStack {
                        Image(systemName: "dumbbell.fill")
                        VStack(alignment: .leading) {
                            Text(session.name).font(.headline)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(tracker.state.rest.map { $0.remaining(at: context.date) > 0 ? "Rest \(strengthTime($0.remaining(at: context.date)))" : "Rest complete" } ?? "Workout in progress")
                                    .font(.caption).monospacedDigit()
                            }
                        }
                        Spacer(); Image(systemName: "chevron.up")
                    }.padding(12).background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).padding(.horizontal).tint(StrandPalette.accent)
            }
        }.sheet(isPresented: $tracker.presented) {
            NavigationStack { StrengthWorkoutsView(tracker: tracker) }
                #if os(macOS)
                .frame(minWidth: 580, minHeight: 760)
                #endif
        }
    }
}

struct StrengthWorkoutsView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @State var section = "Train"
    @State private var summary: StrengthSession?
    @State private var editingRoutine: StrengthRoutine?
    @State private var settings = false
    @State private var browse = false
    @State private var viewingSession = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if tracker.state.active != nil && viewingSession {
                StrengthSessionView(tracker: tracker, finished: { summary = $0 }, browse: { viewingSession = false })
            } else {
                VStack(spacing: 16) {
                    Picker("Workouts section", selection: $section) {
                        ForEach(["Train", "Progress", "History"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal)
                    if section == "Progress" { StrengthProgressView(tracker: tracker) }
                    else if section == "History" { StrengthHistoryList(tracker: tracker) }
                    else { train }
                }.navigationTitle("Workouts")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { tracker.presented = false } }
                        ToolbarItem { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Workout settings") }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
            }
        }
        .background(StrandPalette.surfaceBase).foregroundStyle(StrandPalette.textPrimary).tint(StrandPalette.accent)
        .safeAreaInset(edge: .top) { if let error = tracker.error { Text(error).font(.caption).foregroundStyle(StrandPalette.statusCritical).padding() } }
        .sheet(item: $summary) { session in NavigationStack { StrengthSummaryView(session: session, tracker: tracker) } }
        .sheet(item: $editingRoutine) { routine in StrengthRoutineEditor(routine: routine, tracker: tracker) }
        .sheet(isPresented: $settings) { StrengthSettingsView(tracker: tracker) }
        .sheet(isPresented: $browse) { StrengthExercisePicker(tracker: tracker, libraryOnly: true) }
    }

    private var train: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let active = tracker.state.active {
                    Button { viewingSession = true } label: { Label("Resume \(active.name)", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                HStack {
                    Text("Your training days").font(.title2.bold()); Spacer()
                    Button { editingRoutine = StrengthRoutine(name: "New training day", movements: [], restSeconds: 90, unit: tracker.state.unit) } label: { Label("New", systemImage: "plus") }
                }
                if tracker.state.routines.isEmpty {
                    Text("Choose a starting template and make it yours. Set your own weights before training.")
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(tracker.state.routines) { routine in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(routine.name).font(.title3.bold()); Spacer()
                            Menu {
                                Button("Edit template") { editingRoutine = routine }
                                Button("Duplicate") { var copy = routine; copy.id = UUID(); copy.name += " copy"; editingRoutine = copy }
                                Button("Delete template", role: .destructive) { tracker.change { $0.routines.removeAll { $0.id == routine.id } } }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Template actions")
                        }
                        Text("\(routine.movements.count) exercises · \(routine.movements.flatMap(\.sets).filter { $0.kind == .working }.count) working sets")
                            .font(.subheadline).foregroundStyle(StrandPalette.textSecondary)
                        HStack { ForEach(Array(routine.movements.prefix(3))) { movement in StrengthExerciseArt(exercise: movement.exercise).frame(width: 80, height: 70) } }
                        Button { tracker.change { $0.start(routine: routine, now: Date()) }; viewingSession = true } label: { Label("Start \(routine.name)", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).disabled(tracker.state.active != nil)
                    }.padding(16).background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                }
                Text("Starting templates").font(.headline)
                ForEach(StrengthRoutine.starterDays) { routine in
                    Button {
                        editingRoutine = StrengthRoutine(name: routine.name, movements: routine.movements,
                            restSeconds: routine.restSeconds, unit: routine.unit)
                    } label: {
                        HStack { StrengthExerciseArt(exercise: routine.movements[0].exercise).frame(width: 64, height: 52)
                            VStack(alignment: .leading) { Text(routine.name).font(.headline); Text("\(routine.movements.count) exercises · Warm-up included").font(.caption) }
                            Spacer(); Image(systemName: "chevron.right")
                        }
                    }.buttonStyle(.plain)
                    Divider()
                }
                Button { tracker.change { $0.start(now: Date()) }; viewingSession = true } label: { Label("Start empty workout", systemImage: "plus") }
                    .buttonStyle(.bordered).disabled(tracker.state.active != nil)
                Button("Browse exercise library") { browse = true }
                Text("Strength history stays on this device. It is separate from database backups. No proprietary muscular-strain score.")
                    .font(.caption).foregroundStyle(StrandPalette.textSecondary)
            }.padding(20)
        }
    }
}

struct StrengthSettingsView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Rest alerts") {
                    Toggle("WHOOP wrist cue", isOn: Binding(get: { tracker.state.wristAlert }, set: { enabled in tracker.change { $0.wristAlert = enabled } }))
                    Text("Also enable Wrist alerts in Automations. Screen-off cues are best effort while Bluetooth keeps NOOP running; missed cues never replay.").font(.caption)
                    Toggle("Phone notification fallback", isOn: Binding(get: { tracker.state.phoneAlert }, set: tracker.setPhoneAlert))
                    Text(tracker.notificationStatus).font(.caption)
                }
                Section("Units") {
                    Picker("Weight", selection: Binding(get: { tracker.state.active?.unit ?? tracker.state.unit }, set: { unit in tracker.change { $0.unit = unit; $0.active?.unit = unit } })) {
                        ForEach(LiftingUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text("Enter the load you record for this exercise consistently. NOOP does not automatically double dumbbells or add body weight.").font(.caption)
                }
            }.navigationTitle("Workout settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

func strengthTime(_ seconds: Int) -> String { let value = max(0, seconds); return String(format: "%d:%02d", value / 60, value % 60) }
func strengthWeight(_ kilograms: Double, unit: LiftingUnit) -> String { unit.display(kilograms).formatted(.number.precision(.fractionLength(0...2))) }
