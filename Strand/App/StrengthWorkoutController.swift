import Foundation
import Combine
import StrengthTracking
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// App-owned, not view-owned. Navigation never creates a new clock or notification scheduler.
@MainActor
final class StrengthWorkoutController: ObservableObject {
    static let notificationPrefix = "noop.strength.rest."
    @Published private(set) var state = StrengthState()
    @Published private(set) var error: String?
    @Published private(set) var notificationStatus = "Phone alerts are off."
    @Published private(set) var restStatus: String?
    private let storage: StrengthFileStore
    private var readable = true
    private var foreground = false
    private var suppressedRestID: UUID?
    private let platformServices: Bool
    private var ticker: AnyCancellable?
    private var lifecycle: Set<AnyCancellable> = []
    private lazy var notificationScheduler = StrengthRestScheduler(
        add: { [weak self] rest in try await self?.addNotification(rest) },
        remove: { id in
            let center = UNUserNotificationCenter.current()
            let identifier = Self.notificationPrefix + id.uuidString
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        },
        onError: { [weak self] in
            self?.notificationStatus = "Phone alert could not be scheduled. Keep the app open for the rest timer."
        })
    var strapReady: () -> Bool = { false }
    var buzz: () -> Void = {}
    var loadMetrics: (StrengthSession) async -> StrengthWorkoutMetrics = { _ in StrengthWorkoutMetrics() }

    init(storage suppliedStorage: StrengthFileStore? = nil, platformServices: Bool = true) {
        self.platformServices = platformServices
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storage = suppliedStorage ?? StrengthFileStore(url: folder.appendingPathComponent("StrengthWorkouts/v1.json"))
        do { state = try storage.load() }
        catch {
            readable = false
            self.error = "Strength data could not be read. It has been kept unchanged. Restart the app and try again."
        }
        // Expired countdowns on process launch are always consumed silently, even within grace.
        tick(allowWrist: false)
        guard platformServices else { return }
        #if os(iOS)
        foreground = UIApplication.shared.applicationState == .active
        let activeName = UIApplication.didBecomeActiveNotification
        let inactiveName = UIApplication.willResignActiveNotification
        #else
        foreground = NSApplication.shared.isActive
        let activeName = NSApplication.didBecomeActiveNotification
        let inactiveName = NSApplication.willResignActiveNotification
        #endif
        NotificationCenter.default.publisher(for: activeName).sink { [weak self] _ in
            // Consume BEFORE marking active: reopening must never replay a background deadline.
            self?.tick(allowWrist: false)
            self?.foreground = true
            self?.refreshNotificationStatus()
        }.store(in: &lifecycle)
        NotificationCenter.default.publisher(for: inactiveName).sink { [weak self] _ in
            self?.foreground = false
        }.store(in: &lifecycle)
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            self.tick(allowWrist: self.foreground)
        }
        synchronizeNotification()
        removeOrphanedNotifications()
        refreshNotificationStatus()
    }

    /// Commit to disk first. A failed save leaves both UI and pending side effects unchanged.
    @discardableResult
    func change(_ edit: (inout StrengthState) -> Void) -> Bool {
        guard readable else { return false }
        var next = state
        edit(&next)
        guard next != state else { return true }
        do { try storage.save(next) }
        catch {
            self.error = "Could not save strength data. Your last saved session is intact. Free device storage and try again."
            return false
        }
        let old = state
        state = next
        error = nil
        if old.rest?.id != next.rest?.id || old.phoneAlert != next.phoneAlert {
            restStatus = nil
            synchronizeNotification(previous: old.rest)
        }
        return true
    }

    func tick(allowWrist: Bool, now: Date = Date()) {
        guard let timer = state.rest, !timer.consumed, now >= timer.deadline else { return }
        let ready = strapReady()
        // Persistence failure must not turn a denied cue into an eligible one on a later tick.
        if !allowWrist || !ready || !state.wristAlert || now.timeIntervalSince(timer.deadline) > 2 {
            suppressedRestID = timer.id
        }
        var shouldBuzz = false
        let committed = change { next in
            shouldBuzz = next.consumeRest(now: now,
                foreground: allowWrist && suppressedRestID != timer.id, strapReady: ready)
        }
        guard committed else { return }
        if shouldBuzz {
            buzz()
            restStatus = "Rest complete · wrist cue sent (delivery unconfirmed)."
        } else {
            restStatus = "Rest complete. No wrist cue was sent."
        }
    }

    func setPhoneAlert(_ enabled: Bool) {
        guard change({ $0.phoneAlert = enabled }) else { return }
        if enabled {
            Task { [weak self] in
                do {
                    _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                } catch { self?.notificationStatus = "Phone notification permission could not be requested." }
                self?.refreshNotificationStatus()
                self?.synchronizeNotification()
            }
        } else { notificationStatus = "Phone alerts are off." }
    }

    func refreshNotificationStatus() {
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard let self else { return }
            if !self.state.phoneAlert { self.notificationStatus = "Phone alerts are off." }
            else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                self.notificationStatus = "Phone alerts enabled. Focus and silent settings may silence them."
            } else { self.notificationStatus = "Allow NOOP Lab notifications in iPhone Settings for phone alerts." }
        }
    }

    /// Foreground OS deliveries can race cancellation or consumption. A cancelled/replaced/late
    /// request must not show a banner. Consumed timers remain identifiable through normal delivery.
    func acceptsNotification(_ identifier: String, now: Date = Date()) -> Bool {
        guard state.phoneAlert, let rest = state.rest, state.active?.id == rest.sessionID else { return false }
        return identifier == Self.notificationPrefix + rest.id.uuidString
            && abs(now.timeIntervalSince(rest.deadline)) <= 5
    }

    private func synchronizeNotification(previous: StrengthRest? = nil) {
        guard platformServices else { return }
        let rest = state.rest.flatMap { timer in
            state.phoneAlert && !timer.consumed && timer.deadline > Date() ? timer : nil
        }
        notificationScheduler.replace(with: rest)
    }

    private func addNotification(_ rest: StrengthRest) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard !Task.isCancelled,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let delay = rest.deadline.timeIntervalSinceNow
        guard delay > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest complete")
        content.body = String(localized: "Ready for your next set? Open NOOP Lab to continue.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.notificationPrefix + rest.id.uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
        try await center.add(request)
    }

    private func removeOrphanedNotifications() {
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard let self else { return }
            let currentID = self.state.rest.flatMap { timer in
                self.state.phoneAlert && !timer.consumed ? Self.notificationPrefix + timer.id.uuidString : nil
            }
            let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(Self.notificationPrefix) && $0 != currentID }
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
    }
}
