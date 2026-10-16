import AuthenticationServices
import Observation
import Security

/// Passkeys and security keys in web pages. WebKit only runs WebAuthn for any site in an app Apple has granted its
/// web browser passkey entitlement, which builds get with BROWSER_PASSKEYS=YES (see RELEASING.md). WebKit then
/// handles the requests itself; the browser asks once for the user's permission to use their passkeys.
@MainActor
@Observable
final class Passkeys {
    static let shared = Passkeys()
    static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    let isEntitled: Bool
    private(set) var authorizationState: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState
    @ObservationIgnored private let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

    init() {
        isEntitled = Self.hasEntitlement()
        authorizationState = isEntitled ? manager.authorizationStateForPlatformCredentials : .denied
    }

    /// Reads the signed entitlements, so a build without the entitlement never asks for passkeys.
    static func hasEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) as? Bool == true
    }

    /// Asks the user, once, to let the browser use their passkeys.
    func requestAuthorizationIfNeeded() {
        guard isEntitled, authorizationState == .notDetermined else { return }
        Task {
            authorizationState = await manager.requestAuthorizationForPublicKeyCredentials()
        }
    }
}
