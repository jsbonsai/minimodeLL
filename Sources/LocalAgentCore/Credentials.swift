import Foundation
import Security

public enum CredentialStore {
    public static func read(account: String) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Brand.identity, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw AgentError.rejected("Keychain credential unavailable (\(status)).")
        }
        return token
    }
    public static func save(_ token: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Brand.identity, kSecAttrAccount as String: account]
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrSynchronizable as String] = false
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AgentError.rejected("Unable to save credential (\(added)).") }
        } else if status != errSecSuccess { throw AgentError.rejected("Unable to update credential (\(status)).") }
    }
}

import MCP
import OSLog
public final class KeychainOAuthStorage: TokenStorage, Sendable {
    private let account: String
    public init(account: String) { self.account = account }
    public func save(_ token: OAuthAccessToken) {
        do {
            let data = try JSONEncoder().encode(token)
            try CredentialStore.save(String(decoding: data, as: UTF8.self), account: account)
        } catch {
            Logger(subsystem: Brand.identity, category: "credentials").error("OAuth token persistence failed.")
        }
    }
    public func load() -> OAuthAccessToken? {
        guard let value = try? CredentialStore.read(account: account) else { return nil }
        return try? JSONDecoder().decode(OAuthAccessToken.self, from: Data(value.utf8))
    }
    public func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Brand.identity, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
