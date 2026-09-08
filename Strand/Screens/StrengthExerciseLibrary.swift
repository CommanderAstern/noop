import SwiftUI
import StrengthTracking
import StrandDesign
#if os(iOS)
import PhotosUI
#endif

/// Original schematic equipment drawings. Custom photos are optional; no third-party art is fetched.
struct StrengthExerciseArt: View {
    let exercise: StrengthExercise
    var body: some View {
        Group {
            #if os(iOS)
            if let data = exercise.photo, let photo = UIImage(data: data) { Image(uiImage: photo).resizable().scaledToFit() }
            else { drawing }
            #else
            if let data = exercise.photo, let photo = NSImage(data: data) { Image(nsImage: photo).resizable().scaledToFit() }
            else { drawing }
            #endif
        }.accessibilityHidden(true)
    }
    private var drawing: some View {
        Canvas { context, size in
            let scale = min(size.width / 120, size.height / 100)
            context.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let equipment = exercise.equipment.lowercased()
            func line(_ points: [CGPoint], width: CGFloat = 5, accent: Bool = false) {
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(accent ? StrandPalette.accent : StrandPalette.textSecondary), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func bar(_ x: CGFloat, _ y: CGFloat) {
                line([CGPoint(x: x - 24, y: y), CGPoint(x: x + 24, y: y)], width: 4)
                for offset in [-18.0, 18.0] { line([CGPoint(x: x + offset, y: y - 10), CGPoint(x: x + offset, y: y + 10)], width: 8, accent: true) }
            }
            if equipment.contains("machine") || equipment.contains("cable") {
                line([.init(x: 12, y: 88), .init(x: 108, y: 88)], width: 3)
                line([.init(x: 92, y: 88), .init(x: 92, y: 12), .init(x: 35, y: 12)])
                line([.init(x: 38, y: 18), .init(x: 38, y: 42)], width: 2)
                line([.init(x: 23, y: 42), .init(x: 53, y: 42)], accent: true)
                line([.init(x: 26, y: 69), .init(x: 66, y: 69), .init(x: 66, y: 46)], width: 8)
                line([.init(x: 35, y: 74), .init(x: 35, y: 88)])
                for y in stride(from: 50, through: 78, by: 7) { line([.init(x: 80, y: y), .init(x: 102, y: y)], width: 4) }
            } else if equipment.contains("barbell") || equipment.contains("smith") {
                bar(60, 27)
                line([.init(x: 18, y: 31), .init(x: 18, y: 85)])
                line([.init(x: 28, y: 64), .init(x: 92, y: 64)], width: 9)
                line([.init(x: 38, y: 68), .init(x: 34, y: 89)])
                line([.init(x: 85, y: 68), .init(x: 94, y: 89)])
            } else if equipment.contains("bodyweight") {
                let head = Path(ellipseIn: CGRect(x: 51, y: 9, width: 18, height: 18))
                context.fill(head, with: .color(StrandPalette.textSecondary))
                line([.init(x: 60, y: 31), .init(x: 60, y: 58)])
                line([.init(x: 34, y: 38), .init(x: 60, y: 35), .init(x: 86, y: 38)], accent: true)
                line([.init(x: 37, y: 85), .init(x: 60, y: 58), .init(x: 83, y: 85)])
            } else { bar(43, 36); bar(77, 69) }
        }
    }
}

struct StrengthExercisePicker: View {
    @ObservedObject var tracker: StrengthWorkoutController
    var libraryOnly = false
    var selectedExercises: (([StrengthExercise]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var equipment = "All"
    @State private var selected: Set<UUID> = []
    @State private var custom = false
    private var catalog: [StrengthExercise] { tracker.state.customExercises + StrengthExercise.catalog }
    private var filtered: [StrengthExercise] { catalog.filter {
        (equipment == "All" || $0.equipment == equipment) && (search.isEmpty || "\($0.name) \($0.equipment)".localizedCaseInsensitiveContains(search))
    } }
    var body: some View {
        NavigationStack {
            List {
                Picker("Equipment", selection: $equipment) {
                    Text("All equipment").tag("All")
                    ForEach(Array(Set(catalog.map(\.equipment))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Button { custom = true } label: { Label("Create custom exercise", systemImage: "plus") }
                ForEach(filtered) { exercise in
                    Button {
                        if selected.contains(exercise.id) { selected.remove(exercise.id) } else { selected.insert(exercise.id) }
                    } label: {
                        HStack {
                            StrengthExerciseArt(exercise: exercise).frame(width: 64, height: 60)
                            VStack(alignment: .leading, spacing: 5) { Text(exercise.name).font(.headline); Text(exercise.equipment).font(.caption).foregroundStyle(StrandPalette.textSecondary) }
                            Spacer()
                            if !libraryOnly { Image(systemName: selected.contains(exercise.id) ? "checkmark.circle.fill" : "circle") }
                        }
                    }.buttonStyle(.plain).disabled(libraryOnly)
                }
            }.searchable(text: $search, prompt: "Search exercises or machines")
                .navigationTitle(libraryOnly ? "Exercise library" : "Add exercises")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    if !libraryOnly {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add \(selected.count)") {
                                let entries = catalog.filter { selected.contains($0.id) }
                                if let selectedExercises { selectedExercises(entries); dismiss() }
                                else if tracker.change({ state in for entry in entries { state.addExercise(entry) } }) { dismiss() }
                            }.disabled(selected.isEmpty)
                        }
                    }
                }
                .sheet(isPresented: $custom) { StrengthCustomExerciseView(tracker: tracker) { selected.insert($0.id) } }
                .tint(StrandPalette.accent)
        }
    }
}

struct StrengthCustomExerciseView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    var saved: (StrengthExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var equipment = ""
    @State private var photo: Data?
    #if os(iOS)
    @State private var selection: PhotosPickerItem?
    #endif
    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                TextField("Equipment / gym machine name", text: $equipment)
                #if os(iOS)
                PhotosPicker(photo == nil ? "Add your machine photo" : "Change photo", selection: $selection, matching: .images)
                    .onChange(of: selection) { item in
                        Task {
                            guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                            let scale = min(1, 512 / max(image.size.width, image.size.height))
                            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                            let result = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.7)
                            if let result, result.count <= 1_000_000 { photo = result }
                        }
                    }
                #endif
                if photo != nil { Text("Photo ready · saved on this device").font(.caption) }
                Text("Give different gym machines distinct names so their weights and records remain comparable.").font(.caption)
            }.navigationTitle("Custom exercise").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    var entry = StrengthExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines), equipment: equipment.trimmingCharacters(in: .whitespacesAndNewlines)); entry.photo = photo
                    if tracker.change({ $0.customExercises.append(entry) }) { saved(entry); dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

struct StrengthSetEditor: View {
    let set: StrengthSet
    let unit: LiftingUnit
    var save: (StrengthSet) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reps: String
    @State private var weight: String
    @State private var kind: StrengthSetKind
    private let initialWeight: String
    init(set: StrengthSet, unit: LiftingUnit, save: @escaping (StrengthSet) -> Bool) {
        self.set = set; self.unit = unit; self.save = save
        let text = unit.display(set.kilograms).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        initialWeight = text; _weight = State(initialValue: text); _reps = State(initialValue: String(set.reps)); _kind = State(initialValue: set.kind)
    }
    private var parsed: StrengthSet? {
        guard let reps = Int(reps), let entered = try? Double(weight, format: .number) else { return nil }
        var updated = set; updated.reps = reps; updated.kilograms = weight == initialWeight ? set.kilograms : unit.kilograms(entered); updated.kind = kind
        return updated.isValid ? updated : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Set type", selection: $kind) { Text("Warm-up").tag(StrengthSetKind.warmup); Text("Working").tag(StrengthSetKind.working) }
                TextField("Weight (\(unit.rawValue))", text: $weight)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("Reps", text: $reps)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("Log external weight consistently; use zero for no added load. Valid range: 1–999 reps and 0–10,000 kg.").font(.caption)
            }.navigationTitle("Edit set").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if let parsed, save(parsed) { dismiss() } }.disabled(parsed == nil) }
            }
        }
    }
}
