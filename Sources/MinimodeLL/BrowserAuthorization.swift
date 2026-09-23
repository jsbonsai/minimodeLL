import AppKit
import AuthenticationServices
import MCP
import LocalAgentCore

@MainActor
final class BrowserAuthorization: NSObject, OAuthAuthorizationDelegate, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        guard url.scheme == "https" else { throw AgentError.rejected("Sign-in requires HTTPS.") }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Brand.identity) { [weak self] callback, error in
                    Task { @MainActor in
                        if let error { self?.finish(.failure(error)) }
                        else if let callback, callback.scheme == Brand.identity, callback.host == "oauth-callback" {
                            self?.finish(.success(callback))
                        } else { self?.finish(.failure(AgentError.rejected("Invalid authorization callback."))) }
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                if !session.start() { finish(.failure(AgentError.rejected("Unable to start sign-in."))) }
            }
        } onCancel: {
            Task { @MainActor in
                self.session?.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
    }
    private func finish(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        pending?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
