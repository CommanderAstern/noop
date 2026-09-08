#if os(iOS)
import ActivityKit
import StrengthTracking
import Foundation

/// Serial latest-state reconciler. No widget action sends BLE commands or writes workout data.
@MainActor
final class StrengthLiveActivityController {
    private var desired: StrengthState?
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var lastEnabled: Bool?

    func refreshAuthorization() {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled && UnitPrefs.liveActivityEnabled()
        if enabled != lastEnabled, let desired { lastEnabled = enabled; update(desired) }
    }

    func update(_ state: StrengthState) {
        desired = state; revision += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let captured = self.revision
                await self.reconcile()
                if captured == self.revision { break }
            }
            self.worker = nil
        }
    }

    private func reconcile() async {
        guard let state = desired, let session = state.active,
              ActivityAuthorizationInfo().areActivitiesEnabled, UnitPrefs.liveActivityEnabled() else {
            for activity in Activity<StrengthActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let next = session.nextSet
        let rest = session.openRest
        let end = state.rest?.deadline
        let content = StrengthActivityAttributes.ContentState(
            exercise: next?.movement.exercise.name ?? "All sets completed",
            setLabel: next.map { $0.set.kind == .warmup ? "Warm-up" : "Working set" } ?? "Ready to finish",
            restStart: rest?.startedAt, restEnd: end)
        var kept: Activity<StrengthActivityAttributes>?
        for activity in Activity<StrengthActivityAttributes>.activities {
            if activity.attributes.sessionID == session.id, kept == nil { kept = activity }
            else { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let stateContent = ActivityContent(state: content, staleDate: nil)
        if let kept {
            if kept.content.state != content { await kept.update(stateContent) }
        } else {
            // No per-second updates: the system draws the countdown from the persisted deadline.
            _ = try? Activity.request(attributes: StrengthActivityAttributes(sessionID: session.id, name: session.name, startedAt: session.startedAt), content: stateContent, pushType: nil)
        }
    }
}
#endif
