// swift-tools-version: 6.1
import PackageDescription
let package = Package(
    name: "MinimodeLL",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalAgentCore", targets: ["LocalAgentCore"]),
        .executable(name: "minimodell", targets: ["MinimodeLL"]),
        .executable(name: "minimodell-diagnostics", targets: ["AgentDiagnostics"])
    ],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .target(name: "LocalAgentCore", dependencies: [.product(name: "MCP", package: "swift-sdk")], resources: [.process("Resources")]),
        .executableTarget(name: "MinimodeLL", dependencies: ["LocalAgentCore"]),
        .executableTarget(name: "AgentDiagnostics", dependencies: ["LocalAgentCore"]),
        .testTarget(name: "LocalAgentCoreTests", dependencies: ["LocalAgentCore"])
    ]
)
