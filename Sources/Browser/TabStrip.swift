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

    init(tabCount: Int, width: CGFloat, leading: CGFloat, supplementaryWidth: CGFloat = 0) {
        let count = CGFloat(max(0, tabCount))
        let gaps = Self.spacing * max(0, count - 1)
        let available = max(0, width - leading - BrowserChrome.edgeInset
                            - Self.addButtonSize - Self.dragAreaWidth - Self.spacing * 2)
        tabWidth = count == 0 ? 0 : min(220, max(56, ((available - gaps - supplementaryWidth) / count).rounded(.down)))
        contentWidth = tabWidth * count + gaps + supplementaryWidth
        viewportWidth = min(contentWidth, available)
    }
}

/// Each row fills the sidebar, including a final row with only one or two pins.
struct PinnedTabGridMetrics {
    static let spacing: CGFloat = 4
    static let tileHeight: CGFloat = 36
    static let horizontalTileWidth: CGFloat = 44
    let count: Int
    let width: CGFloat
    let columns: Int
    var rows: Int { (count + columns - 1) / columns }
    var height: CGFloat { CGFloat(rows) * Self.tileHeight + CGFloat(max(0, rows - 1)) * Self.spacing }

    init(count: Int, width: CGFloat) {
        self.count = max(0, count)
        self.width = width.isFinite ? max(0, width) : 220
        columns = min(3, max(1, Int((self.width + Self.spacing) / (56 + Self.spacing))))
    }

    func frame(at index: Int) -> CGRect {
        let row = index / columns
        let rowCount = min(columns, count - row * columns)
        let tileWidth = max(0, (width - CGFloat(rowCount - 1) * Self.spacing) / CGFloat(max(1, rowCount)))
        return CGRect(x: CGFloat(index % columns) * (tileWidth + Self.spacing),
                      y: CGFloat(row) * (Self.tileHeight + Self.spacing),
                      width: tileWidth, height: Self.tileHeight)
    }
}

/// A single layout keeps tab identity stable when pins move between rows.
private struct PinnedTabGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = PinnedTabGridMetrics(count: subviews.count, width: proposal.width ?? 220)
        return CGSize(width: metrics.width, height: metrics.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = PinnedTabGridMetrics(count: subviews.count, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let frame = metrics.frame(at: index)
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
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
    @State private var drag: TabDragController
    @GestureState private var dragGestureActive = false
    @State private var groupEditor: TabGroupEditorRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var addButtonIsFocused: Bool
    @FocusState private var focusedGroupSection: String?

    init(browser: BrowserModel, layout: TabLayout, isFullScreen: Bool, accent: Color,
         hoverCardTabID: Binding<UUID?>, drag: TabDragController = TabDragController()) {
        self.browser = browser
        self.layout = layout
        self.isFullScreen = isFullScreen
        self.accent = accent
        _hoverCardTabID = hoverCardTabID
        // Native host tests inject the same gesture state used by the rendered strip.
        _drag = State(initialValue: drag)
    }

    private let spacing = HorizontalTabStripMetrics.spacing
    private let addButtonID = "new-tab-button"
    private var folderAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.24) }
    private var folderContentTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(
            x: layout == .horizontal ? -8 : 0, y: layout == .vertical ? -6 : 0))
    }

    var body: some View {
        Group {
            switch layout {
            case .horizontal: horizontalStrip
            case .vertical: sidebar
            }
        }
        // One transaction coordinates the children, neighboring sections and pin viewport size,
        // regardless of whether the change came from a click, menu, or spring-loaded drag.
        // Keep the pointer-following drag overlay outside this animation scope.
        .animation(folderAnimation, value: Dictionary(uniqueKeysWithValues: browser.groups.map { ($0.id, $0.isCollapsed) }))
        .coordinateSpace(name: TabDragController.coordinateSpace)
        .overlayPreferenceValue(TabDragBoundsKey.self) { bounds in
            TabDragGeometryObserver(bounds: bounds, drag: drag, browser: browser)
        }
        .overlay { TabDragPreview(drag: drag, browser: browser) }
        .onChange(of: dragGestureActive) { _, active in if !active { drag.reset() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if notification.object as? NSWindow === browser.window, drag.isDragging { drag.cancel() }
        }
        .onDisappear { drag.reset() }
        .task(id: hoveredTabID) { await updateHoverCard() }
        .sheet(item: $groupEditor) { request in
            TabGroupEditor(browser: browser, request: request)
        }
    }

    private var horizontalStrip: some View {
        GeometryReader { geometry in
            let leading = isFullScreen ? BrowserChrome.edgeInset
                : BrowserChrome.windowButtonsTrailing(titlebarHeight: BrowserChrome.tabRowHeight) + 12
            let sections = browser.tabSections
            let pinned = sections.filter(\.isPinned)
            let regular = sections.filter { !$0.isPinned }
            let pinContentWidth = pinned.reduce(CGFloat(0)) { width, section in
                width + CGFloat(section.visibleCards.reduce(0) { $0 + $1.tabs.count })
                    * (PinnedTabGridMetrics.horizontalTileWidth + spacing)
                    + (section.group == nil ? 0 : 124)
                    + CGFloat(section.visibleCards.filter { $0.tabs.count == 2 }.count) * 4
            }
            let available = max(0, geometry.size.width - leading - 100)
            let pinWidth = min(pinContentWidth, available * (regular.isEmpty ? 1 : 0.4))
            let metrics = HorizontalTabStripMetrics(
                tabCount: regular.reduce(0) { $0 + $1.visibleCards.reduce(0) { $0 + $1.tabs.count } },
                width: geometry.size.width - pinWidth - (pinned.isEmpty ? 0 : 8), leading: leading,
                supplementaryWidth: CGFloat(regular.filter { $0.group != nil }.count) * 124
                    + CGFloat(regular.flatMap(\.visibleCards).filter { $0.tabs.count == 2 }.count) * 4)

            HStack(spacing: spacing) {
                if !pinned.isEmpty {
                    horizontalSections(pinned, width: PinnedTabGridMetrics.horizontalTileWidth)
                        .frame(width: pinWidth)
                    Divider().frame(height: 18).padding(.horizontal, 2)
                }
                horizontalSections(regular, width: metrics.tabWidth)
                    .frame(width: metrics.viewportWidth)
                newTabButton
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .overlay { if drag.isDragging { outsideGroupHint(compact: true) } }
                    .tabDropRegion("outside-horizontal", target: .group(nil), horizontal: false, drag: drag, accent: accent)
                    .browserContextMenu { stripMenuActions }
            }
            .padding(.leading, leading)
            .padding(.trailing, BrowserChrome.edgeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: browser.tabs.map(\.id))
        }
        .frame(height: BrowserChrome.tabRowHeight)
    }

    private func horizontalSections(_ sections: [BrowserModel.TabSection], width: CGFloat) -> some View {
        let viewport = sections.first?.isPinned == true ? "pins" : "tabs"
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(sections) { section in
                        HStack(spacing: spacing) {
                            if let group = section.group { groupHeader(group, section: section) }
                            ForEach(section.visibleCards) { card in
                                tabGroup(card, width: width)
                                    .transition(section.group == nil ? .opacity : folderContentTransition)
                            }
                        }
                        .tabGroupDropRegion(section.id, groupID: section.group?.id, horizontal: true,
                                            viewport: viewport, drag: drag, accent: accent)
                    }
                }
                .frame(height: BrowserChrome.tabRowHeight)
            }
            .scrollIndicators(.never)
            .tabDragViewport(viewport, horizontal: true)
            .tabDragAutoScroll(viewport, drag: drag, proxy: proxy, reduceMotion: reduceMotion)
            .onAppear { revealActiveTab(in: sections, using: proxy) }
            .onChange(of: browser.activeTabID) { _, _ in revealActiveTab(in: sections, using: proxy) }
            .onChange(of: width) { _, _ in revealActiveTab(in: sections, using: proxy) }
            .onChange(of: browser.tabs.map(\.isPinned)) { _, _ in revealActiveTab(in: sections, using: proxy) }
        }
    }

    private func revealActiveTab(in sections: [BrowserModel.TabSection], using proxy: ScrollViewProxy) {
        guard let id = browser.activeTabID,
              sections.contains(where: { $0.cards.contains { $0.tabs.contains { $0.id == id } } }) else { return }
        proxy.scrollTo(id)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .browserContextMenu { stripMenuActions }
                .frame(height: BrowserChrome.navigationBarHeight)

            GeometryReader { geometry in
                let sections = browser.tabSections
                let pinned = sections.filter(\.isPinned)
                let pinnedHeight = pinned.reduce(2 + BrowserChrome.edgeInset + CGFloat(max(0, pinned.count - 1)) * 4) { height, section in
                    let count = section.visibleCards.reduce(0) { $0 + $1.tabs.count }
                    let grid = PinnedTabGridMetrics(count: count, width: geometry.size.width - BrowserChrome.edgeInset * 2)
                    return height + grid.height + (section.group == nil ? 0 : 28 + (count > 0 ? 2 : 0))
                }
                VStack(spacing: 0) {
                    if !pinned.isEmpty {
                        sidebarSections(pinned, showsNewTab: false)
                            .frame(height: min(pinnedHeight, geometry.size.height * 0.4))
                        Divider().padding(.horizontal, BrowserChrome.edgeInset).padding(.vertical, 4)
                    }
                    sidebarSections(sections.filter { !$0.isPinned }, showsNewTab: true)
                    if drag.isDragging {
                        outsideGroupHint(compact: false)
                            .frame(height: 32)
                            .padding(.horizontal, BrowserChrome.edgeInset)
                            .padding(.bottom, 4)
                            .tabDropRegion("outside-footer", target: .group(nil), horizontal: false, drag: drag, accent: accent)
                    }
                }
                .tabDropRegion("outside-sidebar", target: .group(nil), horizontal: false, priority: 0, drag: drag, accent: accent)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: browser.tabs.map(\.id))
        }
    }

    private func sidebarSections(_ sections: [BrowserModel.TabSection], showsNewTab: Bool) -> some View {
        let viewport = showsNewTab ? "tabs" : "pins"
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(sections) { section in
                        VStack(spacing: 2) {
                            if let group = section.group { groupHeader(group, section: section) }
                            if section.isPinned && !section.visibleCards.isEmpty {
                                PinnedTabGrid {
                                    ForEach(section.visibleCards.flatMap(\.tabs)) { tab in
                                        tabItem(for: tab, width: nil).id(tab.id)
                                    }
                                }
                                .transition(section.group == nil ? .opacity : folderContentTransition)
                            } else if !section.isPinned {
                                ForEach(section.visibleCards) { card in
                                    tabGroup(card, width: nil)
                                        .transition(section.group == nil ? .opacity : folderContentTransition)
                                }
                            }
                        }
                        .tabGroupDropRegion(section.id, groupID: section.group?.id, horizontal: false,
                                            viewport: viewport, drag: drag, accent: accent)
                    }
                    if showsNewTab {
                        newTabButton
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(addButtonID)
                    }
                }
                .padding(.horizontal, BrowserChrome.edgeInset)
                .padding(.top, 2)
                .padding(.bottom, BrowserChrome.edgeInset)
            }
            .scrollIndicators(.never)
            .tabDragViewport(viewport, horizontal: false)
            .tabDragAutoScroll(viewport, drag: drag, proxy: proxy, reduceMotion: reduceMotion)
            .onAppear { revealActiveTab(in: sections, using: proxy) }
            .onChange(of: browser.activeTabID) { _, _ in revealActiveTab(in: sections, using: proxy) }
            .onChange(of: browser.tabs.map(\.isPinned)) { _, _ in revealActiveTab(in: sections, using: proxy) }
            .contextMenu { BrowserMenuContent(actions: stripMenuActions) }
        }
    }

    private func groupHeader(_ group: TabGroup, section: BrowserModel.TabSection) -> some View {
        let isSelected = section.cards.contains { $0.tabs.contains { browser.isTabVisible($0.id) } }
        return Button { browser.toggleGroupCollapsed(group.id) } label: {
            HStack(spacing: 6) {
                Image(browserIcon: .forward, size: 10)
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                    .animation(folderAnimation, value: group.isCollapsed)
                Image(browserIcon: .tabGroup, size: 13).foregroundStyle(group.color.tint)
                Text(group.name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(String(section.tabCount)).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 7)
            .frame(width: layout == .horizontal ? 120 : nil, height: 28)
        }
        .buttonStyle(TabGroupButtonStyle(tint: group.color.tint, isSelected: isSelected,
                                        isFocused: focusedGroupSection == section.id,
                                        isDragging: drag.isDragging,
                                        isDropTarget: drag.indicator?.id == section.id))
        .focused($focusedGroupSection, equals: section.id)
        .help("\(group.name) · \(group.color.title)")
        .accessibilityLabel("\(group.name), \(section.tabCount) tabs")
        .accessibilityValue("\(group.isCollapsed ? "Collapsed" : "Expanded"), \(group.color.title)")
        .accessibilityIdentifier("tab-group-\(section.id)")
        .browserContextMenu { groupMenuActions(group) }
        .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(TabDragController.coordinateSpace))
            .updating($dragGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                hoverCardTabID = nil
                drag.updateGroup(id: group.id, location: value.location, browser: browser)
            }
            .onEnded { value in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    drag.finishGroup(id: group.id, location: value.location, browser: browser)
                }
            })
        .id(section.id)
        .tabDropRegion(section.id, target: .group(group.id), horizontal: false,
                       viewport: section.isPinned ? "pins" : "tabs", drag: drag, accent: group.color.tint)
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
        .tabDropRegion("outside-new-tab", target: .group(nil), horizontal: false,
                       viewport: layout == .vertical ? "tabs" : nil, drag: drag, accent: accent)
    }

    private func outsideGroupHint(compact: Bool) -> some View {
        let movingGroup = drag.sourceGroupID != nil
        let grouped = browser.tab(withID: drag.sourceID)?.groupID != nil
        return HStack(spacing: 6) {
            Image(browserIcon: movingGroup ? .tabGroup : .ungroup, size: 14)
            if !compact {
                Text(movingGroup ? "Move group to end" : grouped ? "Move out of group" : "Move to end")
                    .font(.system(size: 11.5))
            }
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(accent.opacity(drag.indicator?.target == .group(nil) ? 0.16 : 0.07),
                    in: RoundedRectangle(cornerRadius: 7))
        .allowsHitTesting(false)
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
        let showsSeparator = !tab.isPinned && !joined && layout == .horizontal && nextTab.map { next in
            !browser.splitTabIDs.contains(next.id) && !isActive && !isHovered
                && browser.activeTabID != next.id && hoveredTabID != next.id
        } ?? false

        return TabItem(tab: tab,
                       isActive: isActive,
                       isHovered: isHovered,
                       width: width,
                       height: layout == .vertical
                           ? (tab.isPinned ? PinnedTabGridMetrics.tileHeight : BrowserChrome.sidebarTabHeight)
                           : BrowserChrome.tabHeight,
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
            .overlay(alignment: .bottom) {
                if let group = browser.groups.first(where: { $0.id == tab.groupID }) {
                    Capsule().fill(group.color.tint).frame(width: tab.isPinned ? 12 : 24, height: 2)
                        .padding(.bottom, 1).allowsHitTesting(false)
                }
            }
            .help(tab.isPinned ? "\(tab.title) · Pinned" : tab.title)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)
                    .offset(x: (spacing + 1) / 2)
                    .opacity(showsSeparator ? 1 : 0)
            }
            // Only the displayed hover preview consumes this anchor. Collecting a second
            // full strip of anchors during every folder animation duplicates the drag geometry.
            .anchorPreference(key: TabFrameKey.self, value: .bounds) {
                hoverCardTabID == tab.id ? [tab.id: $0] : [:]
            }
            .onHover { isHovering in
                if isHovering {
                    hoveredTabID = tab.id
                } else if hoveredTabID == tab.id {
                    hoveredTabID = nil
                }
            }
            .opacity(drag.sourceID == tab.id ? 0.4 : 1)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(TabDragController.coordinateSpace))
                .updating($dragGestureActive) { _, active, _ in active = true }
                .onChanged { value in
                    hoverCardTabID = nil
                    suppressedHoverCardTabID = tab.id
                    drag.update(id: tab.id, location: value.location, browser: browser)
                }
                .onEnded { value in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        drag.finish(id: tab.id, location: value.location, browser: browser)
                    }
                })
            .tabDropRegion(tab.id.uuidString, target: .tab(tab.id), horizontal: layout == .horizontal || tab.isPinned,
                           viewport: tab.isPinned ? "pins" : "tabs", priority: 2, drag: drag, accent: accent)
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
        guard !drag.isDragging, hoveredTabID != suppressedHoverCardTabID else { return }
        if hoverCardTabID != nil {
            hoverCardTabID = hoveredTabID
            return
        }
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled, !drag.isDragging else { return }
        hoverCardTabID = hoveredTabID
    }

    private var layoutAction: BrowserContextAction {
        .init(title: layout == .vertical ? "Use Horizontal Tabs" : "Use Vertical Tabs",
              icon: layout == .vertical ? .horizontalTabs : .verticalTabs) { tabLayout = layout.toggled }
    }
    private var stripMenuActions: [BrowserContextAction] {
        [.init(title: "New Tab", icon: .add) { browser.addTab() },
         .init(title: "New Group…", icon: .tabGroup) { groupEditor = TabGroupEditorRequest() },
         .init(title: "Reopen Closed Tab", icon: .reopen, isEnabled: browser.canReopenClosedTab) { browser.reopenClosedTab() },
         .separator, layoutAction]
    }

    private func groupMenuActions(_ group: TabGroup) -> [BrowserContextAction] {
        let index = browser.groups.firstIndex { $0.id == group.id } ?? 0
        return [
            .init(title: "New Tab in Group", icon: .add) { browser.addTab(in: group.id) },
            .init(title: "Edit Name and Color…", icon: .rename) { groupEditor = TabGroupEditorRequest(group: group) },
            .init(title: group.isCollapsed ? "Expand Group" : "Collapse Group", icon: .tabGroup) { browser.toggleGroupCollapsed(group.id) },
            .separator,
            .init(title: "Move Group Earlier", icon: .back, isEnabled: index > 0) { browser.moveGroup(group.id, by: -1) },
            .init(title: "Move Group Later", icon: .forward, isEnabled: index + 1 < browser.groups.count) { browser.moveGroup(group.id, by: 1) },
            .separator,
            .init(title: "Ungroup Tabs", icon: .ungroup) { browser.ungroup(group.id) }
        ]
    }

    private func tabMenuActions(for tab: BrowserTab) -> [BrowserContextAction] {
        let cards = browser.tabStripGroups
        let index = cards.firstIndex { $0.tabs.contains { $0.id == tab.id } } ?? 0
        let isJoined = cards.indices.contains(index) && cards[index].tabs.count == 2
        let canCloseAfter = cards.dropFirst(index + 1).contains { $0.tabs.contains { !$0.isPinned } }
        var groupActions: [BrowserContextAction] = [
            .init(title: "New Group…", icon: .tabGroup) { groupEditor = TabGroupEditorRequest(tabID: tab.id) }
        ]
        groupActions += browser.groups.map { group in
            .init(title: group.name, icon: tab.groupID == group.id ? .checkmark : .tabGroup) {
                browser.assignTab(tab.id, to: group.id)
            }
        }
        if tab.groupID != nil {
            groupActions += [.separator, .init(title: "Remove from Group", icon: .ungroup) { browser.assignTab(tab.id, to: nil) }]
        }
        var actions: [BrowserContextAction] = [
            .init(title: "New Tab", icon: .add) { browser.addTab() }, .separator,
            .init(title: tab.isPinned ? "Unpin Tab" : "Pin Tab", icon: .pin) { browser.setPinned(!tab.isPinned, for: tab.id) },
            .init(title: "Move to Group", icon: .tabGroup, children: groupActions),
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
            }, .separator
        ]
        if !tab.isPinned { actions.append(.init(title: "Close Tab", icon: .close) { browser.closeTab(tab.id) }) }
        actions += [
            .init(title: "Close Other Tabs", icon: .close, isEnabled: browser.tabs.contains { $0.id != tab.id && !$0.isPinned }) { browser.closeOtherTabs(than: tab.id) },
            .init(title: isJoined ? "Close Tabs After Split View" : layout == .vertical ? "Close Tabs Below" : "Close Tabs to the Right",
                  icon: .close, isEnabled: canCloseAfter) { browser.closeTabs(afterGroupContaining: tab.id) }, .separator,
            .init(title: "Reopen Closed Tab", icon: .reopen, isEnabled: browser.canReopenClosedTab) { browser.reopenClosedTab() },
            .separator, layoutAction
        ]
        return actions
    }

}

/// Pointer motion redraws only the floating preview. Resolving every anchor belongs to layout
/// updates, and must not run again for each pointer sample over an otherwise stationary strip.
private struct TabDragGeometryObserver: View {
    let bounds: TabDragBounds
    let drag: TabDragController
    let browser: BrowserModel

    var body: some View {
        GeometryReader { geometry in
            let frames = bounds.resolve(in: geometry)
            Color.clear
                .onChange(of: frames, initial: true) { _, frames in drag.updateFrames(frames, browser: browser) }
        }.allowsHitTesting(false)
    }
}

private struct TabDragPreview: View {
    let drag: TabDragController
    let browser: BrowserModel

    var body: some View {
        GeometryReader { _ in
            if let id = drag.sourceID, let tab = browser.tab(withID: id), let point = drag.location {
                HStack(spacing: 6) {
                    TabIcon(tab: tab, isActive: false)
                    if !tab.isPinned { Text(tab.title).font(.system(size: 12)).lineLimit(1) }
                }
                .padding(.horizontal, 10)
                .frame(width: tab.isPinned ? 44 : 160, height: 32)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .position(x: point.x + 20, y: point.y + 20)
            } else if let id = drag.sourceGroupID, let group = browser.groups.first(where: { $0.id == id }),
                      let point = drag.location {
                Label(group.name, browserIcon: .tabGroup)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .foregroundStyle(group.color.tint)
                    .padding(.horizontal, 10)
                    .frame(width: 160, height: 32)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .position(x: point.x + 20, y: point.y + 20)
            }
        }
        // A native material here creates/removes a backdrop view for every drag. Keep the
        // transient preview lightweight, and never animate its cleanup with the committed move.
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
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

    private var isCompact: Bool { tab.isPinned || (width ?? .infinity) < 100 }
    private var isJoined: Bool { splitPosition != nil }
    /// Narrow tabs keep their icon visible and only swap in the close button while hovered.
    private var showsCloseButton: Bool { !tab.isPinned && (isHovered || (isActive && !isCompact)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 7) {
            if !(isCompact && showsCloseButton) {
                TabIcon(tab: tab, isActive: isActive)
                    .opacity(tab.isSuspended ? 0.5 : 1)
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier("tab-icon-\(tab.id)")
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
            shape.fill(isActive ? (isJoined ? accent.opacity(0.16) : Color.primary.opacity(tab.isPinned ? 0.14 : 0.11)) :
                       Color.primary.opacity(isHovered ? (tab.isPinned ? 0.09 : 0.055) : (tab.isPinned ? 0.045 : 0)))
                .shadow(color: .black.opacity(isActive && !isJoined ? 0.08 : 0), radius: 1, y: 0.5)
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(isActive && !isJoined ? 0.07 : 0), lineWidth: 1)
        }
        .contentShape(shape)
        .onTapGesture(perform: select)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityValue([tab.isPinned ? "Pinned" : nil, splitPosition.map { $0 == 0 ? "Left pane" : "Right pane" }].compactMap { $0 }.joined(separator: ", "))
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
            .accessibilityIdentifier("tab-title-\(tab.id)")
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
        .accessibilityIdentifier("close-tab-\(tab.id)")
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
        .frame(width: tab.isPinned ? 18 : 14, height: tab.isPinned ? 18 : 14)
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

/// Keep the full header's geometry stable while its surface responds to mouse and keyboard input.
/// Each section owns its hover state, including when a group appears in both pin and ordinary lists.
private struct TabGroupButtonStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool
    let isFocused: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let pressed = configuration.isPressed && !isDragging
        let hovered = isHovered && !isDragging
        let emphasized = hovered || isDropTarget
        let fill = pressed ? 0.23 : emphasized ? 0.14 : isSelected ? 0.10 : 0.045
        let border = pressed ? 0.60 : emphasized ? 0.42 : isSelected ? 0.32 : 0.12
        return configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .offset(y: pressed && !reduceMotion ? 0.5 : 0)
            .background {
                shape.fill(Color.primary.opacity(pressed ? 0.05 : hovered ? 0.035 : 0.02))
                shape.fill(tint.opacity(fill + (colorScheme == .dark ? 0.035 : 0)))
            }
            .overlay {
                shape.strokeBorder(tint.opacity(contrast == .increased ? max(0.6, border) : border), lineWidth: 1)
                    .allowsHitTesting(false)
                if isFocused {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .animation(reduceMotion || isDragging ? nil : .easeOut(duration: pressed ? 0.08 : 0.14), value: pressed)
            .animation(reduceMotion || isDragging ? nil : .easeOut(duration: 0.14), value: hovered)
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
