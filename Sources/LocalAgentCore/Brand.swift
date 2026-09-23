import Foundation
public enum Brand {
    private struct Metadata: Decodable {
        let displayName: String
        let version: String
        let bundleIdentifier: String
    }
    private static let metadata: Metadata = {
        // A missing bundled branding resource is a packaging error.
        let appResource = Bundle.main.url(forResource: "Branding", withExtension: "json")
        let cliResource = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources/Branding.json")
        let url = appResource ?? (FileManager.default.fileExists(atPath: cliResource.path)
            ? cliResource : Bundle.module.url(forResource: "Branding", withExtension: "json")!)
        return try! JSONDecoder().decode(Metadata.self, from: Data(contentsOf: url))
    }()
    public static let displayName = metadata.displayName
    // Stable storage identity: changing the display name must not orphan credentials or policies.
    public static let identity = metadata.bundleIdentifier
    public static let version = metadata.version
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(identity)
    }
}
