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

## Studio

Studio is a pane on the right (⌘\\ or the sparkles button) where you describe a small tool, such as "a todo list", and Codex builds it as a self-contained web app. Each view is saved and can be reopened from the pane's title menu; follow-up requests change the selected view and keep its data.

Studio runs the [Codex CLI](https://github.com/openai/codex) the same way the Codex SDK does (`codex exec --json`), using your existing Codex sign-in. Install it with `npm install -g @openai/codex` and run `codex login` first. Views are stored in `~/Library/Application Support/dev.athas.browser/Views`, one folder per view, and served from `athas-view://<id>/`, so each view keeps its own `localStorage`.

Running the Codex CLI needs the app sandbox off. Unsigned development builds (the command above) already run without it; signed builds need `ENABLE_APP_SANDBOX: NO` in `project.yml`.

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
| Show or hide Studio | ⌘\\ |
| Show Web Inspector | ⌥⌘I |

The in-app Web Inspector shortcut and the Inspect Element context menu item use private WebKit hooks because WebKit's public API only enables inspection through Safari's Develop menu. The Inspector docks inside the page or opens in its own window, and remembers which one you chose last. Each hook is checked before use, so the Inspector is simply unavailable if WebKit changes it. These hooks need review before distributing the app.
