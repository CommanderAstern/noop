import SwiftUI
import StrengthTracking
import StrandDesign

struct StrengthRoutineEditor: View {
    @State var routine: StrengthRoutine
    @ObservedObject var tracker: StrengthWorkoutController
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var selection: StrengthSessionView.SetSelection?
    var body: some View {
        NavigationStack {
            List {
                Section("Training day") {
                    TextField("Name", text: $routine.name)
                    Picker("Unit", selection: $routine.unit) { ForEach(LiftingUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Text("Your own targets; zero is no external load. Edit weights before training.").font(.caption)
                }
                ForEach($routine.movements) { $movement in
                    Section {
                        ForEach(Array(movement.sets.enumerated()), id: \.element.id) { index, set in
                            Button {
                                selection = StrengthSessionView.SetSelection(movement: movement, set: set)
                            } label: {
                                HStack { Text(set.kind == .warmup ? "Warm-up" : "Set \(index + 1)"); Spacer(); Text("\(strengthWeight(set.kilograms, unit: routine.unit)) \(routine.unit.rawValue) × \(set.reps)"); Image(systemName: "pencil") }
                            }.buttonStyle(.plain)
                        }.onDelete { movement.sets.remove(atOffsets: $0) }
                        HStack {
                            Button("Add set") { movement.sets.append(movement.sets.last?.fresh() ?? StrengthSet()) }
                            Spacer()
                            Button("Add warm-up") { var set = StrengthSet(reps: 12); set.kind = .warmup; movement.sets.insert(set, at: 0) }
                        }
                        Stepper("Rest: \(strengthTime(movement.restSeconds ?? routine.restSeconds))", value: Binding(get: { movement.restSeconds ?? routine.restSeconds }, set: { movement.restSeconds = $0 }), in: 0...1800, step: 15)
                    } header: {
                        HStack { Text("\(movement.exercise.name) · \(movement.exercise.equipment)"); Spacer()
                            Button { routine.movements.removeAll { $0.id == movement.id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove exercise")
                        }
                    }
                }.onMove { routine.movements.move(fromOffsets: $0, toOffset: $1) }
                Button("Add exercises") { adding = true }
            }
            .navigationTitle("Edit training day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                #if os(iOS)
                ToolbarItem { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if tracker.change({ state in
                        if let i = state.routines.firstIndex(where: { $0.id == routine.id }) { state.routines[i] = routine }
                        else { state.routines.append(routine) }
                    }) { dismiss() }
                }.disabled(routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.movements.isEmpty || routine.movements.contains { $0.sets.isEmpty }) }
            }
            .sheet(isPresented: $adding) {
                StrengthExercisePicker(tracker: tracker, selectedExercises: { exercises in
                    routine.movements.append(contentsOf: exercises.map { exercise in
                        let set = tracker.state.previousSet(for: exercise)?.fresh() ?? StrengthSet()
                        return StrengthMovement(exercise: exercise, sets: [set, set.fresh(), set.fresh()])
                    })
                })
            }
            .sheet(item: $selection) { item in
                StrengthSetEditor(set: item.set, unit: routine.unit) { set in
                    guard let m = routine.movements.firstIndex(where: { $0.id == item.movement.id }),
                          let s = routine.movements[m].sets.firstIndex(where: { $0.id == set.id }) else { return false }
                    routine.movements[m].sets[s] = set; return true
                }
            }
            .tint(StrandPalette.accent)
        }
    }
}
