> Historical planning input. See README.md and docs/architecture.md for current decisions and implementation status. Code samples below are not production instructions.

# PRD Addendum: Technical Specifications & Security Architecture

**Document Title:** Technical Addendum — Enterprise Local AI Agent (macOS Menu Bar)
**Parent Document:** `PRD_Enterprise_Local_AI_Menubar_App.md`
**Target Audience:** Lead macOS / Swift Engineer, AI Systems Architect

---

## 1. Core Architecture & Protocol Integrations

### 1.1 LiteLLM Proxy & OpenAI Compatibility
The application natively interacts with `llama-server` via its OpenAI-compatible REST API on local loopback (`http://127.0.0.1:9931/v1`).

* **Dual-Mode Routing:**
  * **Local Mode (Default):** Queries execute against local `llama-server` instances.
  * **LiteLLM Gateway Fallback (Optional):** If a model query exceeds local hardware limits or requires a cloud-based model, the Swift orchestrator routes the request directly to an enterprise LiteLLM Proxy URL (`https://litellm.company.com/v1/chat/completions`) using standard Bearer token authentication.
* **Compatibility Layer:** The internal request format matches standard OpenAI JSON payloads (`/v1/chat/completions`), ensuring zero code changes when switching between `llama-server` and `LiteLLM`.

---

### 1.2 Model Context Protocol (MCP) Swift SDK
The application MUST use the official Linux Foundation-backed **`modelcontextprotocol/swift-sdk`** via Swift Package Manager (SPM).

* **SPM Dependency Package:** `https://github.com/modelcontextprotocol/swift-sdk.git`
* **Transport Protocol:** Server-Sent Events (SSE) over HTTPS (`SSEClientTransport`).

#### Native Swift MCP Execution Pattern
```swift
import Foundation
import MCP

actor MCPManager {
    private var client: Client?

    func initializeConnection(serverURL: URL, authToken: String) async throws -> [MCP.Tool] {
        let customHeaders = ["Authorization": "Bearer \(authToken)"]
        let transport = SSEClientTransport(url: serverURL, headers: customHeaders)

        let mcpClient = Client(name: "EnterpriseLocalAI-Mac", version: "1.0.0")
        try await mcpClient.connect(transport: transport)

        let (tools, _) = try await mcpClient.listTools()
        self.client = mcpClient
        return tools
    }

    func executeTool(name: String, arguments: [String: AnyCodable]) async throws -> CallToolResult {
        guard let client = client else { throw MCPError.notConnected }
        return try await client.callTool(name: name, arguments: arguments)
    }
}
```

---

### 1.3 Modular Abstracted Configuration (`config.yaml` / `config.json`)
App settings are parsed at boot from `~/Library/Application Support/CompanyLocalAI/config.yaml` using the `Yams` Swift library or standard `Codable` JSON parsing.

```yaml
version: "1.0"
app:
  menu_bar_title: "Company AI"
  auto_start_at_login: true

inference:
  default_ctx_size: 8192
  gpu_layers: 99 # Offload all layers to Apple Silicon Metal
  idle_timeout_minutes: 15 # Unload GGUF from VRAM after inactivity

mcp_servers:
  - id: "mcp-jira"
    name: "Enterprise Jira Agent"
    sse_url: "https://mcp-jira.internal.company.com/sse"
    auth_provider: "okta"
    client_id: "mcp_jira_mac_client"

security:
  enforce_tls_pinning: true
  allow_unapproved_models: false
  oslog_audit_enabled: true
```

---

## 2. Hardened Enterprise Security & Isolation

### 2.1 Zero-Knowledge Token Isolation (macOS Keychain)
OAuth tokens (`access_token`, `refresh_token`) and sensitive credentials MUST NEVER be written to flat files (`.yaml`, `.json`, `.plist`).

* **Keychain Service:** `Security.framework` (`SecItemAdd`, `SecItemCopyMatching`)
* **Access Control Class:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
* **Hardware Protection:** Tokens are tied to the Mac's Secure Enclave / Secure System Store and excluded from iCloud Keychain sync or Time Machine backups.

---

### 2.2 App Sandboxing & Hardened Runtime

To prevent unauthorized local processes or compromised scripts from inspecting application memory or accessing app files:

1. **App Sandbox:** Enable in Xcode Entitlements (`com.apple.security.app-sandbox = true`).
2. **Network Entitlements:**
   * `com.apple.security.network.client` (Required for remote MCP/OAuth endpoints).
   * `com.apple.security.network.server` (Required to bind `llama-server` to local loopback `127.0.0.1`).
3. **Hardened Runtime Options:** Enable `--options=runtime` during build. Disallow `DYLD_INSERT_LIBRARIES` to stop code injection attacks.

---

### 2.3 Subprocess Isolation (`llama-server`)
Execute `llama-server` in an isolated environment using macOS Sandbox Profiles or an XPC Service architecture.

* **Loopback Lockdown:** Force `llama-server` to listen ONLY on `127.0.0.1` (`--host 127.0.0.1`).
* **Path Constraint:** `llama-server` is spawned as a child process with read-only file access restricted strictly to `/Library/Application Support/CompanyLocalAI/Models/`.

---

## 3. Reliability, Proactive OOM & Quality-of-Life (QoL)

### 3.1 Proactive Memory (OOM) Protection
Because Apple Silicon uses Unified Memory shared between CPU and GPU, attempting to load a model larger than available RAM causes severe swapping or system instability.

#### Pre-Flight Memory Check Engine
Before initializing or switching models, the app queries Darwin system memory APIs:

```swift
import Darwin

struct SystemMemoryGuard {
    static func getFreeMemoryGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let freePages = UInt64(stats.free_count + stats.inactive_count)
        return Double(freePages * pageSize) / 1024.0 / 1024.0 / 1024.0
    }

    static func validateModelLoad(requiredRAMGB: Double) -> (allowed: Bool, warningMessage: String?) {
        let availableGB = getFreeMemoryGB()
        if availableGB < requiredRAMGB {
            let msg = "Model requires ~\(requiredRAMGB) GB free RAM, but only \(String(format: "%.1f", availableGB)) GB is available. Please close heavy applications (e.g., Xcode, Chrome) before loading."
            return (false, msg)
        }
        return (true, nil)
    }
}
```

---

### 3.2 Enterprise Audit Telemetry & Observability (`OSLog`)
Avoid standard `print()` statements. Use Apple's unified logging system (`OSLog`) so logs stream directly into **Console.app** and can be ingested by Enterprise EDRs (CrowdStrike, Jamf Protect).

```swift
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.company.localai"

    static let inference = Logger(subsystem: subsystem, category: "Inference")
    static let mcp = Logger(subsystem: subsystem, category: "MCPTools")
    static let security = Logger(subsystem: subsystem, category: "Security")
}

// Audit Trail Example
Logger.mcp.notice("[AUDIT] User executed MCP Tool: 'jira_create_issue' | Server: 'mcp-jira'")
Logger.security.info("[AUTH] OAuth token successfully refreshed via Keychain.")
```

---

## 4. UI/UX Design System (Native macOS Aesthetics)

To create a clean, viral-ready native macOS UI:

1. **Vibrant Materials:** Use SwiftUI `.background(.ultraThinMaterial)` for popovers to achieve modern translucent glassmorphism matching macOS Sequoia/Sonoma standards.
2. **Fluid Animations:** Apply `.animation(.smooth, value: isProcessing)` during state transitions.
3. **Menu Bar Status Indicators:**
   * 🟢 **Green Dot:** Model loaded & idle.
   * 🔵 **Pulsing Blue Dot:** Inferring / Streaming response.
   * 🟠 **Orange Dot:** Executing remote MCP tool.
   * 🔴 **Red Dot:** System low on memory or MCP authentication failed.
