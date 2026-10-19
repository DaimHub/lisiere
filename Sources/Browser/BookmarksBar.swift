import AppKit
import SwiftUI

struct BookmarksBar: View {
    let bookmarks: BookmarkStore
    let browser: BrowserModel

    @State private var draggedBookmarkID: UUID?
    @State private var renamingBookmarkID: UUID?

    static let height: CGFloat = 30

    var body: some View {
        HStack(spacing: 2) {
            if bookmarks.bookmarks.isEmpty {
                Label("Bookmark pages with ⌘D or the bookmark button in the address bar", browserIcon: .bookmark)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(bookmarks.bookmarks) { bookmark in
                            item(for: bookmark)
                        }
                    }
                }
                .scrollIndicators(.never)

                Menu {
                    ForEach(bookmarks.bookmarks) { bookmark in
                        Button(bookmark.displayTitle, browserIcon: .bookmark) { open(bookmark) }
                    }
                } label: {
                    Image(browserIcon: .chevronDown, size: 10)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(ChromeIconButtonStyle(size: 24))
                .fixedSize()
                .help("All Bookmarks")
                .accessibilityLabel("All bookmarks")
                .browserMenu {
                    bookmarks.bookmarks.map { bookmark in
                        .init(title: bookmark.displayTitle, icon: .bookmark) { open(bookmark) }
                    }
                }
            }
        }
        .padding(.horizontal, BrowserChrome.edgeInset)
        .frame(height: Self.height)
        .animation(.snappy(duration: 0.2), value: bookmarks.bookmarks.map(\.id))
        .modifier(WorkspaceActivationObserver(browser: browser) { active in
            if !active { renamingBookmarkID = nil; draggedBookmarkID = nil }
        })
    }

    private func item(for bookmark: Bookmark) -> some View {
        Button { open(bookmark) } label: {
            HStack(spacing: 6) {
                SiteIcon(url: bookmark.url, size: 14)
                if let title = bookmark.visibleTitle {
                    Text(title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .fixedSize()
                }
            }
        }
        .buttonStyle(BookmarkButtonStyle())
        .help(bookmark.url.absoluteString)
        .accessibilityLabel(bookmark.displayTitle)
        .browserContextMenu { BookmarkMenu(bookmark: bookmark, bookmarks: bookmarks, browser: browser,
                                    rename: { renamingBookmarkID = bookmark.id }).actions }
        .popover(isPresented: Binding(get: { renamingBookmarkID == bookmark.id },
                                      set: { if !$0 { renamingBookmarkID = nil } }),
                 arrowEdge: .bottom) {
            RenameBookmarkForm(bookmark: bookmark) { title in
                bookmarks.rename(bookmark.id, to: title)
                renamingBookmarkID = nil
            }
        }
        .onDrag {
            draggedBookmarkID = bookmark.id
            return NSItemProvider(object: bookmark.url.absoluteString as NSString)
        }
        .onDrop(of: [.text], delegate: BookmarkDropDelegate(targetID: bookmark.id,
                                                            bookmarks: bookmarks,
                                                            draggedID: $draggedBookmarkID))
    }

    private func open(_ bookmark: Bookmark) {
        browser.open(bookmark.url, inNewTab: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
    }
}

/// Actions shared by bookmarks in the bar and favorites on the new tab page.
@MainActor
struct BookmarkMenu {
    let bookmark: Bookmark
    let bookmarks: BookmarkStore
    let browser: BrowserModel
    var rename: (@MainActor () -> Void)?

    var actions: [BrowserContextAction] {
        var items: [BrowserContextAction] = [
            .init(title: "Open", icon: .open) { browser.open(bookmark.url) },
            .init(title: "Open in New Tab", icon: .add) { browser.open(bookmark.url, inNewTab: true) },
            .separator,
            .init(title: "Copy Link", icon: .copy) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
            }
        ]
        if let rename { items.append(.init(title: "Rename…", icon: .rename, action: rename)) }
        items += [.separator, .init(title: "Delete Bookmark", icon: .trash, role: .destructive) { bookmarks.remove(bookmark.id) }]
        return items
    }
}

struct RenameBookmarkForm: View {
    let bookmark: Bookmark
    let save: (String) -> Void
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Bookmark")
                .font(.headline)
            TextField("Name (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { save(title) }
            HStack {
                Spacer()
                Button("Save") { save(title) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            title = bookmark.title ?? ""
            isFocused = true
        }
    }
}

private struct BookmarkButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) :
                        isHovered ? Color.primary.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct BookmarkDropDelegate: DropDelegate {
    let targetID: UUID
    let bookmarks: BookmarkStore
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
              let destinationIndex = bookmarks.bookmarks.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            bookmarks.move(draggedID, to: destinationIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil
    }
}
