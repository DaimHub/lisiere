import AppKit
import SwiftUI

/// Native popup images keep their template tint for both mouse and keyboard selection.
/// SwiftUI Picker rasterizes custom label images before the menu applies its appearance.
struct BrowserIconPicker<Value: Hashable>: NSViewRepresentable {
    struct Option: Equatable {
        let value: Value
        let title: String
        let icon: BrowserIcon
    }

    let title: String
    @Binding var selection: Value
    let options: [Option]
    var tint: Color = .accentColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.update(button, options: options, selected: selection)
        if button.isEnabled != isEnabled { button.isEnabled = isEnabled }
        let appearance: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if button.appearance?.name != appearance { button.appearance = NSAppearance(named: appearance) }
        let color = NSColor(tint)
        if button.contentTintColor != color { button.contentTintColor = color }
        button.setAccessibilityLabel(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        private var options: [Option] = []

        init(selection: Binding<Value>) { self.selection = selection }

        func update(_ button: NSPopUpButton, options: [Option], selected: Value) {
            let menuChanged = self.options != options || button.menu == nil
            if menuChanged {
                self.options = options
                let menu = NSMenu()
                menu.autoenablesItems = false
                for option in options {
                    let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                    item.image = option.icon.menuImage()
                    item.onStateImage = BrowserIcon.checkmark.menuImage()
                    BrowserMenuImages.keepImageVisible(item)
                    menu.addItem(item)
                }
                button.menu = menu
            }
            let index = options.firstIndex { $0.value == selected } ?? -1
            let selectionChanged = button.indexOfSelectedItem != index
            if selectionChanged { button.selectItem(at: index) }
            // A parent view can update without changing this picker. Keep the native
            // size cache until either its menu contents or displayed selection changes.
            if menuChanged || selectionChanged { button.invalidateIntrinsicContentSize() }
        }

        @objc func select(_ sender: NSPopUpButton) {
            guard sender.isEnabled, options.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = options[sender.indexOfSelectedItem].value
        }
    }
}
