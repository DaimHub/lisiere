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
