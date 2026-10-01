import Foundation

/// Delay schedule for status polling: starts short, grows while nothing
/// changes, resets on progress, and is jittered so many devices don't poll in
/// lockstep.
struct PollingBackoff {
    let base: TimeInterval
    var growth: Double = 1.5
    var maximum: TimeInterval = 30
    private(set) var current: TimeInterval

    init(base: TimeInterval, growth: Double = 1.5, maximum: TimeInterval = 30) {
        self.base = base
        self.growth = growth
        self.maximum = maximum
        self.current = base
    }

    /// Returns the next jittered delay in nanoseconds and grows the interval.
    mutating func nextDelayNanoseconds() -> UInt64 {
        let jittered = current * Double.random(in: 0.85...1.15)
        current = min(maximum, current * growth)
        return UInt64(jittered * 1_000_000_000)
    }

    mutating func reset() { current = base }
}
