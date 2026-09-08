import SwiftUI
import Charts
import StrengthTracking
import StrandDesign

struct StrengthHistoryList: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @State private var search = ""
    @State private var filter = "All"
    private var sessions: [StrengthSession] { tracker.state.history.filter {
        (filter == "All" || $0.name == filter) && (search.isEmpty || ($0.name + " " + $0.movements.map { $0.exercise.name }.joined(separator: " ")).localizedCaseInsensitiveContains(search))
    }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        List {
            Picker("Training day", selection: $filter) {
                Text("All templates").tag("All")
                ForEach(Array(Set(tracker.state.history.map(\.name))).sorted(), id: \.self) { Text($0).tag($0) }
            }
            if sessions.isEmpty { Text("Your finished workouts appear here.").foregroundStyle(StrandPalette.textSecondary) }
            ForEach(sessions) { session in
                NavigationLink { StrengthSummaryView(session: session, tracker: tracker) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.startedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(StrandPalette.textSecondary)
                        HStack {
                            if let exercise = session.movements.first?.exercise { StrengthExerciseArt(exercise: exercise).frame(width: 58, height: 58) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.name).font(.headline)
                                Text("\(session.movements.count) exercises · \(session.workingSets) working sets").font(.caption)
                                Text("\(strengthWeight(session.volumeKilograms, unit: session.unit)) \(session.unit.rawValue) lifted · \(session.actualRest.map { strengthTime(Int($0)) } ?? "—") rest").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                            let records = StrengthProgress.records(in: session, history: tracker.state.history)
                            if !records.isEmpty { Label("\(records.count) PR", systemImage: "trophy.fill").font(.caption).foregroundStyle(StrandPalette.zone3) }
                        }
                    }.padding(.vertical, 7)
                }
            }
        }.searchable(text: $search, prompt: "Workout or exercise").listStyle(.plain)
    }
}

struct StrengthProgressView: View {
    @ObservedObject var tracker: StrengthWorkoutController
    @State private var exerciseID: UUID?
    @State private var reps = 8
    @State private var months = 3
    private var exercises: [StrengthExercise] {
        var seen = Set<UUID>()
        return tracker.state.history.flatMap(\.movements).map(\.exercise).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
    private var chosen: UUID? { exerciseID ?? exercises.first?.id }
    private var data: [ProgressPoint] {
        let cutoff = months == 0 ? Date.distantPast : Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast
        return tracker.state.history.filter { $0.startedAt >= cutoff }.compactMap { session in
            let sets = session.movements.filter { $0.exercise.id == chosen }.flatMap(\.sets)
                .filter { $0.completedAt != nil && $0.kind == .working && $0.reps == reps && $0.kilograms > 0 }
            guard let best = sets.map(\.kilograms).max() else { return nil }
            return ProgressPoint(session: session, kilograms: best)
        }.sorted { $0.session.startedAt < $1.session.startedAt }
    }
    struct ProgressPoint: Identifiable { let session: StrengthSession; let kilograms: Double; var id: UUID { session.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if exercises.isEmpty {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(StrandPalette.accent)
                    Text("See your lifts grow").font(.title2.bold())
                    Text("Finish a workout to start tracking your exercises, rep-count bests and progress.").foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Picker("Exercise", selection: Binding(get: { chosen }, set: { exerciseID = $0 })) {
                        ForEach(exercises) { Text("\($0.name) · \($0.equipment)").tag(Optional($0.id)) }
                    }
                    Stepper("Best \(reps)-rep set", value: $reps, in: 1...999)
                    Picker("Period", selection: $months) { Text("1M").tag(1); Text("3M").tag(3); Text("6M").tag(6); Text("All").tag(0) }.pickerStyle(.segmented)
                    if let latest = data.last {
                        StrengthStat(value: "\(strengthWeight(latest.kilograms, unit: tracker.state.unit)) \(tracker.state.unit.rawValue)", label: "Most recent \(reps)-rep best")
                        if let first = data.first, data.count > 1 {
                            Text("\(strengthWeight(latest.kilograms - first.kilograms, unit: tracker.state.unit)) \(tracker.state.unit.rawValue) change in this period").foregroundStyle(StrandPalette.accent)
                        }
                        Chart(data) { point in
                            LineMark(x: .value("Date", point.session.startedAt), y: .value("Load", tracker.state.unit.display(point.kilograms))).foregroundStyle(StrandPalette.accent)
                            PointMark(x: .value("Date", point.session.startedAt), y: .value("Load", tracker.state.unit.display(point.kilograms))).foregroundStyle(StrandPalette.accent)
                        }.frame(height: 210).chartYAxisLabel(tracker.state.unit.rawValue)
                    } else { Text("No completed working sets at \(reps) reps in this period.").foregroundStyle(StrandPalette.textSecondary) }
                    Text("Compared at the same reps, exercise identity and recorded load convention. Warm-ups are excluded; no estimated 1RM.").font(.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("Recent sessions").font(.title2.bold())
                    ForEach(data.reversed()) { point in
                        NavigationLink { StrengthSummaryView(session: point.session, tracker: tracker) } label: {
                            HStack {
                                Text(point.session.startedAt, format: .dateTime.day().month().year()); Spacer()
                                Text("\(strengthWeight(point.kilograms, unit: tracker.state.unit)) \(tracker.state.unit.rawValue) × \(reps)")
                                Image(systemName: "chevron.right")
                            }.font(.subheadline).padding(.vertical, 8)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.padding(20)
        }
    }
}
