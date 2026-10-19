import AppKit
import SwiftUI

/// Window-local drag controllers share only hit testing. Tabs remain in their source until mouse-up.
@MainActor
final class TabDragWindows {
    static let shared = TabDragWindows()
    private struct Entry { weak var controller: TabDragController? }
    private var entries: [Entry] = []

    func register(_ controller: TabDragController) {
        entries.removeAll { $0.controller == nil || $0.controller === controller }
        entries.append(Entry(controller: controller))
    }

    func unregister(_ controller: TabDragController) {
        entries.removeAll { $0.controller == nil || $0.controller === controller }
    }

    func destination(at point: CGPoint, excluding source: TabDragController) -> TabDragController? {
        // AppKit skips our mouse-transparent preview, and respects other apps, menus and sheets.
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return entries.compactMap(\.controller).first {
            $0 !== source && $0.attachedBrowser?.isActiveInWorkspace == true &&
                $0.coordinateView?.window?.windowNumber == number
        }
    }
}

/// A non-interactive screen-space card follows the pointer beyond the source window's clipping bounds.
@MainActor
final class TabDragFloatingPreview {
    let window: NSPanel
    private var content: NSHostingView<AnyView>?
    private var tabID: UUID?
    private var destination: TabPageDrop?

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(tab: BrowserTab, destination: TabPageDrop?, at point: CGPoint, appearance: NSAppearance?) {
        let compact = tab.isPinned && destination != .newWindow && destination != .existingWindow && destination != .unavailableWindow
        let size = CGSize(width: compact ? 68 : 184, height: 56)
        if content == nil || tabID != tab.id || self.destination != destination {
            let root = AnyView(TabDragCard(tab: tab, destination: destination).padding(12)
                .accessibilityHidden(true).transaction { $0.animation = nil })
            if let content { content.rootView = root }
            else {
                let host = NSHostingView(rootView: root)
                content = host
                window.contentView = host
            }
            tabID = tab.id
            self.destination = destination
        }
        window.appearance = appearance
        window.setFrame(Self.frame(at: point, size: size), display: true)
        if !window.isVisible { window.orderFrontRegardless() }
    }

    static func frame(at point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: point.x + 20 - size.width / 2, y: point.y - 20 - size.height / 2,
               width: size.width, height: size.height)
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        content = nil
    }
}
