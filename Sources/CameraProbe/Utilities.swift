import Foundation

/// Resolves `hostname` via getaddrinfo and logs the result.
/// Returns true on success, false on failure, so callers (e.g. a future
/// `--test` command) can act on it instead of only reading logs.
@discardableResult
func testDNS(_ hostname: String) -> Bool {
    var hints = addrinfo(
        ai_flags: 0,
        ai_family: AF_INET,
        ai_socktype: SOCK_STREAM,
        ai_protocol: 0,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )

    var result: UnsafeMutablePointer<addrinfo>?

    let status = getaddrinfo(hostname, nil, &hints, &result)

    if status == 0 {
        logger.info("DNS OK: \(hostname, privacy: .public)")
        freeaddrinfo(result)
        return true
    } else {
        logger.error("DNS FAILED: \(hostname, privacy: .public)")
        return false
    }
}
