import XCTest

final class RouteManagerTests: XCTestCase {

    func testPreviewListsAddLinesForFreshState() {
        let shell = ShellRunner(dryRun: true)
        let rm = RouteManager(shell: shell)

        let lines = rm.previewCommands(
            desiredSplitIPs: ["1.2.3.4", "5.6.7.8"],
            gateway: "192.168.1.1",
            desiredBlackholeIPs: []
        )
        XCTAssertTrue(lines.contains("/sbin/route add -host 1.2.3.4 192.168.1.1"))
        XCTAssertTrue(lines.contains("/sbin/route add -host 5.6.7.8 192.168.1.1"))
    }

    func testPreviewListsBlackholeAndRestore() {
        let shell = ShellRunner(dryRun: true)
        let rm = RouteManager(shell: shell)

        let lines = rm.previewCommands(
            desiredSplitIPs: [],
            gateway: "192.168.1.1",
            desiredBlackholeIPs: ["9.9.9.9"]
        )
        XCTAssertTrue(lines.contains { $0.contains("add -host 9.9.9.9 127.0.0.1") })
    }

    func testDryRunReconcileDoesNotExecuteButTracksIntent() {
        let shell = ShellRunner(dryRun: true)
        let rm = RouteManager(shell: shell)

        rm.reconcileSplitRoutes(desiredIPs: ["1.1.1.1"], gateway: "10.0.0.1")
        // Intended state tracked even though nothing was executed (dry-run).
        XCTAssertEqual(rm.installedSplitIPs, ["1.1.1.1"])
        // The command was recorded as a DRY-RUN line, not executed.
        XCTAssertTrue(shell.recentCommands().contains { $0.contains("[DRY-RUN]") })
    }

    func testNoChangeMessageWhenDesiredMatchesInstalled() {
        let shell = ShellRunner(dryRun: true)
        let rm = RouteManager(shell: shell)
        let lines = rm.previewCommands(desiredSplitIPs: [], gateway: nil, desiredBlackholeIPs: [])
        XCTAssertTrue(lines.contains { $0.contains("no route changes needed") })
    }
}
