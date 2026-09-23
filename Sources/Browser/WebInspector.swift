import AppKit
import WebKit

@MainActor
enum WebInspector {
    static func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let webView = findWebView(in: subview) { return webView }
        }
        return nil
    }

    static func show(for webView: WKWebView) {
        // WebKit has no public API for opening the in-app Inspector.
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let inspectorSelector = NSSelectorFromString("_inspector")
        guard webView.isInspectable,
              webView.responds(to: inspectorSelector),
              let inspector = webView.perform(inspectorSelector)?.takeUnretainedValue() as? NSObject else {
            return
        }

        let showSelector = NSSelectorFromString("show")
        guard inspector.responds(to: showSelector) else { return }
        inspector.perform(showSelector)
    }
}
