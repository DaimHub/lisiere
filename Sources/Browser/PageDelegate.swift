import AppKit
import WebKit

/// Handles what a tab's page asks of the browser: new windows, modifier-clicked links, and JavaScript panels.
@MainActor
final class PageDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var tab: BrowserTab?

    /// WebKit reports mouse buttons as a mask, like `NSEvent.pressedMouseButtons`, not as a button number.
    private static let middleButtonMask = 1 << 2

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == Self.middleButtonMask,
           let tab, let browser = tab.browser {
            browser.openChildTab(of: tab, loading: navigationAction.request, select: false)
            return .cancel
        }
        return .allow
    }

    /// Opens pop-ups and `target="_blank"` links as tabs. WebKit loads the page into the returned
    /// web view, which must use the configuration it provides so `window.opener` keeps working.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let tab, let browser = tab.browser else { return nil }
        return browser.openChildTab(of: tab, configuration: configuration, select: true).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab else { return }
        tab.browser?.closeTab(tab.id)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        _ = await present(alert, in: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await present(alert, in: webView) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = makeAlert(message: prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await present(alert, in: webView) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let response = if let window = webView.window {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.urls : nil
    }

    private func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says:" : "\(host) says:"
        alert.informativeText = message
        return alert
    }

    /// Brings the page's tab forward, then shows the panel as a sheet on its window.
    private func present(_ alert: NSAlert, in webView: WKWebView) async -> NSApplication.ModalResponse {
        if let tab { tab.browser?.activeTabID = tab.id }
        if let window = webView.window {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }
}
