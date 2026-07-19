import XCTest

final class NetworkInspectorTests: XCTestCase {

    // Captured `route -n get default` output with a physical default (no VPN).
    let routeDefaultPhysical = """
       route to: default
    destination: default
           mask: default
        gateway: 192.168.1.1
      interface: en0
          flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
     recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
           0         0         0         0         0         0      1500         0
    """

    // Captured `route -n get default` output while a VPN owns the default route.
    let routeDefaultVPN = """
       route to: default
    destination: default
           mask: default
        gateway: 10.8.0.1
      interface: utun4
          flags: <UP,GATEWAY,DONE,STATIC>
    """

    // Captured `route -n get -ifscope en0 default` output (physical gw while VPN up).
    let routeScopedEn0 = """
       route to: default
    destination: default
        gateway: 192.168.1.1
      interface: en0
          flags: <UP,GATEWAY,DONE,STATIC,IFSCOPE>
    """

    func testParsePhysicalDefault() {
        let r = NetworkInspector.parseRouteGet(routeDefaultPhysical)
        XCTAssertEqual(r.gateway, "192.168.1.1")
        XCTAssertEqual(r.interface, "en0")
        XCTAssertFalse(NetworkInspector.isTunnelInterface(r.interface))
    }

    func testParseVPNDefaultDetectsTunnel() {
        let r = NetworkInspector.parseRouteGet(routeDefaultVPN)
        XCTAssertEqual(r.gateway, "10.8.0.1")
        XCTAssertEqual(r.interface, "utun4")
        XCTAssertTrue(NetworkInspector.isTunnelInterface(r.interface))
    }

    func testParseScopedGivesPhysicalGateway() {
        let r = NetworkInspector.parseRouteGet(routeScopedEn0)
        XCTAssertEqual(r.gateway, "192.168.1.1")
        XCTAssertEqual(r.interface, "en0")
    }

    func testTunnelPrefixes() {
        XCTAssertTrue(NetworkInspector.isTunnelInterface("utun0"))
        XCTAssertTrue(NetworkInspector.isTunnelInterface("ppp0"))
        XCTAssertTrue(NetworkInspector.isTunnelInterface("ipsec0"))
        XCTAssertFalse(NetworkInspector.isTunnelInterface("en0"))
        XCTAssertFalse(NetworkInspector.isTunnelInterface(nil))
    }

    func testPhysicalCandidatesFromList() {
        let list = "lo0 gif0 stf0 en0 en1 utun0 utun1 bridge0"
        let c = NetworkInspector.physicalCandidates(fromIfconfigList: list)
        XCTAssertEqual(c, ["en0", "en1"])
    }

    func testParseInetAddress() {
        let ifconfig = """
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            options=6463<RXCSUM,TXCSUM,TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM>
            ether a4:83:e7:00:00:00
            inet6 fe80::1cb:2f1a:0000:0000%en0 prefixlen 64 secured scopeid 0xa
            inet 192.168.1.23 netmask 0xffffff00 broadcast 192.168.1.255
            nd6 options=201<PERFORMNUD,DAD>
            media: autoselect
            status: active
        """
        XCTAssertEqual(NetworkInspector.parseInetAddress(fromIfconfig: ifconfig), "192.168.1.23")
        XCTAssertTrue(NetworkInspector.isInterfaceActive(fromIfconfig: ifconfig))
    }

    func testInactiveInterface() {
        let ifconfig = """
        en1: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: inactive
        """
        XCTAssertFalse(NetworkInspector.isInterfaceActive(fromIfconfig: ifconfig))
        XCTAssertNil(NetworkInspector.parseInetAddress(fromIfconfig: ifconfig))
    }
}
