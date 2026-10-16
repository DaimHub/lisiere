import AppKit
import SwiftUI

enum BrowserChrome {
    /// Height of the row that holds the window controls and tabs.
    static let tabRowHeight: CGFloat = 40
    static let tabHeight: CGFloat = 30
    static let navigationBarHeight: CGFloat = 46
    static let sidebarWidth: CGFloat = 236
    static let sidebarTabHeight: CGFloat = 32
    /// Inset shared by the navigation bar and the page, so their edges line up.
    static let edgeInset: CGFloat = 8

    static let windowButtonSize: CGFloat = 14
    static let windowButtonSpacing: CGFloat = 23

    /// Height of the top row the window controls are centered in for a tab layout.
    static func titlebarHeight(for layout: TabLayout) -> CGFloat {
        layout == .vertical ? navigationBarHeight : tabRowHeight
    }

    /// Matches the vertical inset so the window controls sit equally far from the top and left edges.
    static func windowButtonLeading(titlebarHeight: CGFloat) -> CGFloat {
        (titlebarHeight - windowButtonSize) / 2
    }

    static func windowButtonsTrailing(titlebarHeight: CGFloat) -> CGFloat {
        windowButtonLeading(titlebarHeight: titlebarHeight) + windowButtonSpacing * 2 + windowButtonSize
    }
}

enum TabLayout: String, CaseIterable {
    case horizontal
    case vertical

    static let storageKey = "tabLayout"

    var toggled: TabLayout { self == .vertical ? .horizontal : .vertical }
}

/// Keeps the window controls centered in the tab row, which is taller than the default title bar, and reports
/// when the user closes the window.
struct WindowChromeConfigurator: NSViewRepresentable {
    let titlebarHeight: CGFloat
    @Binding var isFullScreen: Bool
    var onClose: () -> Void = {}

    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.onFullScreenChange = { isFullScreen = $0 }
        view.onClose = onClose
        view.titlebarHeight = titlebarHeight
    }
}

final class WindowChromeView: NSView {
    var onFullScreenChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var titlebarHeight = BrowserChrome.tabRowHeight {
        didSet {
            if titlebarHeight != oldValue { layoutWindowButtons() }
        }
    }
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }

        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeScreenNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutWindowButtons() }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClose?() }
        })
        DispatchQueue.main.async { [weak self] in self?.layoutWindowButtons() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func layoutWindowButtons() {
        guard let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if let onFullScreenChange {
            DispatchQueue.main.async { onFullScreenChange(isFullScreen) }
        }

        guard !isFullScreen,
              let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview,
              let titlebarContainer = titlebarView.superview else { return }

        let height = titlebarHeight
        let containerFrame = NSRect(x: titlebarContainer.frame.minX,
                                    y: window.frame.height - height,
                                    width: titlebarContainer.frame.width,
                                    height: height)
        if titlebarContainer.frame != containerFrame {
            titlebarContainer.frame = containerFrame
        }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttonTypes.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let origin = NSPoint(
                x: BrowserChrome.windowButtonLeading(titlebarHeight: height)
                    + CGFloat(index) * BrowserChrome.windowButtonSpacing,
                y: ((titlebarView.bounds.height - button.frame.height) / 2).rounded()
            )
            if button.frame.origin != origin {
                button.setFrameOrigin(origin)
            }
        }
    }
}
