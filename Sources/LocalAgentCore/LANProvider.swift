import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Host rules for `lan` inference providers (ADR 0011).
///
/// A LAN host is either a literal private address or an mDNS `.local` name:
/// - IPv4: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918) and 169.254.0.0/16 (link-local),
///   except 169.254.169.254 (cloud instance-metadata address, never an inference server).
/// - IPv6: fc00::/7 (unique local) and fe80::/10 (link-local, optional `%zone`).
/// - Names: `<label>(.<label>)*.local` (RFC 6762). Any other DNS name is rejected because it could resolve publicly.
///
/// Loopback is not a LAN host (use `local`). Public, CGNAT (100.64/10), multicast, unspecified, IPv4-mapped IPv6 and
/// non-canonical IPv4 spellings (`3232235777`, `0xC0.0xA8.1.1`, `192.168.001.001`) are rejected.
/// `.local` names are resolved again immediately before every request and every resolved address must be a LAN address.
public enum LANHost {
    public enum Classification: Equatable, Sendable { case privateIPv4, privateIPv6, mdnsName }

    /// Classifies `host` as it appears in `URL.host` (IPv6 without brackets). Returns nil when it is not a LAN host.
    public static func classify(_ host: String) -> Classification? {
        let host = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        if let bytes = parseIPv4(host) { return isLANIPv4(bytes) ? .privateIPv4 : nil }
        if host.contains(":") {
            let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            guard let bytes = parseIPv6(String(parts[0])) else { return nil }
            if parts.count == 2 {
                // A zone index only makes sense for link-local addresses.
                guard isLinkLocalIPv6(bytes),
                      parts[1].range(of: "^[A-Za-z0-9]{1,15}$", options: .regularExpression) != nil else { return nil }
            }
            return isLANIPv6(bytes) ? .privateIPv6 : nil
        }
        return isMDNSName(host) ? .mdnsName : nil
    }

    /// Strict dotted-quad: four decimal parts, no leading zeros, each ≤ 255.
    static func parseIPv4(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0", let value = UInt8(part) else { return nil }
            bytes.append(value)
        }
        return bytes
    }
    static func parseIPv6(_ text: String) -> [UInt8]? {
        guard !text.isEmpty, text.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return nil }
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
    public static func isLANIPv4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        if b == [169, 254, 169, 254] { return false }
        return b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254)
    }
    static func isLinkLocalIPv6(_ b: [UInt8]) -> Bool { b.count == 16 && b[0] == 0xfe && (b[1] & 0xc0) == 0x80 }
    public static func isLANIPv6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        return (b[0] & 0xfe) == 0xfc || isLinkLocalIPv6(b)
    }
    static func isMDNSName(_ host: String) -> Bool {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        guard name.count <= 253, name.hasSuffix(".local") else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-"
                && label.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
        }
    }

    /// Every resolved address must be a LAN address; an empty answer is a failure.
    public static func checkResolved(_ addresses: [[UInt8]]) throws {
        guard !addresses.isEmpty else { throw AgentError.rejected("The LAN host name did not resolve.") }
        for address in addresses {
            let allowed = address.count == 4 ? isLANIPv4(address) : isLANIPv6(address)
            guard allowed else {
                throw AgentError.rejected("The LAN host name resolved to an address outside the local network. Request refused.")
            }
        }
    }

    /// Resolves `name` with the system resolver (mDNS for `.local`). Blocking work runs off the cooperative pool.
    static func resolve(_ name: String) async throws -> [[UInt8]] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(name, nil, &hints, &result) == 0 else {
                    continuation.resume(throwing: AgentError.rejected("The LAN host name did not resolve."))
                    return
                }
                defer { freeaddrinfo(result) }
                var addresses: [[UInt8]] = []
                var cursor = result
                while let entry = cursor?.pointee {
                    if entry.ai_family == AF_INET, let raw = entry.ai_addr {
                        raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                            var address = pointer.pointee.sin_addr
                            addresses.append(withUnsafeBytes(of: &address) { Array($0) })
                        }
                    } else if entry.ai_family == AF_INET6, let raw = entry.ai_addr {
                        raw.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                            var address = pointer.pointee.sin6_addr
                            addresses.append(withUnsafeBytes(of: &address) { Array($0) })
                        }
                    }
                    cursor = entry.ai_next
                }
                continuation.resume(returning: addresses)
            }
        }
    }
}

/// Where a provider sends prompts and tool results. Shown before submission.
public enum InferenceDestination: Equatable, Sendable {
    /// `local` (loopback) or `managed` (bundled runtime).
    case thisMac
    /// `lan`: a private-network host. `encrypted` is true for HTTPS.
    case lan(host: String, encrypted: Bool)
    /// `litellm`: an HTTPS gateway.
    case cloud

    /// Stable machine-readable code (diagnostics output).
    public var code: String {
        switch self {
        case .thisMac: "this-mac"
        case .lan(_, let encrypted): encrypted ? "lan-tls" : "lan-unencrypted"
        case .cloud: "cloud"
        }
    }
    /// One-line label for the task window.
    public var label: String {
        switch self {
        case .thisMac: "Local inference · tools connect to remote services"
        case .cloud: "Cloud inference through your LiteLLM gateway"
        case .lan(let host, true): "LAN · TLS · your request and tool results are sent to \(host)"
        case .lan(let host, false): "LAN · unencrypted · your request and tool results are sent to \(host) in plain text"
        }
    }
}
extension ProviderSpec {
    public var destination: InferenceDestination {
        switch kind {
        case .local, .managed: .thisMac
        case .litellm: .cloud
        case .lan: .lan(host: baseURL?.host ?? "LAN host", encrypted: baseURL?.scheme == "https")
        }
    }
    /// Validates this provider's endpoint and, for a `lan` name, re-resolves it and checks every address.
    /// Called immediately before each request. Returns the base URL to use.
    func verifiedBaseURL() async throws -> URL {
        guard kind != .managed, let baseURL else { throw AgentError.rejected("The local model runtime is not ready.") }
        try AgentConfiguration.validateProviderEndpoint(self)
        if kind == .lan, let host = baseURL.host, LANHost.classify(host) == .mdnsName {
            try LANHost.checkResolved(try await LANHost.resolve(host))
        }
        return baseURL
    }
}

enum ProviderCredential {
    /// Keychain bearer token for a configured provider. A configured account with no saved token fails the request.
    static func bearer(account: String?) throws -> String? {
        guard let account else { return nil }
        guard let token = try CredentialStore.read(account: account), !token.isEmpty else {
            throw AgentError.rejected("Save the credential for \(account) in Settings first.")
        }
        return token
    }
}

/// "Test connection": lists the model IDs an OpenAI-compatible provider reports at `GET <baseURL>/models`.
/// Uses the same endpoint rules, credential and redirect refusal as inference. Returns model IDs only; nothing is logged.
public enum ProviderProbe {
    public static let maximumResponseBytes = 65536
    public static let maximumModelIDs = 100

    public static func listModels(provider: ProviderSpec, timeoutSeconds: Int = 10) async throws -> [String] {
        guard provider.kind != .managed else {
            throw AgentError.rejected("The bundled runtime is checked with --runtime-smoke-test, not a provider probe.")
        }
        let baseURL = try await provider.verifiedBaseURL()
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        if let token = try ProviderCredential.bearer(account: provider.credentialAccount) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Double(timeoutSeconds)
        configuration.timeoutIntervalForResource = Double(timeoutSeconds)
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentError.rejected("Model list request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw AgentError.rejected("Model list response exceeded the size limit.") }
            data.append(byte)
        }
        return try parseModelList(data)
    }

    /// OpenAI shape: `{"data":[{"id":"…"}]}`. Keeps at most 100 printable IDs of ≤ 256 characters.
    static func parseModelList(_ data: Data) throws -> [String] {
        struct List: Decodable { struct Entry: Decodable { let id: String }; let data: [Entry] }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            throw AgentError.rejected("The provider did not return an OpenAI-compatible model list.")
        }
        return list.data.map(\.id)
            .filter { !$0.isEmpty && $0.count <= 256 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
            .prefix(maximumModelIDs).map { $0 }
    }
}
