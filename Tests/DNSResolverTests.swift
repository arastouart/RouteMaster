import XCTest

final class DNSResolverTests: XCTestCase {

    func testBuildQueryHeaderAndQuestion() {
        let id: UInt16 = 0x1234
        let q = DNSResolver.buildQuery(domain: "example.com", id: id)

        // Header
        XCTAssertEqual(q[0], 0x12)
        XCTAssertEqual(q[1], 0x34)
        XCTAssertEqual(q[2], 0x01) // RD set
        XCTAssertEqual(q[3], 0x00)
        XCTAssertEqual(q[4], 0x00); XCTAssertEqual(q[5], 0x01) // QDCOUNT = 1

        // Question: 7 'example' 3 'com' 0
        let expectedQName: [UInt8] =
            [7] + Array("example".utf8) + [3] + Array("com".utf8) + [0]
        let qname = Array(q[12..<(12 + expectedQName.count)])
        XCTAssertEqual(qname, expectedQName)

        // QTYPE = A (1), QCLASS = IN (1)
        let tail = Array(q.suffix(4))
        XCTAssertEqual(tail, [0x00, 0x01, 0x00, 0x01])
    }

    func testParseAnswersSingleARecordWithCompression() throws {
        let id: UInt16 = 0x1234
        var pkt: [UInt8] = []
        // Header
        pkt += [0x12, 0x34]        // ID
        pkt += [0x81, 0x80]        // flags: response, RD, RA
        pkt += [0x00, 0x01]        // QDCOUNT = 1
        pkt += [0x00, 0x01]        // ANCOUNT = 1
        pkt += [0x00, 0x00]        // NSCOUNT
        pkt += [0x00, 0x00]        // ARCOUNT
        // Question: example.com A IN
        pkt += [7] + Array("example".utf8) + [3] + Array("com".utf8) + [0]
        pkt += [0x00, 0x01, 0x00, 0x01]
        // Answer: name pointer -> 0xC00C (offset 12)
        pkt += [0xC0, 0x0C]
        pkt += [0x00, 0x01]        // TYPE A
        pkt += [0x00, 0x01]        // CLASS IN
        pkt += [0x00, 0x00, 0x01, 0x2C] // TTL 300
        pkt += [0x00, 0x04]        // RDLENGTH 4
        pkt += [93, 184, 216, 34]  // 93.184.216.34

        let recs = try DNSResolver.parseAnswers(pkt, expectedID: id)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.ip, "93.184.216.34")
        XCTAssertEqual(recs.first?.ttl, 300)
    }

    func testParseAnswersRejectsWrongID() {
        let pkt: [UInt8] = [0x00, 0x01, 0x81, 0x80] + Array(repeating: 0, count: 8)
        XCTAssertThrowsError(try DNSResolver.parseAnswers(pkt, expectedID: 0x9999))
    }

    func testParseAnswersMalformedTooShort() {
        XCTAssertThrowsError(try DNSResolver.parseAnswers([0x00, 0x01], expectedID: nil))
    }
}
