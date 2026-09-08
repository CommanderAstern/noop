#if DEBUG
import SwiftUI
import StrengthTracking
import StrandAnalytics
import WhoopProtocol

/// Screenshot-only synthetic data. No strap commands, database reads or health data uploads.
struct StrengthDemoView: View {
    let mode: String
    @StateObject private var tracker: StrengthWorkoutController
    init(mode: String) {
        self.mode = mode
        let now = Date()
        var state = StrengthState()
        for day in [14, 7, 0] {
            let start = now.addingTimeInterval(-Double(day * 86400 + 2400))
            state.start(now: start)
            state.active!.name = "Upper body A"
            state.active!.movements = [StrengthMovement(exercise: StrengthExercise.catalog[1], sets: (0..<3).map { _ in StrengthSet(reps: 8, kilograms: day == 14 ? 50 : day == 7 ? 55 : 60) }),
                                      StrengthMovement(exercise: StrengthExercise.catalog[16], sets: (0..<3).map { _ in StrengthSet(reps: 12, kilograms: 45) })]
            let movements = state.active!.movements
            var offset = 120.0
            for movement in movements {
                for set in movement.sets {
                    state.startSet(movementID: movement.id, setID: set.id, now: start.addingTimeInterval(offset))
                    state.completeSet(movementID: movement.id, setID: set.id, now: start.addingTimeInterval(offset + 40))
                    offset += 150
                }
            }
            state.finish(now: start.addingTimeInterval(2400))
        }
        let routine = StrengthRoutine(name: "Upper body A", movements: state.history[0].movements, restSeconds: 90, unit: .kg)
        state.routines = [routine]
        if ["active", "rest", "exercises", "picker"].contains(mode) {
            state.start(routine: routine, now: now.addingTimeInterval(-300))
            let movement = state.active!.movements[0]
            state.startSet(movementID: movement.id, setID: movement.sets[0].id, now: now.addingTimeInterval(-80))
            state.completeSet(movementID: movement.id, setID: movement.sets[0].id, now: now.addingTimeInterval(-30))
            if mode == "active" {
                state.startSet(movementID: movement.id, setID: movement.sets[1].id, now: now.addingTimeInterval(-10))
            }
        }
        let disk = StrengthFileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("strength-demo/\(UUID()).json"))
        try? disk.save(state)
        let controller = StrengthWorkoutController(storage: disk, platformServices: false)
        controller.liveReading = { (118, 2) }
        controller.loadMetrics = { session in
            let count = Int((session.finishedAt ?? now).timeIntervalSince(session.startedAt))
            let samples = (0...max(0, count)).map { second in HRSample(ts: Int(session.startedAt.timeIntervalSince1970) + second, bpm: 120 + Int(32 * sin(Double(second) / 90))) }
            return .calculate(session: session, samples: samples, now: now, maxHR: 190, restingHR: 60, sex: "male", method: .edwards)
        }
        UserDefaults.standard.set(mode == "exercises" ? "Exercises" : "Live", forKey: "strength.sessionTab")
        _tracker = StateObject(wrappedValue: controller)
    }
    var body: some View {
        Group {
            if mode == "picker" { StrengthExercisePicker(tracker: tracker) }
            else if mode == "summary", let session = tracker.state.history.first { StrengthSummaryView(session: session, tracker: tracker) }
            else { StrengthWorkoutsView(tracker: tracker, section: mode == "history" ? "History" : mode == "progress" ? "Progress" : "Train") }
        }
    }
}
#endif
