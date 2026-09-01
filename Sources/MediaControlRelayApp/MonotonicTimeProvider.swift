import Foundation

struct MonotonicTimeProvider: Sendable {
    let now: @Sendable () -> UInt64

    static let live = MonotonicTimeProvider(
        now: { DispatchTime.now().uptimeNanoseconds }
    )
}
