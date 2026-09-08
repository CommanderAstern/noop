import SwiftUI
import StrengthTracking
import StrandDesign
#if os(iOS)
import PhotosUI
#endif

/// Original generated equipment renders; optional custom photos remain local to the workout file.
struct StrengthExerciseArt: View {
    let exercise: StrengthExercise
    var body: some View {
        Group {
            #if os(iOS)
            if let data = exercise.photo, let photo = UIImage(data: data) { Image(uiImage: photo).resizable().scaledToFit() }
            else { equipmentImage }
            #else
            if let data = exercise.photo, let photo = NSImage(data: data) { Image(nsImage: photo).resizable().scaledToFit() }
            else { equipmentImage }
            #endif
        }.accessibilityHidden(true)
    }
    private var equipmentImage: some View {
        Image("strength-" + assetName).resizable().interpolation(.high).scaledToFit().padding(2)
    }
    private var assetName: String {
        let name = exercise.name.lowercased()
        switch exercise.equipment.lowercased() {
        case "barbell":
            if name.contains("bench") { return "bench" }
            if name.contains("squat") || name.contains("press") { return "squat" }
            return "barbell"
        case "dumbbell":
            return name.contains("bench") || name.contains("shoulder press") ? "adjustable-bench" : "dumbbell"
        case "kettlebell": return "kettlebell"
        case "smith machine": return "smith"
        case "machine":
            if name.contains("leg press") { return "leg-press" }
            if name.contains("extension") { return "leg-extension" }
            if name.contains("curl") { return "leg-curl" }
            if name.contains("chest") { return "chest-press" }
            if name.contains("calf") { return "calf" }
            if name.contains("abduction") { return "hip-abduction" }
            return "cable"
        case "cable":
            if name.contains("pulldown") { return "pulldown" }
            if name.contains("row") { return "row" }
            return "cable"
        case "bodyweight":
            if name.contains("pull-up") { return "pullup" }
            if name.contains("dip") { return "dip" }
            return "mat"
        default: return "dumbbell"
        }
    }
}

struct StrengthExercisePicker: View {
    @ObservedObject var tracker: StrengthWorkoutController
    var libraryOnly = false
    var selectedExercises: (([StrengthExercise]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State var equipment = "All"
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
    @State private var photoError: String?
    #if os(iOS)
    @State private var selection: PhotosPickerItem?
    @State private var resolvedSelection: PhotosPickerItem?
    #endif
    private var loadingPhoto: Bool {
        #if os(iOS)
        selection != resolvedSelection
        #else
        false
        #endif
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                TextField("Equipment / gym machine name", text: $equipment)
                #if os(iOS)
                PhotosPicker(photo == nil ? "Add your machine photo" : "Change photo", selection: $selection, matching: .images)
                    .task(id: selection) {
                        let item = selection
                        guard let item else { return }
                        let data = try? await item.loadTransferable(type: Data.self)
                        guard !Task.isCancelled, selection == item else { return }
                        photo = nil; photoError = nil
                        if let data, let image = UIImage(data: data) {
                            let scale = min(1, 512 / max(image.size.width, image.size.height))
                            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                            let format = UIGraphicsImageRendererFormat(); format.scale = 1
                            let result = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.7)
                            if let result, result.count <= 1_000_000 { photo = result }
                        }
                        if photo == nil { photoError = "Photo could not be loaded. Choose another, or save without a photo." }
                        resolvedSelection = item
                    }
                #endif
                if loadingPhoto { ProgressView("Loading photo…") }
                else if photo != nil { Text("Photo ready · saved on this device").font(.caption) }
                if let photoError { Text(photoError).font(.caption) }
                Text("Give different gym machines distinct names so their weights and records remain comparable.").font(.caption)
            }.navigationTitle("Custom exercise").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    var entry = StrengthExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines), equipment: equipment.trimmingCharacters(in: .whitespacesAndNewlines)); entry.photo = photo
                    if tracker.change({ $0.customExercises.append(entry) }) { saved(entry); dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingPhoto) }
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
