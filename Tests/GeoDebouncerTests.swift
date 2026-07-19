import XCTest

final class GeoDebouncerTests: XCTestCase {

    func testRequiresConsecutiveObservationsToFlip() {
        var d = GeoDebouncer(threshold: 3)
        // Two violations are not enough to flip from unknown.
        XCTAssertFalse(d.observe(domain: "claude.ai", target: .violated).changed)
        XCTAssertFalse(d.observe(domain: "claude.ai", target: .violated).changed)
        // Third consecutive violation commits.
        let third = d.observe(domain: "claude.ai", target: .violated)
        XCTAssertTrue(third.changed)
        XCTAssertEqual(third.state, .violated)
    }

    func testFlappingIsSuppressed() {
        var d = GeoDebouncer(threshold: 3)
        // Alternating observations never accumulate 3-in-a-row, so nothing commits.
        for i in 0..<10 {
            let target: GeoLockState = (i % 2 == 0) ? .violated : .compliant
            XCTAssertFalse(d.observe(domain: "claude.ai", target: target).changed,
                           "flapping should not commit a state change")
        }
        XCTAssertEqual(d.state(for: "claude.ai"), .unknown)
    }

    func testReturnToCompliantAfterViolation() {
        var d = GeoDebouncer(threshold: 2)
        _ = d.observe(domain: "claude.ai", target: .violated)
        let committedViolation = d.observe(domain: "claude.ai", target: .violated)
        XCTAssertTrue(committedViolation.changed)
        XCTAssertEqual(committedViolation.state, .violated)

        // Now recover: two consecutive compliant observations flip back.
        XCTAssertFalse(d.observe(domain: "claude.ai", target: .compliant).changed)
        let recovered = d.observe(domain: "claude.ai", target: .compliant)
        XCTAssertTrue(recovered.changed)
        XCTAssertEqual(recovered.state, .compliant)
    }

    func testInterruptedStreakResets() {
        var d = GeoDebouncer(threshold: 3)
        _ = d.observe(domain: "x", target: .violated)   // count 1
        _ = d.observe(domain: "x", target: .violated)   // count 2
        _ = d.observe(domain: "x", target: .compliant)  // resets pending
        _ = d.observe(domain: "x", target: .violated)   // count 1 again
        XCTAssertEqual(d.state(for: "x"), .unknown)      // still not committed
    }

    func testThresholdOneCommitsImmediately() {
        var d = GeoDebouncer(threshold: 1)
        let r = d.observe(domain: "x", target: .violated)
        XCTAssertTrue(r.changed)
        XCTAssertEqual(r.state, .violated)
    }
}
