# Appearance

Settings > Appearance > App theme offers System, Light, and Dark. The choice is saved under `browserAppearance` in the app's existing UserDefaults domain. Missing or unknown values fall back to System.

Websites follow Lisière by default. The **Use a separate theme for websites** switch reveals a Website theme picker with Light and Dark. The first activation starts with Lisière's current effective appearance. Switching it off immediately restores inheritance; switching it back on restores the last separate choice, even after relaunch. `webPageAppearance` stores the active website preference (`followApp`, `light`, or `dark`); `separateWebPageAppearance` remembers the last explicit choice. Missing or unknown active values fall back to `followApp`.

`AppearanceStore` owns this preference and applies it through `NSApplication.appearance` before the first window opens. System sets the property to `nil`, returning control to macOS, including subsequent system appearance changes. Light uses Aqua; Dark uses Dark Aqua. The settings picker observes the same store.

Windows, sheets, popovers, menus, SwiftUI materials, and AppKit text fields inherit this application appearance. Keep native controls free of local `preferredColorScheme` or `NSAppearance` overrides so the browser chrome and field editor stay consistent. The intentional exception is each `WKWebView`: `AppearanceStore` applies its separate website appearance, or `nil` to inherit the app. A weak registry updates existing and background web views without retaining closed or suspended tabs. `BrowserTab.install` attaches new, popup, and restored web views before navigation. BrowserChrome dimensions and the existing native components remain the layout source of truth.

Private windows follow the same preference. Their violet tint and explicit Private label distinguish them in both appearances. Theme changes do not alter private data-store ownership or persistence.

WebKit receives the native appearance and evaluates `prefers-color-scheme`. Websites decide which styles and color schemes they support. No CSS, JavaScript, image inversion, navigation, or page reload is injected to force a dark site. A site without dark styles can remain white.

The address field uses the native keyboard-focus color with a two-point outline. Selected address suggestions pair AppKit's selected-content background with its selected-control text color. Bookmark hints use secondary text. Private badge accents differ between light and dark to retain readable text over the existing violet treatment.

## Regression checks

`AppearanceTests` covers both preference fallbacks, persistence and relaunch, switch activation and remembered choices, existing and newly created native windows/panels/fields, all nine app/website combinations in regular and private browsers, background and restored tabs, weak ownership, live WebKit media-query updates, absence of reloads, and preservation of author-specified colors on adaptive and light-only pages. The tests restore the app appearance and use disposable preferences.

For visual validation, build a Release app with its own `DERIVED_DATA` and temporary bundle identifier when another Lisière instance is running. Keep the normal signing and Release entitlements; change only the validation bundle identifier through an external xcconfig, never the checked-in app identity. Do not install over `/Applications/Lisiere.app` or use another browser's profile.

Check these paths in both Light and Dark, then return to System:

- Switch with regular and private windows already open; open another window afterward.
- Check horizontal and vertical tabs, active/inactive tabs, new-tab pages, bookmarks, and tab menus.
- Use Command-L, enter a matching address, and select suggestions with the arrow keys. Check caret, selection, text, and focus outline.
- Check all Settings sections, native JavaScript prompt sheets, history/find surfaces, and light-only websites.
- Switch while a page using `matchMedia` is open. Confirm it updates without navigation and that explicitly white content stays white.
- Leave the website switch off: pages follow the app. Enable it and check app Light with website Dark, then app Dark with website Light, including private windows and new/background tabs.
- Disable the switch: the website picker disappears and pages follow the app again. Re-enable it: the previous separate choice returns.
- Quit and relaunch; confirm both choices and the switch state persist. System must release the app override.

App-wide appearance inheritance follows [Apple's documented NSApplication behavior](https://developer.apple.com/documentation/appkit/nsapplication/appearance). Web content uses [WebKit's native dark-mode support](https://webkit.org/blog/8840/dark-mode-support-in-webkit/).

## Validation on 2026-10-16

- 118 XCTest tests passed, including nine appearance tests and the complete upstream suite.
- The canonical Release build passed strict deep signature verification. The isolated validation Release also passed startup smoke with the standard local Release sandbox and hardened runtime.
- The built native Release was inspected on macOS 27.0 (26A428): light/dark settings, both tab layouts, address focus and selected suggestions, private windows, tab menus, native prompt sheets, and history. Separate app/site themes worked in both directions; switch-off inheritance, switch-on recall, and relaunch persistence were observed with an adaptive local page. Its media query changed without reloading; author-fixed white content and a light-only page stayed white.
- macOS 26, a live system-wide light/dark change while System is selected, full VoiceOver/Increase Contrast coverage, and distribution signing/notarization were not exercised. Find-field keyboard validation was inconclusive. The pre-existing private welcome text truncation at minimum height remains outside this appearance change.

The validation used a separate app identifier and profile. No installed browser or user profile was replaced.
