import AppKit
import SwiftUI

struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TransparentWindowMaterialView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // A SwiftUI hosting ancestor can retain its own appearance. Match the resolved profile
        // palette explicitly, without writing a preferredColorScheme back to the whole window.
        let name: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
    }
}

private final class TransparentWindowMaterialView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }
}
