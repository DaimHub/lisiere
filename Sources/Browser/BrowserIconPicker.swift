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
        button.isEnabled = isEnabled
        button.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        button.contentTintColor = NSColor(tint)
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
            if self.options != options || button.menu == nil {
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
            button.selectItem(at: options.firstIndex { $0.value == selected } ?? -1)
            button.invalidateIntrinsicContentSize()
        }

        @objc func select(_ sender: NSPopUpButton) {
            guard sender.isEnabled, options.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = options[sender.indexOfSelectedItem].value
        }
    }
}
