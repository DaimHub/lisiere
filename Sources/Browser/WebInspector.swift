import AppKit
import WebKit

/// WebKit only enables the Web Inspector through Safari's Develop menu, so these hooks use private API.
/// Every selector is checked first, so the Inspector just stays unavailable if WebKit changes.
@MainActor
enum WebInspector {
    /// Adds Inspect Element to the page's context menu.
    static func enableDeveloperExtras(in configuration: WKWebViewConfiguration) {
        let preferences = configuration.preferences
        guard preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) else { return }
        preferences.setValue(true, forKey: "developerExtrasEnabled")
    }

    /// Opens the Inspector docked in the page, or in its own window if that's where the user last put it.
    static func show(for webView: WKWebView) {
        let inspectorSelector = NSSelectorFromString("_inspector")
        let showSelector = NSSelectorFromString("show")
        guard webView.isInspectable,
              webView.responds(to: inspectorSelector),
              let inspector = webView.perform(inspectorSelector)?.takeUnretainedValue() as? NSObject,
              inspector.responds(to: showSelector) else {
            NSSound.beep()
            return
        }
        inspector.perform(showSelector)
    }
}
