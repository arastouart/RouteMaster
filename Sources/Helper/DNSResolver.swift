import Foundation
import Darwin

/// Interface-pinned DNS resolver — the heart of RouteMaster's "vantage point" logic.
///
/// Split-domain resolution must reflect what the *ISP* would answer, not what the VPN
/// resolver returns. So instead of `getaddrinfo` (which uses the system resolver, i.e.
/// the VPN path when a tunnel is up), we send a raw DNS query over a UDP socket that is
/// bound to the physical interface's source IP AND pinned to that interface via
/// `IP_BOUND_IF`. This forces the query to egress en0, so returned CDN edge IPs match
/// the ISP's view.
struct DNSResolver {

    struct Record: Equatable {
        let ip: String
        let ttl: UInt32
    }

    enum ResolveError: Error, CustomStringConvertible {
        case socketCreationFailed(Int32)
        case bindFailed(Int32)
        case bindInterfaceFailed(Int32)
        case sendFailed(Int32)
        case receiveTimedOut
        case receiveFailed(Int32)
        case malformedResponse

        var description: String {
            switch self {
            case .socketCreationFailed(let e): return "socket() failed errno=\(e)"
            case .bindFailed(let e):           return "bind() to source IP failed errno=\(e)"
            case .bindInterfaceFailed(let e):  return "IP_BOUND_IF failed errno=\(e)"
            case .sendFailed(let e):           return "sendto() failed errno=\(e)"
            case .receiveTimedOut:             return "DNS receive timed out"
            case .receiveFailed(let e):        return "recvfrom() failed errno=\(e)"
            case .malformedResponse:           return "malformed DNS response"
            }
        }
    }

    /// Public resolver used for split-domain queries (primary + fallback).
    static let primaryResolver = "1.1.1.1"
    static let fallbackResolver = "8.8.8.8"

    /// Source IPv4 of the physical interface to bind to.
    let sourceIP: String
    /// Physical interface name (for `IP_BOUND_IF`).
    let interfaceName: String
    /// Per-query receive timeout.
    let timeout: TimeInterval

    init(sourceIP: String, interfaceName: String, timeout: TimeInterval = 3.0) {
        self.sourceIP = sourceIP
        self.interfaceName = interfaceName
        self.timeout = timeout
    }

    /// Resolve A records for `domain`, trying the primary resolver then the fallback.
    func resolveA(_ domain: String) -> [Record] {
        if let recs = try? query(domain: domain, resolver: Self.primaryResolver), !recs.isEmpty {
            return recs
        }
        return (try? query(domain: domain, resolver: Self.fallbackResolver)) ?? []
    }

    // MARK: - Wire query

    func query(domain: String, resolver: String) throws -> [Record] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw ResolveError.socketCreationFailed(errno) }
        defer { close(fd) }

        // Pin the socket to the physical interface (IP_BOUND_IF).
        var ifIndex = if_nametoindex(interfaceName)
        if ifIndex == 0 {
            // Interface name didn't resolve; continue with source-IP bind only.
            ifIndex = 0
        } else {
            let rc = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF,
                                &ifIndex, socklen_t(MemoryLayout<UInt32>.size))
            if rc != 0 { throw ResolveError.bindInterfaceFailed(errno) }
        }

        // Bind to the physical interface's source IP so the query egresses en0.
        var src = sockaddr_in()
        src.sin_family = sa_family_t(AF_INET)
        src.sin_port = 0
        src.sin_addr.s_addr = inet_addr(sourceIP)
        let bindRC = withUnsafePointer(to: &src) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRC != 0 { throw ResolveError.bindFailed(errno) }

        // Receive timeout.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Destination resolver:53.
        var dst = sockaddr_in()
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = in_port_t(53).bigEndian
        dst.sin_addr.s_addr = inet_addr(resolver)

        // Build and send the query.
        let queryID = UInt16.random(in: 0...UInt16.max)
        let packet = Self.buildQuery(domain: domain, id: queryID)
        let sent = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &dst) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, raw.count, 0,
                           $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 { throw ResolveError.sendFailed(errno) }

        // Receive.
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = recv(fd, &buf, buf.count, 0)
        if n < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { throw ResolveError.receiveTimedOut }
            throw ResolveError.receiveFailed(errno)
        }

        return try Self.parseAnswers(Array(buf.prefix(n)), expectedID: queryID)
    }

    // MARK: - DNS packet build

    /// Build a standard recursive A query for `domain`.
    static func buildQuery(domain: String, id: UInt16) -> [UInt8] {
        var p = [UInt8]()
        p.append(UInt8(id >> 8)); p.append(UInt8(id & 0xff))     // ID
        p.append(0x01); p.append(0x00)                            // flags: RD=1
        p.append(0x00); p.append(0x01)                            // QDCOUNT=1
        p.append(0x00); p.append(0x00)                            // ANCOUNT
        p.append(0x00); p.append(0x00)                            // NSCOUNT
        p.append(0x00); p.append(0x00)                            // ARCOUNT

        for label in domain.split(separator: ".") {
            let bytes = Array(label.utf8)
            p.append(UInt8(bytes.count))
            p.append(contentsOf: bytes)
        }
        p.append(0x00)                                            // root label
        p.append(0x00); p.append(0x01)                            // QTYPE = A
        p.append(0x00); p.append(0x01)                            // QCLASS = IN
        return p
    }

    // MARK: - DNS response parse

    /// Parse A records (+ TTL) from a DNS response, handling name compression.
    static func parseAnswers(_ data: [UInt8], expectedID: UInt16?) throws -> [Record] {
        guard data.count >= 12 else { throw ResolveError.malformedResponse }

        if let expected = expectedID {
            let id = (UInt16(data[0]) << 8) | UInt16(data[1])
            guard id == expected else { throw ResolveError.malformedResponse }
        }

        let qd = (Int(data[4]) << 8) | Int(data[5])
        let an = (Int(data[6]) << 8) | Int(data[7])

        var offset = 12

        // Skip the question section.
        for _ in 0..<qd {
            offset = try skipName(data, offset)
            offset += 4 // QTYPE + QCLASS
            guard offset <= data.count else { throw ResolveError.malformedResponse }
        }

        var records: [Record] = []
        for _ in 0..<an {
            offset = try skipName(data, offset)
            guard offset + 10 <= data.count else { throw ResolveError.malformedResponse }
            let type = (Int(data[offset]) << 8) | Int(data[offset + 1])
            let ttl = (UInt32(data[offset + 4]) << 24)
                    | (UInt32(data[offset + 5]) << 16)
                    | (UInt32(data[offset + 6]) << 8)
                    |  UInt32(data[offset + 7])
            let rdlength = (Int(data[offset + 8]) << 8) | Int(data[offset + 9])
            offset += 10
            guard offset + rdlength <= data.count else { throw ResolveError.malformedResponse }

            if type == 1 && rdlength == 4 { // A record
                let ip = "\(data[offset]).\(data[offset+1]).\(data[offset+2]).\(data[offset+3])"
                records.append(Record(ip: ip, ttl: ttl))
            }
            offset += rdlength
        }
        return records
    }

    /// Advance past a (possibly compressed) domain name, returning the offset just after it.
    private static func skipName(_ data: [UInt8], _ start: Int) throws -> Int {
        var offset = start
        while true {
            guard offset < data.count else { throw ResolveError.malformedResponse }
            let len = Int(data[offset])
            if len == 0 {
                return offset + 1
            } else if len & 0xC0 == 0xC0 {
                // Compression pointer occupies two bytes; name ends here for this field.
                return offset + 2
            } else {
                offset += 1 + len
            }
        }
    }
}
