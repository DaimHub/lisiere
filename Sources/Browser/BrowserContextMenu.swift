import AppKit
import SwiftUI

/// Shared action data keeps native and accessibility context menus in sync.
@MainActor
struct BrowserContextAction {
    var title: String
    var icon: BrowserIcon?
    var isEnabled = true
    var role: ButtonRole? = nil
    var children: [BrowserContextAction]? = nil
    var action: @MainActor () -> Void = {}
    static var separator: Self { Self(title: "", icon: nil) }
}

extension View {
    @MainActor
    func browserContextMenu(excludingTop: CGFloat = 0, _ actions: @escaping () -> [BrowserContextAction]) -> some View {
        return contextMenu {
            DeferredBrowserMenuContent(actions: actions)
        }
        .overlay { BrowserContextMenuOverlay(actions: actions, excludingTop: excludingTop, primaryClick: false) }
    }
    @MainActor
    func browserMenu(_ actions: @escaping () -> [BrowserContextAction]) -> some View {
        overlay { BrowserContextMenuOverlay(actions: actions, excludingTop: 0, primaryClick: true) }
    }

}

/// Build action lists when SwiftUI needs the menu, not during every tab/layout update.
/// The AppKit overlay also calls the same factory at opening, so both paths see live state.
private struct DeferredBrowserMenuContent: View {
    let actions: () -> [BrowserContextAction]
    var body: some View { BrowserMenuContent(actions: actions()) }
}

private struct BrowserContextMenuOverlay: NSViewRepresentable {
    var actions: () -> [BrowserContextAction]
    var excludingTop: CGFloat
    var primaryClick: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> ContextView { ContextView(actions: actions, excludingTop: excludingTop, primaryClick: primaryClick) }
    func updateNSView(_ view: ContextView, context: Context) {
        view.actions = actions
        view.excludingTop = excludingTop
        view.isMenuEnabled = isEnabled
    }

    final class ContextView: NSView {
        var actions: () -> [BrowserContextAction]
        var excludingTop: CGFloat
        let primaryClick: Bool
        var isMenuEnabled = true
        override var isFlipped: Bool { true }
        init(actions: @escaping () -> [BrowserContextAction], excludingTop: CGFloat, primaryClick: Bool) {
            self.actions = actions
            self.excludingTop = excludingTop
            self.primaryClick = primaryClick
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isMenuEnabled, let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && (primaryClick || event.modifierFlags.contains(.control))) else { return nil }
            // A sidebar background must not cover the menus of its tab rows.
            guard convert(point, from: superview).y >= excludingTop else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { showMenu(event) }
        override func mouseDown(with event: NSEvent) { showMenu(event) }
        private func showMenu(_ event: NSEvent) {
            let items = actions()
            guard !items.isEmpty else { return }
            let menu = BrowserContextAction.menu(items)
            if primaryClick && event.type == .leftMouseDown && !event.modifierFlags.contains(.control) {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
            } else {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }
    }
}

extension BrowserContextAction {
    @MainActor
    static func menu(_ actions: [Self]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            if let icon = action.icon {
                let item = BrowserContextMenuItem(title: action.title, action: action.action)
                item.image = icon.nsImage()
                BrowserMenuImages.keepImageVisible(item)
                item.isEnabled = action.isEnabled
                if let children = action.children { item.submenu = Self.menu(children) }
                menu.addItem(item)
            } else if action.title.isEmpty { menu.addItem(.separator()) }
            else {
                let heading = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                menu.addItem(heading)
            }
        }
        return menu
    }
}

@MainActor
private final class BrowserContextMenuItem: NSMenuItem {
    let handler: @MainActor () -> Void
    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

/// SwiftUI retains keyboard and accessibility access to the same action data.
struct BrowserMenuContent: View {
    let actions: [BrowserContextAction]
    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
            if let icon = item.icon {
                if let children = item.children {
                    Menu(item.title, browserIcon: icon) { BrowserMenuContent(actions: children) }
                        .disabled(!item.isEnabled)
                } else {
                    Button(item.title, browserIcon: icon, role: item.role, action: item.action)
                        .disabled(!item.isEnabled)
                }
            } else if item.title.isEmpty { Divider() }
            else { Text(item.title) }
        }
    }
}
