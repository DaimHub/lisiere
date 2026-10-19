import SwiftUI

/// Page-local observation keeps loading progress, errors and Find out of the window's view body.
/// The native page keeps its identity while its lightweight overlays update independently.
struct BrowserWebPage: View {
    let tab: BrowserTab
    let browser: BrowserModel
    let accent: Color
    let updateAddress: (URL?) -> Void

    var body: some View {
        PageHost(content: tab.contentView, tab: tab, browser: browser)
            .modifier(PageErrorOverlay(tab: tab))
            .modifier(PageFindOverlay(tab: tab, browser: browser))
            .modifier(PageProgressOverlay(tab: tab, accent: accent))
            .onChange(of: tab.url) { _, url in updateAddress(url) }
            .onAppear { updateAddress(tab.url) }
    }
}

private struct PageErrorOverlay: ViewModifier {
    let tab: BrowserTab
    func body(content: Content) -> some View {
        content.overlay {
            if let error = tab.loadError {
                PageErrorView(error: error, isLoading: tab.isLoading) { tab.retry() }
            }
        }
    }
}

private struct PageFindOverlay: ViewModifier {
    let tab: BrowserTab
    let browser: BrowserModel
    @Environment(\.browserReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if tab.isFindBarVisible, browser.activeTabID == tab.id {
                FindBar(tab: tab, browser: browser)
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: tab.isFindBarVisible)
    }
}

private struct PageProgressOverlay: ViewModifier {
    let tab: BrowserTab
    let accent: Color
    @Environment(\.browserReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if tab.isLoading {
                GeometryReader { geometry in
                    Capsule()
                        .fill(accent.opacity(0.5))
                        .frame(width: max(18, geometry.size.width * tab.estimatedProgress), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.top, 3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: tab.estimatedProgress)
            }
        }
    }
}
