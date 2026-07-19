import XCTest

final class AppConfigCodableTests: XCTestCase {

    /// A legacy config.json written before the geo-provider fields existed must still
    /// decode cleanly, leaving both new fields nil (identical default behavior).
    func testLegacyConfigDecodesWithNilProviderFields() throws {
        let legacy = """
        {
          "splitDomains": [ { "domain": "bitgraph.ir", "enabled": true } ],
          "geoLockRules": [ { "domain": "claude.ai", "requiredCountry": "TR", "enabled": true } ],
          "resolveIntervalSeconds": 300,
          "geoCheckIntervalSeconds": 30,
          "dryRun": true,
          "geoDebounceCount": 3
        }
        """
        let config = try JSONDecoder.routeMaster.decode(AppConfig.self, from: Data(legacy.utf8))
        XCTAssertNil(config.geoProvider)
        XCTAssertNil(config.geoAPIKey)
        XCTAssertTrue(config.dryRun)
        XCTAssertEqual(config.splitDomains.first?.domain, "bitgraph.ir")
    }

    /// The seed config must never carry a provider or key (security invariant).
    func testSeedHasNoProviderOrKey() {
        XCTAssertNil(AppConfig.seed.geoProvider)
        XCTAssertNil(AppConfig.seed.geoAPIKey)
    }

    /// Encoding a config with nil provider fields omits the keys (stays clean), and a
    /// set key round-trips.
    func testRoundTripPreservesProviderAndKey() throws {
        var config = AppConfig.seed
        config.geoProvider = "ipinfo"
        config.geoAPIKey = "secret-token-123"

        let data = try JSONEncoder.routeMaster.encode(config)
        let decoded = try JSONDecoder.routeMaster.decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.geoProvider, "ipinfo")
        XCTAssertEqual(decoded.geoAPIKey, "secret-token-123")

        // nil optionals are omitted by the synthesized encoder (encodeIfPresent).
        let seedData = try JSONEncoder.routeMaster.encode(AppConfig.seed)
        let json = String(decoding: seedData, as: UTF8.self)
        XCTAssertFalse(json.contains("geoAPIKey"))
        XCTAssertFalse(json.contains("geoProvider"))
    }
}
