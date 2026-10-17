import AppKit
import SwiftUI

struct TabFrameKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Reserve the add button and a window-drag area before shrinking or scrolling tabs.
struct HorizontalTabStripMetrics {
    static let spacing: CGFloat = 4
    static let addButtonSize: CGFloat = 32
    static let dragAreaWidth: CGFloat = 40
    let tabWidth: CGFloat
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    var scrolls: Bool { contentWidth > viewportWidth }

    init(tabCount: Int, width: CGFloat, leading: CGFloat) {
        let count = CGFloat(max(0, tabCount))
        let gaps = Self.spacing * max(0, count - 1)
        let available = max(0, width - leading - BrowserChrome.edgeInset
                            - Self.addButtonSize - Self.dragAreaWidth - Self.spacing * 2)
        tabWidth = count == 0 ? 0 : min(220, max(56, ((available - gaps) / count).rounded(.down)))
        contentWidth = tabWidth * count + gaps
        viewportWidth = min(contentWidth, available)
    }
}

struct TabStrip: View {
    let browser: BrowserModel
    let layout: TabLayout
    let isFullScreen: Bool
    let accent: Color
    @Binding var hoverCardTabID: UUID?
    private var tabLayout: TabLayout {
        get { browser.preferences.tabLayout }
        nonmutating set { browser.preferences.tabLayout = newValue }
    }

    @State private var hoveredTabID: UUID?
    @State private var suppressedHoverCardTabID: UUID?
    @State private var draggedTabID: UUID?
    @FocusState private var addButtonIsFocused: Bool

    private let spacing = HorizontalTabStripMetrics.spacing
    private let addButtonID = "new-tab-button"

    var body: some View {
        Group {
            switch layout {
            case .horizontal: horizontalStrip
            case .vertical: sidebar
            }
        }
        .task(id: hoveredTabID) { await updateHoverCard() }
    }

    private var horizontalStrip: some View {
        GeometryReader { geometry in
            let leading = isFullScreen ? BrowserChrome.edgeInset
                : BrowserChrome.windowButtonsTrailing(titlebarHeight: BrowserChrome.tabRowHeight) + 12
            let metrics = HorizontalTabStripMetrics(tabCount: browser.tabs.count,
                                                    width: geometry.size.width, leading: leading)

            HStack(spacing: spacing) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: spacing) {
                            ForEach(browser.tabStripGroups) { group in
                                tabGroup(group, width: metrics.tabWidth)
                            }
                        }
                        .frame(height: BrowserChrome.tabRowHeight)
                    }
                    .scrollIndicators(.never)
                    .scrollDisabled(!metrics.scrolls)
                    .onAppear {
                        if let activeTabID = browser.activeTabID { scrollProxy.scrollTo(activeTabID) }
                    }
                    .onChange(of: metrics.viewportWidth) { _, _ in
                        if let activeTabID = browser.activeTabID { scrollProxy.scrollTo(activeTabID) }
                    }
                    .onChange(of: browser.activeTabID) { _, activeTabID in
                        guard let activeTabID else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollProxy.scrollTo(activeTabID)
                        }
                    }
                }
                .frame(width: metrics.viewportWidth)

                newTabButton

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .browserContextMenu { stripMenuActions }
            }
            .padding(.leading, leading)
            .padding(.trailing, BrowserChrome.edgeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.snappy(duration: 0.22), value: browser.tabs.map(\.id))
            .animation(.snappy(duration: 0.22), value: metrics.tabWidth)
        }
        .frame(height: BrowserChrome.tabRowHeight)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .browserContextMenu { stripMenuActions }
            }
            .padding(.leading, isFullScreen ? BrowserChrome.edgeInset
                     : BrowserChrome.windowButtonsTrailing(titlebarHeight: BrowserChrome.navigationBarHeight) + 8)
            .padding(.trailing, BrowserChrome.edgeInset)
            .frame(height: BrowserChrome.navigationBarHeight)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(browser.tabStripGroups) { group in
                            tabGroup(group, width: nil)
                        }
                        newTabButton
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(addButtonID)
                    }
                    .padding(.horizontal, BrowserChrome.edgeInset)
                    .padding(.top, 2)
                    .padding(.bottom, BrowserChrome.edgeInset)
                }
                .scrollIndicators(.never)
                .onAppear { revealActiveSidebarTab(using: scrollProxy) }
                .onChange(of: browser.activeTabID) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        revealActiveSidebarTab(using: scrollProxy)
                    }
                }
            }
            .browserContextMenu(excludingTop: CGFloat(browser.tabs.count) * (BrowserChrome.sidebarTabHeight + 2)
                                + BrowserChrome.sidebarTabHeight + 2 + BrowserChrome.edgeInset
                                + (browser.hasSplitPair ? 4 : 0)) { stripMenuActions }
            .animation(.snappy(duration: 0.22), value: browser.tabs.map(\.id))
        }
    }

    private func revealActiveSidebarTab(using proxy: ScrollViewProxy) {
        guard let activeTabID = browser.activeTabID else { return }
        if browser.tabStripGroups.last?.tabs.contains(where: { $0.id == activeTabID }) == true {
            proxy.scrollTo(addButtonID, anchor: .bottom)
        } else {
            proxy.scrollTo(activeTabID)
        }
    }

    private var newTabButton: some View {
        Group {
            if layout == .vertical {
                Button(action: addTab) {
                    HStack(spacing: 7) {
                        Image(browserIcon: .add, size: 14)
                        Text("New Tab")
                            .font(.system(size: 12.5))
                            .tracking(-0.1)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: BrowserChrome.sidebarTabHeight)
                }
                .buttonStyle(SidebarNewTabButtonStyle())
            } else {
                Button(action: addTab) {
                    Image(browserIcon: .add, size: 14)
                }
                .buttonStyle(ChromeIconButtonStyle(size: HorizontalTabStripMetrics.addButtonSize))
            }
        }
        .focused($addButtonIsFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(addButtonIsFocused ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .help("New Tab (⌘T)")
        .accessibilityLabel("New Tab")
        .accessibilityIdentifier(addButtonID)
    }

    private func addTab() {
        hoverCardTabID = nil
        browser.addTab()
    }

    @ViewBuilder
    private func tabGroup(_ group: BrowserModel.TabStripGroup, width: CGFloat?) -> some View {
        if group.tabs.count == 2 {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let arrangement = layout == .vertical
                ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 0))
            arrangement {
                ForEach(group.tabs) { tab in
                    tabItem(for: tab, width: width, joined: true)
                        .id(tab.id)
                }
            }
            .padding(2)
            .background(accent.opacity(browser.isSplitView ? 0.055 : 0.025), in: shape)
            .overlay {
                shape.strokeBorder(accent.opacity(browser.isSplitView ? 0.45 : 0.3), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Split View")
        } else if let tab = group.tabs.first {
            tabItem(for: tab, width: width)
                .id(tab.id)
        }
    }

    private func tabItem(for tab: BrowserTab, width: CGFloat?, joined: Bool = false) -> some View {
        let isActive = browser.activeTabID == tab.id
        let isHovered = hoveredTabID == tab.id
        let index = browser.tabs.firstIndex { $0.id == tab.id } ?? 0
        let nextTab = browser.tabs.indices.contains(index + 1) ? browser.tabs[index + 1] : nil
        let showsSeparator = !joined && layout == .horizontal && nextTab.map { next in
            !browser.splitTabIDs.contains(next.id) && !isActive && !isHovered
                && browser.activeTabID != next.id && hoveredTabID != next.id
        } ?? false

        return TabItem(tab: tab,
                       isActive: isActive,
                       isHovered: isHovered,
                       width: width,
                       height: layout == .vertical ? BrowserChrome.sidebarTabHeight : BrowserChrome.tabHeight,
                       splitPosition: joined ? browser.splitTabIDs.firstIndex(of: tab.id) : nil,
                       accent: accent,
                       select: {
                           suppressedHoverCardTabID = tab.id
                           hoverCardTabID = nil
                           browser.activeTabID = tab.id
                       },
                       close: {
                           hoverCardTabID = nil
                           browser.closeTab(tab.id)
                       })
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)
                    .offset(x: (spacing + 1) / 2)
                    .opacity(showsSeparator ? 1 : 0)
            }
            .anchorPreference(key: TabFrameKey.self, value: .bounds) { [tab.id: $0] }
            .onHover { isHovering in
                if isHovering {
                    hoveredTabID = tab.id
                } else if hoveredTabID == tab.id {
                    hoveredTabID = nil
                }
            }
            .onDrag {
                draggedTabID = tab.id
                hoverCardTabID = nil
                suppressedHoverCardTabID = tab.id
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(targetID: tab.id, draggedID: $draggedTabID,
                canMove: { id in browser.tabs.contains { $0.id == id } },
                move: { id, target in
                    browser.moveTabGroup(containing: id, beside: target)
                }))
            .browserContextMenu { tabMenuActions(for: tab) }
    }

    /// Shows the card after a short delay, then follows the pointer between tabs without waiting again.
    private func updateHoverCard() async {
        guard let hoveredTabID else {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            hoverCardTabID = nil
            suppressedHoverCardTabID = nil
            return
        }
        guard hoveredTabID != suppressedHoverCardTabID else { return }
        if hoverCardTabID != nil {
            hoverCardTabID = hoveredTabID
            return
        }
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled else { return }
        hoverCardTabID = hoveredTabID
    }

    private var layoutAction: BrowserContextAction {
        .init(title: layout == .vertical ? "Use Horizontal Tabs" : "Use Vertical Tabs",
              icon: layout == .vertical ? .horizontalTabs : .verticalTabs) { tabLayout = layout.toggled }
    }
    private var stripMenuActions: [BrowserContextAction] {
        [.init(title: "New Tab", icon: .add) { browser.addTab() },
         .init(title: "Reopen Closed Tab", icon: .reopen, isEnabled: browser.canReopenClosedTab) { browser.reopenClosedTab() },
         .separator, layoutAction]
    }
    private func tabMenuActions(for tab: BrowserTab) -> [BrowserContextAction] {
        let isJoined = browser.splitTabIDs.contains(tab.id)
        let lastGroupContainsTab = browser.tabStripGroups.last?.tabs.contains { $0.id == tab.id } ?? true
        return [.init(title: "New Tab", icon: .add) { browser.addTab() }, .separator,
         .init(title: "Reload", icon: .reload, isEnabled: !tab.isNewTab) { browser.reloadTab(tab.id) },
         .init(title: browser.splitTabIDs.contains(tab.id) ? "Exit Split View" : "Open Beside Current Tab",
               icon: .splitView, isEnabled: browser.isSplitView || browser.activeTabID != tab.id) {
             if browser.splitTabIDs.contains(tab.id) { browser.endSplitView(keeping: tab.id) }
             else { browser.startSplitView(with: tab.id) }
         },
         .init(title: "Duplicate", icon: .copy) { browser.duplicateTab(tab.id) },
         .init(title: "Copy Link", icon: .copy, isEnabled: tab.url != nil) {
             guard let url = tab.url else { return }
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString(url.absoluteString, forType: .string)
         }, .separator,
         .init(title: "Close Tab", icon: .close) { browser.closeTab(tab.id) },
         .init(title: "Close Other Tabs", icon: .close, isEnabled: browser.tabs.count >= 2) { browser.closeOtherTabs(than: tab.id) },
         .init(title: isJoined ? "Close Tabs After Split View" : "Close Tabs to the Right",
               icon: .close, isEnabled: !lastGroupContainsTab) { browser.closeTabs(afterGroupContaining: tab.id) }, .separator,
         .init(title: "Reopen Closed Tab", icon: .reopen, isEnabled: browser.canReopenClosedTab) { browser.reopenClosedTab() },
         .separator, layoutAction]
    }

}

private struct TabItem: View {
    let tab: BrowserTab
    let isActive: Bool
    let isHovered: Bool
    /// A fixed width in the tab strip, or `nil` to fill the sidebar.
    let width: CGFloat?
    let height: CGFloat
    let splitPosition: Int?
    let accent: Color
    let select: () -> Void
    let close: () -> Void

    private var isCompact: Bool { (width ?? .infinity) < 100 }
    private var isJoined: Bool { splitPosition != nil }
    /// Narrow tabs keep their icon visible and only swap in the close button while hovered.
    private var showsCloseButton: Bool { isHovered || (isActive && !isCompact) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 7) {
            if !(isCompact && showsCloseButton) {
                TabIcon(tab: tab, isActive: isActive)
                    .opacity(tab.isSuspended ? 0.5 : 1)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction(.default, select)
                    .accessibilityHidden(!isCompact)
            }
            if !isCompact {
                title
            }
            if showsCloseButton || !isCompact {
                closeButton
                    .opacity(showsCloseButton ? 1 : 0)
                    .allowsHitTesting(showsCloseButton)
            }
        }
        .padding(.leading, isCompact ? 0 : 10)
        .padding(.trailing, isCompact ? 0 : 4)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            shape.fill(isActive ? (isJoined ? accent.opacity(0.16) : Color.primary.opacity(0.11)) :
                       isHovered ? Color.primary.opacity(0.055) : Color.clear)
                .shadow(color: .black.opacity(isActive && !isJoined ? 0.08 : 0), radius: 1, y: 0.5)
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(isActive && !isJoined ? 0.07 : 0), lineWidth: 1)
        }
        .contentShape(shape)
        .onTapGesture(perform: select)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityValue(splitPosition.map { $0 == 0 ? "Left pane" : "Right pane" } ?? "")
    }

    private var title: some View {
        // The title lives in an overlay so its natural width never widens the tab.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                    .tracking(-0.1)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            // Fade long titles instead of truncating them with an ellipsis.
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(browserIcon: .close, size: 9)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromeCloseButtonStyle())
        .help("Close Tab (⌘W)")
        .accessibilityLabel("Close \(tab.title)")
    }
}

private struct TabIcon: View {
    let tab: BrowserTab
    let isActive: Bool

    var body: some View {
        Group {
            if tab.isLoading && !tab.isNewTab {
                ProgressView()
                    .controlSize(.mini)
            } else if let favicon = tab.favicon {
                favicon
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(browserIcon: tab.isNewTab ? .home : .globe)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.light)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }
}

struct TabHoverCard: View {
    let tab: BrowserTab
    let isActive: Bool

    static let width: CGFloat = 280

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            if !isActive, !tab.isNewTab, let thumbnail = tab.thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.width, height: 156, alignment: .top)
                    .clipped()
                Divider()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    if tab.isSecure {
                        Image(browserIcon: .secure, size: 8.5)
                    }
                    Text(subtitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private var subtitle: String {
        if tab.isNewTab { return "Start page" }
        let host = tab.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            ?? tab.url?.absoluteString ?? ""
        return tab.isLoading ? "\(host) · Loading…" : host
    }
}

struct ChromeIconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: size, height: size)
            .background(!isEnabled ? Color.clear :
                        configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: size <= 28 ? 8 : 10, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct SidebarNewTabButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .background(configuration.isPressed ? Color.primary.opacity(0.11) :
                        isHovered ? Color.primary.opacity(0.07) : Color.clear, in: shape)
            .contentShape(shape)
            .onHover { isHovered = $0 }
    }
}

struct ChromeCloseButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .background(configuration.isPressed ? Color.primary.opacity(0.14) :
                        isHovered ? Color.primary.opacity(0.09) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
    }
}
