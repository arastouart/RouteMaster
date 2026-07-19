import Foundation

/// Pure debounce state machine for Geo-Lock transitions. A domain must be observed in
/// a new target state `threshold` times in a row before that state is committed. This
/// prevents flapping between compliant/violated on transient geo-lookup noise.
struct GeoDebouncer {
    let threshold: Int
    private(set) var committed: [String: GeoLockState] = [:]
    private var pending: [String: GeoLockState] = [:]
    private var count: [String: Int] = [:]

    init(threshold: Int) {
        self.threshold = max(1, threshold)
    }

    /// Observe `target` for `domain`. Returns the currently-committed state and whether
    /// it just changed on this observation.
    @discardableResult
    mutating func observe(domain: String, target: GeoLockState) -> (state: GeoLockState, changed: Bool) {
        let current = committed[domain] ?? .unknown

        if current == target {
            pending[domain] = nil
            count[domain] = 0
            return (current, false)
        }

        if pending[domain] == target {
            count[domain, default: 0] += 1
        } else {
            pending[domain] = target
            count[domain] = 1
        }

        if (count[domain] ?? 0) >= threshold {
            committed[domain] = target
            pending[domain] = nil
            count[domain] = 0
            return (target, true)
        }
        return (current, false)
    }

    func state(for domain: String) -> GeoLockState {
        committed[domain] ?? .unknown
    }
}
