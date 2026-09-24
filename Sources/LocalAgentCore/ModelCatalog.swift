import Foundation

/// One approved, verifiable model file (ADR 0009). `id` is the stable identity; `displayName` is presentation only.
/// Integrity (size + SHA-256) is checked before a file can be used; it says nothing about quality — qualification
/// and benchmark approval are separate (WORK-005).
public struct ModelArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// HTTPS download location on an approved host. Pin an immutable revision, not a moving branch.
    public let sourceURL: URL
    /// Plain `.gguf` name the verified file is stored under in the Models folder.
    public let fileName: String
    public let sizeBytes: Int64
    /// Lowercase hex SHA-256 of the whole file.
    public let sha256: String
    public let quantization: String
    /// SPDX identifier of the model weights license.
    public let license: String
    public let licenseURL: URL?
    /// Template identity and notes, e.g. which chat template is embedded and how tool calls are formatted.
    public let chatTemplate: String
    /// Bundled llama.cpp tags this artifact was checked with. The runtime refuses other tags.
    public let runtimeTags: [String]
    /// Minimum physical memory for this artifact. Model stubs may require more, never less.
    public let minimumMemoryGB: Int
    /// Largest context the artifact is approved for. Model stubs may use less, never more.
    public let contextTokens: Int

    public init(id: String, displayName: String, sourceURL: URL, fileName: String, sizeBytes: Int64, sha256: String,
                quantization: String, license: String, licenseURL: URL? = nil, chatTemplate: String,
                runtimeTags: [String], minimumMemoryGB: Int, contextTokens: Int) {
        self.id = id; self.displayName = displayName; self.sourceURL = sourceURL; self.fileName = fileName
        self.sizeBytes = sizeBytes; self.sha256 = sha256; self.quantization = quantization; self.license = license
        self.licenseURL = licenseURL; self.chatTemplate = chatTemplate; self.runtimeTags = runtimeTags
        self.minimumMemoryGB = minimumMemoryGB; self.contextTokens = contextTokens
    }

    func validate(approvedHosts: [String]) throws {
        func reject(_ what: String) -> AgentError { AgentError.rejected("Model artifact \(id): \(what).") }
        guard id.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            throw AgentError.rejected("Model artifact IDs must contain 1–64 letters, digits, dots, underscores or hyphens.")
        }
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty, displayName.count <= 80 else { throw reject("invalid display name") }
        guard ModelArtifact.isPlainModelFileName(fileName) else { throw reject("fileName must be a plain .gguf file name") }
        guard (1...(Int64(64) << 30)).contains(sizeBytes) else { throw reject("sizeBytes out of range") }
        guard sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw reject("sha256 must be 64 lowercase hex digits") }
        guard !quantization.isEmpty, !license.isEmpty, !chatTemplate.isEmpty else { throw reject("quantization, license and chatTemplate are required") }
        guard !runtimeTags.isEmpty, runtimeTags.allSatisfy({ $0.range(of: "^[A-Za-z0-9._-]{1,32}$", options: .regularExpression) != nil }) else {
            throw reject("runtimeTags must list the qualified runtime tags")
        }
        guard (1...512).contains(minimumMemoryGB), (2048...1_048_576).contains(contextTokens) else { throw reject("memory or context out of range") }
        try ModelArtifact.validateSource(sourceURL, approvedHosts: approvedHosts)
        if let licenseURL, licenseURL.scheme != "https" { throw reject("licenseURL must use HTTPS") }
    }

    static func isPlainModelFileName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.gguf$"#, options: .regularExpression) != nil && !name.contains("..")
    }

    /// HTTPS, no credentials, query or fragment, and an approved host (exact or subdomain).
    static func validateSource(_ url: URL, approvedHosts: [String]) throws {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let host = url.host?.lowercased(), !host.isEmpty else {
            throw AgentError.rejected("Model sources must be plain HTTPS URLs without credentials, query strings or fragments.")
        }
        guard ModelCatalog.isApproved(host: host, approvedHosts: approvedHosts) else {
            throw AgentError.rejected("Model source host \(host) is not approved.")
        }
    }
}

/// Optional `modelCatalog` block in a configuration. Absent fields fall back to the catalog built into the app.
/// Forced managed policy replaces the user configuration entirely, so a user can never extend a managed catalog.
public struct ModelCatalogSpec: Codable, Sendable, Equatable {
    /// Hosts that artifact sources and download redirects may use (exact match or subdomain).
    public let approvedHosts: [String]?
    /// false: artifacts can only be imported from a local file (still hash-verified), never downloaded.
    public let allowDownloads: Bool?
    /// Replaces the built-in artifact list when present.
    public let artifacts: [ModelArtifact]?
    public init(approvedHosts: [String]? = nil, allowDownloads: Bool? = nil, artifacts: [ModelArtifact]? = nil) {
        self.approvedHosts = approvedHosts; self.allowDownloads = allowDownloads; self.artifacts = artifacts
    }
}

/// The effective, validated catalog for one configuration.
public struct ModelCatalog: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    /// Date-based version of the built-in catalog, or "policy" when a configuration supplies the artifacts.
    public let catalogVersion: String
    public let approvedHosts: [String]
    public let allowDownloads: Bool
    public let artifacts: [ModelArtifact]

    public func artifact(id: String) -> ModelArtifact? { artifacts.first { $0.id == id } }

    static func isApproved(host: String, approvedHosts: [String]) -> Bool {
        let host = host.lowercased()
        return approvedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw AgentError.rejected("Unsupported model catalog version.") }
        guard (1...16).contains(approvedHosts.count), approvedHosts.allSatisfy({
            $0.range(of: #"^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#, options: .regularExpression) != nil
        }) else { throw AgentError.rejected("Model catalog approvedHosts must be 1–16 lowercase DNS names (no wildcards).") }
        guard artifacts.count <= 32, Set(artifacts.map(\.id)).count == artifacts.count,
              Set(artifacts.map { $0.fileName.lowercased() }).count == artifacts.count else {
            throw AgentError.rejected("Model catalog needs at most 32 artifacts with unique IDs and file names.")
        }
        for artifact in artifacts { try artifact.validate(approvedHosts: approvedHosts) }
    }

    /// Built-in catalog. Update it together with ADR 0009 and docs/validation-results.md.
    public static let builtIn: ModelCatalog = {
        // A malformed built-in catalog is a build error; tests validate it.
        try! JSONDecoder().decode(ModelCatalog.self, from: Data(builtInJSON.utf8))
    }()

    static let builtInJSON = #"""
    {
      "schemaVersion": 1,
      "catalogVersion": "2026-09-23.1",
      "approvedHosts": ["huggingface.co", "hf.co"],
      "allowDownloads": true,
      "artifacts": [
        {
          "id": "qwen3-4b-instruct-2507-q4_k_m",
          "displayName": "Qwen3 4B Instruct 2507 (Q4_K_M)",
          "sourceURL": "https://huggingface.co/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF/resolve/ae44f08e1392f39c0e474af10c3ff8355c8b6688/Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
          "fileName": "Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
          "sizeBytes": 2497280736,
          "sha256": "2fde00ce69dd4899c70d020845e2638353015bba0fdf161b3eb965f2bca4464e",
          "quantization": "Q4_K_M",
          "license": "Apache-2.0",
          "licenseURL": "https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/LICENSE",
          "chatTemplate": "Embedded Qwen3 ChatML Jinja template (non-thinking 2507 instruct); tool calls as <tool_call> JSON, parsed by llama-server --jinja",
          "runtimeTags": ["b11140"],
          "minimumMemoryGB": 16,
          "contextTokens": 8192
        }
      ]
    }
    """#
}

extension AgentConfiguration {
    /// The configuration's catalog, falling back field by field to the built-in catalog.
    public var effectiveCatalog: ModelCatalog {
        let builtIn = ModelCatalog.builtIn
        guard let spec = modelCatalog else { return builtIn }
        return ModelCatalog(schemaVersion: 1,
                            catalogVersion: spec.artifacts == nil ? builtIn.catalogVersion : "policy",
                            approvedHosts: (spec.approvedHosts ?? builtIn.approvedHosts).map { $0.lowercased() },
                            allowDownloads: spec.allowDownloads ?? builtIn.allowDownloads,
                            artifacts: spec.artifacts ?? builtIn.artifacts)
    }
    /// The approved artifact a managed provider runs, if it references one.
    public func artifact(for provider: ProviderSpec) -> ModelArtifact? {
        guard provider.kind == .managed, let id = provider.runtime?.artifact else { return nil }
        return effectiveCatalog.artifact(id: id)
    }
}
