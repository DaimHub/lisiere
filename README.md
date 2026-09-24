# Browser

A first macOS browser built with SwiftUI and Apple's WebKit for SwiftUI. Requires macOS 26 or later and Xcode 26 or later.

## Run

```sh
xcodegen generate
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Debug -derivedDataPath DerivedData build CODE_SIGNING_ALLOWED=NO
open DerivedData/Build/Products/Debug/Browser.app
```

The first version supports tabs, address entry and web search, back and forward navigation, reload, and standard keyboard shortcuts. Each tab owns a `WebPage`, so switching tabs keeps its page and navigation history alive. WebKit manages page rendering and persistent website data.

Each tab adds the installed Safari version to WebKit's user agent. Sites such as Google otherwise serve an older layout to the embedded WebKit default user agent.

## Tabs

Tabs share the strip width and shrink to icons when many are open. Hover a tab for a card with its title, address, and a preview of background pages. Drag tabs to reorder them. Right-click a tab to reload, duplicate, copy its link, or close other tabs and tabs to the right. Right-click the back or forward button to jump through history.

The window controls are repositioned to sit centered in the taller tab row. AppKit resets them during layout, so they are placed again after resizes and full screen changes.

## Vertical tabs

Switch between the tab strip and a sidebar of vertical tabs with View ▸ Use Vertical Tabs (⇧⌘S), the button at the top of the sidebar, or the tab context menu. The window controls move to the sidebar's top row, level with the address bar.

## New tabs and bookmarks

New tabs show a short greeting, a search field that focuses the address bar, and your bookmarks as favorites over a translucent background. Bookmark a page with ⌘D or the star in the address bar. The bookmarks bar can always show, show only on new tabs, or stay hidden (View ▸ Bookmarks Bar, or ⇧⌘B to toggle it). Drag bookmarks to reorder them, right-click to rename or delete, and ⌘-click to open one in a new tab. Bookmarks are stored in the app's user defaults.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New tab / close tab / reopen closed tab | ⌘T / ⌘W / ⇧⌘T |
| Next / previous tab | ⇧⌘] / ⇧⌘[ or ⌃Tab / ⌃⇧Tab |
| Select tab 1–8 / last tab | ⌘1–8 / ⌘9 |
| Focus address / reload | ⌘L / ⌘R |
| Back / forward | ⌘[ / ⌘] |
| Bookmark page / toggle bookmarks bar | ⌘D / ⇧⌘B |
| Switch between horizontal and vertical tabs | ⇧⌘S |
| Show Web Inspector | ⌥⌘I |

The in-app Web Inspector shortcut uses a private WebKit hook because WebKit's public API only enables inspection through Safari's Develop menu. The Inspector opens in its own window, because docking it inside the SwiftUI-managed web view makes the two fight over the page's frame. This hook needs review before distributing the app.
