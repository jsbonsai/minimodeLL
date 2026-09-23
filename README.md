# minimodeLL

A native macOS menu bar assistant for small workplace tasks, with local inference, approved model catalogs, and remote MCP tools. Organizations can add managed policy through Jamf or Kandji; individual users configure the same app themselves.

**Status: developer preview.** The app and policy engine build on Apple Silicon. Unit tests use deterministic fake providers and tools. Live model quality, enterprise OAuth interoperability, notarization, and MDM behavior still require validation before production use.

## What works today

- SwiftUI task window, menu bar entry, settings, cancellation, and explicit tool approvals.
- OpenAI-compatible local inference and LiteLLM gateway configuration. No automatic cloud fallback.
- Official MCP Swift SDK, pinned at 0.12.1: Streamable HTTP, tool discovery, native browser OAuth with PKCE, and Keychain token storage.
- Approved model stubs and explicit per-server tool allowlists; one active task and one tool call per step.
- Request, output, context, tool-step, tool-result, and time budgets. Unknown tools and invalid arguments are blocked.
- JSONL audit metadata and OSLog events with bounded local retention; no prompt, response, argument, or credential logging.
- Optional forced MDM policy, profile generator, hardware inventory script, and a diagnostics executable.
- Sandboxed `.app` packaging plus DMG and PKG build scripts.

## Build and open

Requires an Apple Silicon Mac, macOS 14+, Xcode 16.4 / Swift 6.1 or newer, and Git. No Python or Node runtime is required by the app. Packaging/profile tooling uses the Python shipped with Xcode command line tools.

```sh
swift test
scripts/package-app.sh
open build/minimodeLL.app
```

The development app is ad-hoc signed and sandboxed. Gatekeeper distribution requires Developer ID signing and notarization. `swift run minimodell` is useful for UI development but does **not** exercise the packaged sandbox.

### Preview the UI without a model

Run `python3 scripts/mock-inference.py`, then submit a short request in the app. This explicit fixture returns a labeled canned response and makes no outbound requests. Stop it with Ctrl-C before starting a real inference server on the same port.

### Connect inference

This preview connects to an existing `llama-server`; it does not yet bundle or download the runtime or models. Start a tool-capable GGUF with a tested template and bounded context, for example:

```sh
llama-server --model /path/to/approved.gguf --alias local-model \
  --host 127.0.0.1 --port 9931 --ctx-size 8192 --parallel 1 --jinja
```

This example exposes inference to other local processes. For authenticated local inference, use llama-server's API-key configuration, add a `credentialAccount` to the local provider, and save the matching token in the app's Credentials tab. Enterprise releases must ship a pinned, signed runtime with app-controlled authentication and lifecycle.

The starter configuration expects the alias `local-model`. Open Settings → Configuration to edit it. A model stub is an approved provider model ID plus its context and memory requirements; it is not a downloaded model or proof of model quality.

For LiteLLM, add an HTTPS provider and a model whose `model` value matches the gateway alias. Save the gateway token in Credentials under the configured `credentialAccount`. The UI labels cloud inference before submission. Tool results are sent to the selected provider, so select cloud models only when your data policy permits it.

### Connect tools

Start from `Config/enterprise.example.json`. Its `.example.com` URLs are placeholders and its tool allowlists are empty intentionally. Set real HTTPS Streamable HTTP endpoints and add exact tool names, for example:

```json
"tools": [{"name": "your_actual_search_tool", "requiresConfirmation": true}]
```

Set confirmation to false only for operations you have reviewed as safe to run automatically. Tool annotations from servers do not grant approval. Tools with unsupported JSON Schema constraints fail closed; see `docs/architecture.md` for the supported subset. Keep the selected tool set small so schemas fit the context budget.

Register a native public OAuth client with redirect URI `org.minimodell.agent://oauth-callback`, or configure an explicit bearer-token account. Do not embed a web application's OAuth client secret. Existing LibreChat OAuth registrations may need a separate native client registration. The app starts browser sign-in on the first authenticated task. Legacy HTTP+SSE endpoints, custom provider OAuth extensions, and enterprise IdP flows require interoperability work.

## Policy and deployment

The app resolves one effective policy in this order:

1. Forced `PolicyJSON` in the `org.minimodell.agent` preference domain, when delivered by MDM.
2. User `config.json` in the app's Application Support directory.
3. Bundled starter defaults.

Invalid forced policy blocks requests. Managed policy is a complete replacement; user settings cannot extend the managed model or tool allowlists. Policy is captured at task start; emergency revocation of an action already in flight must happen at the service or identity provider.

```sh
swift run minimodell-diagnostics --config Config/enterprise.example.json
scripts/make-profile.py Config/enterprise.example.json build/minimodell.mobileconfig
```

Upload the generated configuration profile to Jamf and scope it independently of the application PKG. This project has no dependency on the Jamf API. See [deployment](docs/deployment.md), the [Jamf sandbox test plan](docs/jamf-test-plan.md), [Kandji best-effort guide](docs/kandji.md), and [validation](docs/validation.md). Kandji has no tenant validation yet; Jamf validation is planned with a scoped sandbox.

## Branding

Edit `Sources/LocalAgentCore/Resources/Branding.json` and rebuild to change the display name and version. All user-facing app names and package names use it. Keep `bundleIdentifier` stable once deployed: it anchors policy, OAuth callbacks, storage, and Keychain records. A distribution fork should establish its identifier before enrolling users.

## Continuing development

Start with [AGENTS.md](AGENTS.md) and the [current handoff](docs/handoff.md). The [documentation map](docs/README.md) links the detailed implementation state, configuration reference, architecture decisions, code map, ordered backlog and session records. Material changes include documentation updates so another contributor can resume without the original chat.

## Architecture and project status

`LocalAgentCore` contains configuration, policy, inference, MCP, credentials, audit, and task orchestration. `MinimodeLL` contains the macOS UI and browser authentication. `AgentDiagnostics` shares the configuration validator. Packaging and MDM integrations live outside the application core.

See [architecture](docs/architecture.md), [security](SECURITY.md), [roadmap](docs/roadmap.md), and [contributing](CONTRIBUTING.md). The original PRDs are historical inputs; the current architecture and implementation take precedence where they differ.

## License

MIT. Dependency and model licenses remain separate. No model weights or inference runtime are redistributed in this preview.
