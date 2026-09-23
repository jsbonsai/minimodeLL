> Historical planning input. See README.md and docs/architecture.md for current decisions and implementation status. Code samples below are not production instructions.

# Product Requirement Document (PRD)
## Enterprise Local AI Agent — macOS Menu Bar App

**Project Title:** Enterprise Local AI (Working Title: *minimodel*)
**Core Objective:** Build a native, lightweight, highly secure macOS menu bar app that brings managed local LLM inference and enterprise HTTP/SSE MCP (Model Context Protocol) tool execution to corporate Mac endpoints via Jamf deployment.

---

### 1. Architectural Vision & Foundation

#### Why Fork `ggml-org/Llama-macOS`?
Rather than building from scratch or using heavyweight Electron/Node wrappers, we will fork **`ggml-org/Llama-macOS`**:
* **100% Native Swift & SwiftUI:** Keeps the binary ultra-light (~5MB to 15MB base app size) and delivers a pure macOS native look and feel.
* **Built-in `llama-server` Management:** Handles launching, lifecycle monitoring, idle auto-unloading, Metal GPU acceleration, and CPU thread configuration automatically.
* **Low Footprint:** Consumes minimal RAM when idle; leaves maximum Unified Memory for the local GGUF models.
* **Deployment Friendly:** Builds cleanly into standard `.app` / `.pkg` bundles that pass macOS Gatekeeper, notarization, and TCC security profiles easily via Jamf.

---

### 2. Key Features & Specifications

#### 2.1 Native macOS Menu Bar UI (SwiftUI)
* **Status Bar Item:** Small, non-intrusive icon in the macOS menu bar displaying system status (Idle, Inferring, Downloading, Tool Executing).
* **Popover Menu:** Native SwiftUI popover providing:
  * **Quick Chat Interface:** Glassmorphism/Vibrancy UI using `.background(.ultraThinMaterial)`.
  * **Model Selector Dropdown:** Curated list filtered by system RAM tier.
  * **MCP Status Indicators:** Shows green/yellow/red status for active remote MCP tool connections.
  * **System Resources Indicator:** Minimal CPU/RAM usage bar.

#### 2.2 Dynamic Hardware-Tiered Model Whitelisting
To eliminate end-user confusion and prevent Out-Of-Memory (OOM) crashes:
* **Hardware Detection:** Query system Unified Memory using `ProcessInfo.processInfo.physicalMemory`.
* **Hardcoded / Remote Tier Mapping:**
  * **8 GB - 16 GB RAM:** Micro/Small models (e.g., `Llama-3.2-3B-Instruct`, `Qwen2.5-3B-Instruct`).
  * **18 GB - 36 GB RAM:** Medium models (e.g., `Llama-3.1-8B-Instruct`, `Mistral-7B-Instruct`, `Qwen2.5-14B`).
  * **48 GB - 128 GB+ RAM:** Large models (e.g., `Qwen2.5-32B`, `Command-R`, `Llama-3.3-70B`).
* **Source Enforcement:** Disable arbitrary Hugging Face searches; force downloading only from IT-approved internal S3/CDN endpoints or pre-selected Hugging Face mirrors.

#### 2.3 Global Enterprise System Prompt & Security Guardrails
* **Enforced Prompt Injection:** Hardcode or lock via `defaults write` an immutable system prompt layer (e.g., corporate policies, tone, output constraints).
* **Layered Injection:**
  1. *Corporate Policy Layer* (Locked down by Jamf configuration).
  2. *MCP Tool Integration Layer* (Automatically generated based on connected tools).
  3. *User Persona / Custom Instructions* (Optional user preference).

#### 2.4 Pure Swift MCP Client & OAuth 2.0/2.1 Engine (Strategy A)
* **Native OAuth via `ASWebAuthenticationSession`:**
  * Pops up system browser/IDP login window (Okta, Entra ID, Ping) for authenticating against remote corporate MCP servers.
  * Handled completely natively without third-party browser hacks.
* **Keychain Storage (`Security.framework`):**
  * Securely stores OAuth Access/Refresh tokens in the user's macOS Keychain.
* **Streamable HTTP/SSE MCP Client:**
  * Connects to remote HTTP/SSE Model Context Protocol servers over TLS.
  * Parses tool JSON-schemas natively in Swift.
  * Automatically injects available tools into the `llama-server` request payloads (`/v1/chat/completions`).
  * **Agent Loop:** If `llama-server` emits a `tool_calls` response, the app intercepts it, executes the HTTP request against the remote MCP endpoint using the stored OAuth token, feeds the tool output back into `llama-server`, and streams the final answer to the user UI.

---

### 3. Application Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                        LlamaBar Enterprise                             │
│                         (Native Swift App)                             │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    SwiftUI Menu Bar Popover                      │  │
│  └──────────────────────────────────┬───────────────────────────────┘  │
│                                     │                                  │
│  ┌──────────────────────────────────▼───────────────────────────────┐  │
│  │               Native Swift Orchestrator & Agent Loop             │  │
│  │  - System Hardware Tier Detector (sysctl)                        │  │
│  │  - Hardcoded System Prompt Manager                               │  │
│  │  - Keychain Token Manager (Security.framework)                   │  │
│  └──────────────────┬──────────────────────────────┬────────────────┘  │
│                     │                              │                   │
│  ┌──────────────────▼──────────────┐    ┌──────────▼────────────────┐  │
│  │    ASWebAuthenticationSession   │    │  Streamable MCP Client    │  │
│  │     (Corporate IDP OAuth)       │    │     (Swift HTTP / SSE)    │  │
│  └─────────────────────────────────┘    └──────────┬────────────────┘  │
└─────────────────────┬──────────────────────────────┼───────────────────┘
                      │                              │
                      ▼                              ▼
          ┌───────────────────────┐      ┌────────────────────────┐
          │     llama-server      │      │ Remote Enterprise MCP  │
          │  (Local Apple Metal)  │      │  Server (OAuth/Tools)  │
          └───────────────────────┘      └────────────────────────┘
```

---

### 4. Implementation Steps & Code Modifications

#### Step 1: Model Catalog Hardcoding (`ModelCatalog.swift`)
Modify the model fetcher to read physical memory and restrict sources.

```swift
import Foundation

struct ApprovedModel: Identifiable, Codable {
    let id: String
    let name: String
    let downloadURL: URL
    let minRAMGB: Int
    let fileName: String
}

class ModelManager: ObservableObject {
    @Published var availableModels: [ApprovedModel] = []

    init() {
        filterModelsForHardware()
    }

    func filterModelsForHardware() {
        let physicalRAMGB = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024)

        let masterCatalog: [ApprovedModel] = [
            ApprovedModel(id: "qwen-3b", name: "Qwen 2.5 3B (Fast)", downloadURL: URL(string: "https://internal-cdn.company.com/models/qwen2.5-3b-instruct-q4_k_m.gguf")!, minRAMGB: 8, fileName: "qwen2.5-3b-instruct-q4_k_m.gguf"),
            ApprovedModel(id: "llama-8b", name: "Llama 3.1 8B (Balanced)", downloadURL: URL(string: "https://internal-cdn.company.com/models/llama-3.1-8b-instruct-q4_k_m.gguf")!, minRAMGB: 16, fileName: "llama-3.1-8b-instruct-q4_k_m.gguf"),
            ApprovedModel(id: "qwen-32b", name: "Qwen 2.5 32B (Pro)", downloadURL: URL(string: "https://internal-cdn.company.com/models/qwen2.5-32b-instruct-q4_k_m.gguf")!, minRAMGB: 36, fileName: "qwen2.5-32b-instruct-q4_k_m.gguf")
        ]

        // Filter catalog based on user's Mac RAM
        self.availableModels = masterCatalog.filter { $0.minRAMGB <= physicalRAMGB }
    }
}
```

#### Step 2: Native OAuth Session Manager (`OAuthManager.swift`)

```swift
import Foundation
import AuthenticationServices
import Security

class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated = false
    private let clientID = "corporate-llama-app"
    private let authURL = URL(string: "https://auth.company.com/oauth2/v1/authorize")!
    private let tokenURL = URL(string: "https://auth.company.com/oauth2/v1/token")!
    private let callbackURLScheme = "com.company.llamabar"

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    func authenticate() {
        let authSession = ASWebAuthenticationSession(
            url: buildAuthURL(),
            callbackURLScheme: callbackURLScheme
        ) { callbackURL, error in
            guard error == nil, let callbackURL = callbackURL else { return }
            self.handleOAuthCallback(url: callbackURL)
        }

        authSession.presentationContextProvider = self
        authSession.start()
    }

    private func buildAuthURL() -> URL {
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "\(callbackURLScheme)://oauth-callback"),
            URLQueryItem(name: "scope", value: "mcp:access offline_access")
        ]
        return components.url!
    }

    private func handleOAuthCallback(url: URL) {
        // Extract authorization code and exchange for Bearer Token
        // Store resulting token securely in Keychain via KeychainServices wrapper
    }
}
```

---

### 5. Packaging & Jamf Deployment Workflow

#### 5.1 Directory Layout for Pre-seeded Models
To prevent network congestion during rollout, build a Jamf PKG payload that places standard low-footprint models in shared system folders:
* Target Directory: `/Library/Application Support/CompanyLocalAI/Models/`
* Permissions: `755` owned by `root:wheel`

#### 5.2 Xcode Signing & Notarization Commands
1. **Archive the App:**
   ```bash
   xcodebuild -workspace LlamaBar.xcworkspace -scheme LlamaBar -configuration Release archive -archivePath ./build/LlamaBar.xcarchive
   ```
2. **Export with Developer ID:**
   ```bash
   xcodebuild -exportArchive -archivePath ./build/LlamaBar.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath ./build/Export
   ```
3. **Notarize with Apple:**
   ```bash
   xcrun notarytool submit ./build/Export/LlamaBar.pkg --keychain-profile "AC_NOTARIZE_PROFILE" --wait
   ```
4. **Staple Ticket:**
   ```bash
   xcrun stapler staple ./build/Export/LlamaBar.pkg
   ```

#### 5.3 Jamf Post-Install Configuration Script (`postinstall.sh`)

```bash
#!/bin/bash
# Jamf Post-Install Script for LlamaBar Enterprise

LOG_FILE="/var/log/llamabar_install.log"
exec >> "$LOG_FILE" 2>&1

echo "Starting LlamaBar Enterprise Post-Install Configuration..."

# 1. Ensure Model Directory exists
MODEL_DIR="/Library/Application Support/CompanyLocalAI/Models"
mkdir -p "$MODEL_DIR"
chmod 777 "$MODEL_DIR"

# 2. Write System Defaults
# Lock down default configuration for logged-in user
CURRENT_USER=$(stat -f "%Su" /dev/console)

if [ "$CURRENT_USER" != "root" ]; then
    USER_ID=$(id -u "$CURRENT_USER")

    # Pre-configure app defaults
    launchctl asuser "$USER_ID" sudo -u "$CURRENT_USER" defaults write com.company.llamabar EnforceSystemPrompt -bool true
    launchctl asuser "$USER_ID" sudo -u "$CURRENT_USER" defaults write com.company.llamabar SystemPrompt -string "You are an authorized enterprise AI assistant. Treat all internal company data confidentially."
    launchctl asuser "$USER_ID" sudo -u "$CURRENT_USER" defaults write com.company.llamabar MCPServerURL -string "https://mcp.company.com/sse"
    launchctl asuser "$USER_ID" sudo -u "$CURRENT_USER" defaults write com.company.llamabar ModelFolderPath -string "$MODEL_DIR"

    echo "Configuration written successfully for user: $CURRENT_USER"
fi

exit 0
```

---

### 6. Summary of Key Advantages

1. **Native UI & UX:** Delivers a smooth macOS native experience (lightweight menu bar popover, low memory footprint, system dark/light mode support).
2. **Zero API Cost for Inference:** Offloads token generation to Apple Silicon GPUs (M1/M2/M3/M4) locally while retaining central control over tool execution.
3. **Enterprise Compliance:** Features hardcoded model options, strict system prompts, OAuth authentication via corporate IDP, and secure Keychain storage for credentials.
4. **Simple Deployment:** Packaged as a standard `.pkg` installer that Jamf admins can distribute instantly across the Mac fleet.
