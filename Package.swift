// swift-tools-version: 6.1
import PackageDescription
let package = Package(
    name: "MinimodeLL",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalAgentCore", targets: ["LocalAgentCore"]),
        .executable(name: "minimodell", targets: ["MinimodeLL"]),
        .executable(name: "minimodell-diagnostics", targets: ["AgentDiagnostics"]),
        .executable(name: "minimodell-runtime-guard", targets: ["RuntimeGuard"])
    ],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .target(name: "LocalAgentCore", dependencies: [.product(name: "MCP", package: "swift-sdk")], resources: [.process("Resources")]),
        .executableTarget(name: "MinimodeLL", dependencies: ["LocalAgentCore"], resources: [.copy("Resources/BrandAssets")]),
        .executableTarget(name: "AgentDiagnostics", dependencies: ["LocalAgentCore"]),
        .executableTarget(name: "RuntimeGuard"),
        .testTarget(name: "LocalAgentCoreTests", dependencies: ["LocalAgentCore"]),
        .testTarget(name: "MinimodeLLTests", dependencies: ["MinimodeLL"])
    ]
)
