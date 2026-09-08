import Foundation

/// Serializes asynchronous OS notification adds with cancellation and replacement.
/// The transport is injected so delayed add completions can be tested without a phone.
@MainActor
public final class StrengthRestScheduler {
    private let add: (StrengthRest) async throws -> Void
    private let remove: (UUID) -> Void
    private let onError: () -> Void
    private var currentID: UUID?
    private var revision = UUID()
    private var task: Task<Void, Never>?

    public init(add: @escaping (StrengthRest) async throws -> Void,
                remove: @escaping (UUID) -> Void, onError: @escaping () -> Void) {
        self.add = add; self.remove = remove; self.onError = onError
    }

    public func replace(with rest: StrengthRest?) {
        let previous = task
        previous?.cancel()
        if let currentID { remove(currentID) }
        let token = UUID()
        revision = token
        currentID = rest?.id
        guard let rest else { return }
        task = Task { [weak self] in
            // An old add can finish after cancellation. Its cleanup must precede the new add,
            // particularly when a permission change reschedules the SAME timer identifier.
            await previous?.value
            guard let self, !Task.isCancelled, self.revision == token else { return }
            do { try await self.add(rest) }
            catch { if self.revision == token { self.onError() } }
            if Task.isCancelled || self.revision != token { self.remove(rest.id) }
        }
    }

    public func drain() async { await task?.value }
}
