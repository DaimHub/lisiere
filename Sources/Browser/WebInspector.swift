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
        detach(inspector, from: webView)
    }

    /// Docked, the Inspector resizes the web view that SwiftUI lays out, and the two keep
    /// overriding each other's frames. A separate window avoids that fight. The Inspector
    /// ignores `detach` until its interface has loaded, so keep asking briefly.
    private static func detach(_ inspector: NSObject, from webView: WKWebView, attempts: Int = 30) {
        let detachSelector = NSSelectorFromString("detach")
        let inspectorViewSelector = NSSelectorFromString("inspectorWebView")
        guard attempts > 0,
              inspector.responds(to: detachSelector),
              inspector.responds(to: inspectorViewSelector) else { return }

        let inspectorView = inspector.perform(inspectorViewSelector)?.takeUnretainedValue() as? NSView
        if let inspectorWindow = inspectorView?.window, inspectorWindow !== webView.window { return }
        if inspectorView?.window != nil {
            inspector.perform(detachSelector)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            detach(inspector, from: webView, attempts: attempts - 1)
        }
    }
}
