#if DEBUG
import SwiftUI
import StrengthTracking
import StrandAnalytics
import WhoopProtocol
#if os(iOS)
import ActivityKit
#endif

/// Screenshot-only synthetic data. No strap commands, database reads or health data uploads.
struct StrengthDemoView: View {
    let mode: String
    @StateObject private var tracker: StrengthWorkoutController
    init(mode: String) {
        self.mode = mode
        let now = Date()
        var state = StrengthState()
        state.wristAlert = true
        for (day, load) in zip([42, 35, 28, 21, 14, 7, 0], [50.0, 52.5, 52.5, 55, 55, 57.5, 60]) {
            let start = now.addingTimeInterval(-Double(day * 86400 + 2400))
            state.start(now: start)
            state.active!.name = "Upper body A"
            var warmup = StrengthSet(reps: 12, kilograms: 20)
            warmup.kind = .warmup
            state.active!.movements = [
                StrengthMovement(exercise: StrengthExercise.catalog[1], sets: [warmup] + (0..<3).map { _ in StrengthSet(reps: 8, kilograms: load) }),
                StrengthMovement(exercise: StrengthExercise.catalog[16], sets: (0..<3).map { _ in StrengthSet(reps: 12, kilograms: 45) }),
                StrengthMovement(exercise: StrengthExercise.catalog[7], sets: (0..<3).map { _ in StrengthSet(reps: 10, kilograms: 16) }),
                StrengthMovement(exercise: StrengthExercise.catalog[17], sets: (0..<3).map { _ in StrengthSet(reps: 12, kilograms: 22.5) })
            ]
            let movements = state.active!.movements
            // Irregular work/rest lengths and equipment transitions span the full session.
            let starts: [Double] = [180, 350, 540, 750, 1000, 1160, 1340, 1550, 1720, 1875, 2050, 2180, 2280]
            let durations: [Double] = [32, 38, 42, 45, 40, 44, 47, 35, 39, 42, 36, 40, 43]
            var index = 0
            for movement in movements {
                for set in movement.sets {
                    state.startSet(movementID: movement.id, setID: set.id, now: start.addingTimeInterval(starts[index]))
                    state.completeSet(movementID: movement.id, setID: set.id, now: start.addingTimeInterval(starts[index] + durations[index]))
                    index += 1
                }
            }
            state.finish(now: start.addingTimeInterval(2400))
        }
        let routine = StrengthRoutine(name: "Upper body A", movements: state.history[0].movements, restSeconds: 90, unit: .kg)
        state.routines = [routine]
        if ["active", "rest", "exercises", "picker", "warmup", "minimized", "island", "edit-set"].contains(mode) {
            state.start(routine: routine, now: now.addingTimeInterval(-360))
            let movement = state.active!.movements[0]
            if mode == "warmup" {
                state.active!.movements[0].sets[0].kind = .warmup
                state.active!.movements[0].sets[0].kilograms = 20
                state.active!.movements[0].sets[0].reps = 12
            } else {
                state.startSet(movementID: movement.id, setID: movement.sets[0].id, now: now.addingTimeInterval(-190))
                state.completeSet(movementID: movement.id, setID: movement.sets[0].id, now: now.addingTimeInterval(-158))
                state.startSet(movementID: movement.id, setID: movement.sets[1].id, now: now.addingTimeInterval(-72))
                state.completeSet(movementID: movement.id, setID: movement.sets[1].id, now: now.addingTimeInterval(-30))
            }
            if mode == "active" {
                state.startSet(movementID: movement.id, setID: movement.sets[2].id, now: now.addingTimeInterval(-10))
            }
        }
        let disk = StrengthFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("strength-demo/\(UUID()).json"))
        try? disk.save(state)
        let controller = StrengthWorkoutController(storage: disk, platformServices: false)
        controller.liveReading = { (mode == "warmup" ? 102 : mode == "active" ? 138 : 118, nil) }
        let demoZones = HRZones.zones(maxHR: 190, customLowerBounds: [90, 110, 130, 150, 170])
        controller.heartRateZones = { demoZones }
        controller.loadMetrics = { session in
            let samples = Self.demoSamples(session: session, now: now)
            return .calculate(session: session, samples: samples, now: now, maxHR: 190, restingHR: 60, sex: "male", method: .edwards, zones: demoZones)
        }
        UserDefaults.standard.set(mode == "exercises" ? "Exercises" : "Live", forKey: "strength.sessionTab")
        UserDefaults.standard.set(mode != "summary-plain", forKey: "strength.summaryZones")
        _tracker = StateObject(wrappedValue: controller)
    }

    /// Illustrative fixture, NOT a physiological model or real strap recording. The same set
    /// timestamps drive the effort peaks and exercise strip. Production analytics are unchanged.
    private static func demoSamples(session: StrengthSession, now: Date) -> [HRSample] {
        let count = max(0, Int((session.finishedAt ?? now).timeIntervalSince(session.startedAt)))
        let sets = session.movements.flatMap(\.sets).filter { $0.startedAt != nil && $0.completedAt != nil }
            .sorted { $0.startedAt! < $1.startedAt! }
        let peaks: [Double] = [122, 143, 149, 154, 148, 156, 151, 146, 153, 150, 140, 147, 143]
        let baseline: [(Double, Double)] = [(0, 84), (100, 103), (170, 107), (420, 104), (800, 111),
            (1020, 106), (1300, 117), (1470, 109), (1750, 119), (1930, 113), (2270, 116), (2330, 108), (2400, 91)]
        var random: UInt64 = 42
        var heartRate = 84.0
        var wander = 0.0
        return (0...count).map { second in
            let time = Double(second)
            let upper = baseline.firstIndex(where: { $0.0 > time }) ?? (baseline.count - 1)
            let lower = max(0, upper - 1)
            let fraction = min(1, max(0, (time - baseline[lower].0) / max(1, baseline[upper].0 - baseline[lower].0)))
            var target = baseline[lower].1 + fraction * (baseline[upper].1 - baseline[lower].1)
            for (index, set) in sets.enumerated() {
                let begin = set.startedAt!.timeIntervalSince(session.startedAt) + 6
                let end = set.completedAt!.timeIntervalSince(session.startedAt) + 10
                if time >= begin && time <= end { target = peaks[index % peaks.count] }
            }
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double((random >> 32) % 1001) / 500 - 1
            wander = 0.83 * wander + 0.7 * noise
            heartRate += (target - heartRate) / (target > heartRate ? 11 : 34)
            return HRSample(ts: Int(session.startedAt.timeIntervalSince1970) + second,
                            bpm: Int((heartRate + wander + noise * 0.65).rounded()))
        }
    }
    var body: some View {
        Group {
            if mode == "picker" { StrengthExercisePicker(tracker: tracker) }
            else if mode == "machines" { StrengthExercisePicker(tracker: tracker, libraryOnly: true, equipment: "Machine") }
            else if mode == "custom" { StrengthCustomExerciseView(tracker: tracker, saved: { _ in }) }
            else if mode == "template", let routine = tracker.state.routines.first { StrengthRoutineEditor(routine: routine, tracker: tracker) }
            else if mode == "settings" { StrengthSettingsView(tracker: tracker) }
            else if mode == "edit-set", let set = tracker.state.active?.nextSet?.set { StrengthSetEditor(set: set, unit: .kg, save: { _ in true }) }
            else if mode == "summary", let session = tracker.state.history.first { StrengthSummaryView(session: session, tracker: tracker) }
            else if ["summary-detail", "summary-plain"].contains(mode), let session = tracker.state.history.first {
                StrengthSummaryView(session: session, tracker: tracker, initialScrollTarget: "heart-rate", highlightedMovement: session.movements.first?.id)
            }
            else if mode == "achievements", let session = tracker.state.history.first {
                StrengthSummaryView(session: session, tracker: tracker, initialScrollTarget: "achievements", highlightedMovement: session.movements.first?.id)
            }
            else { content }
        }
        .task { await showDemoActivity() }
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        if ["minimized", "island"].contains(mode) {
            RootTabView(homeScreenQuickActionsEnabled: true, strength: tracker)
        } else {
            StrengthWorkoutsView(tracker: tracker, section: mode == "history" ? "History" : mode == "progress" ? "Progress" : "Train")
        }
        #else
        StrengthWorkoutsView(tracker: tracker, section: mode == "history" ? "History" : mode == "progress" ? "Progress" : "Train")
        #endif
    }

    private func showDemoActivity() async {
        #if os(iOS) && targetEnvironment(simulator)
        // Simulator system capture only; never enables BLE/platform services.
        guard mode == "island", let session = tracker.state.active, let next = session.nextSet else { return }
        try? await Task.sleep(for: .seconds(2))
        for activity in Activity<StrengthActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        do {
            let content = StrengthActivityAttributes.ContentState(exercise: next.movement.exercise.name,
                setLabel: "Working set", restStart: session.openRest?.startedAt, restEnd: tracker.state.rest?.deadline)
            _ = try Activity.request(attributes: StrengthActivityAttributes(sessionID: session.id, name: session.name,
                startedAt: session.startedAt), content: ActivityContent(state: content, staleDate: nil), pushType: nil)
        } catch { print("Demo Live Activity unavailable: \(error)") }
        #endif
    }
}
#endif
