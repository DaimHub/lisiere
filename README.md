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

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New tab / close tab / reopen closed tab | ⌘T / ⌘W / ⇧⌘T |
| Next / previous tab | ⇧⌘] / ⇧⌘[ or ⌃Tab / ⌃⇧Tab |
| Select tab 1–8 / last tab | ⌘1–8 / ⌘9 |
| Focus address / reload | ⌘L / ⌘R |
| Back / forward | ⌘[ / ⌘] |
| Show Web Inspector | ⌥⌘I |

The in-app Web Inspector shortcut uses a private WebKit hook because WebKit's public API only enables inspection through Safari's Develop menu. This hook needs review before distributing the app.
