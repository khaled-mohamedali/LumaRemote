import Foundation
import CryptoKit
import os

/// webOS TVs serve `wss://<ip>:3001` with a certificate issued by LG's private CA
/// (the same certificate ships on every LG TV), so the system trust store can't
/// validate it. We use trust-on-first-use: accept the certificate on the first
/// connection to a given TV, remember its SHA-256 fingerprint, and refuse any
/// different certificate afterwards. Only the configured TV host is trusted.
nonisolated final class TVTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let expectedHost: String
    let pinnedFingerprint: String?

    private let state = OSAllocatedUnfairLock(initialState: (observed: String?.none, mismatch: false))

    init(expectedHost: String, pinnedFingerprint: String?) {
        self.expectedHost = expectedHost
        self.pinnedFingerprint = pinnedFingerprint
    }

    /// Fingerprint of the most recent certificate the TV presented.
    var observedFingerprint: String? { state.withLock { $0.observed } }
    /// True if the TV presented a certificate that doesn't match the pinned one.
    var detectedMismatch: Bool { state.withLock { $0.mismatch } }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return (.performDefaultHandling, nil)
        }
        guard space.host == expectedHost, let trust = space.serverTrust,
              let fingerprint = Self.leafFingerprint(of: trust) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        if let pinnedFingerprint, pinnedFingerprint != fingerprint {
            state.withLock { $0.observed = fingerprint; $0.mismatch = true }
            return (.cancelAuthenticationChallenge, nil)
        }
        state.withLock { $0.observed = fingerprint; $0.mismatch = false }
        return (.useCredential, URLCredential(trust: trust))
    }

    static func leafFingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        let data = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Creates the URLSession used for everything that talks to one TV (WebSockets and
/// app-icon downloads). Remember to invalidate it when the connection ends.
enum TVSessionFactory {
    static func makeSession(host: String, pinnedFingerprint: String?) -> (URLSession, TVTrustDelegate) {
        let delegate = TVTrustDelegate(expectedHost: host, pinnedFingerprint: pinnedFingerprint)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        return (session, delegate)
    }
}
