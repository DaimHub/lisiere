# Default browser

Lisière uses the native Settings form and AppKit's asynchronous default-application API. Only **Make Default…** requests an association change. Opening Settings, refreshing the status, and following **Open System Settings…** never request one.

## Behavior

- `project.yml` already declares both `http` and `https`, with the `Viewer` role, for both distribution targets. HTML and XHTML declarations remain available for opening files; this action does not change their default application.
- Both URL schemes must resolve to this app's nonempty bundle identifier before Settings reports success. A split association is shown as partial; unavailable handler information is never treated as success.
- An in-flight request disables both actions. Each scheme is checked again before requesting it, so a macOS change that covers both schemes needs only one request.
- A cancellation, failure, or completion without a verified change stops the sequence. No automatic retry or rollback changes the user's choice.
- Status refreshes when General settings appears, when Lisière becomes active again, and after each request. A later verified change clears stale feedback.
- The fallback opens Desktop & Dock in System Settings, with the System Settings root as a fallback if the pane URL cannot open. The form also gives the manual path, since pane links are not a stable public API.

Apple documents consent as conditional: the system asks before completion when a change requires it. Do not click **Make Default…** during unattended validation on a user's Mac, even if you intend to cancel a dialog. See [NSWorkspace's default-application API](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)) and [Apple's default-browser instructions](https://support.apple.com/102362).

## External links

SwiftUI selects a scene before the app delegate receives an external URL. The normal window's `handlesExternalEvents(preferring:allowing:)` modifier makes an existing scene eligible, avoiding a new window for every link. The normal scene is also the fallback for new windows; the private scene never matches external events. See [Apple's scene-selection rules](https://developer.apple.com/documentation/swiftui/scene/handlesexternalevents(matching:)).

`BrowserAppDelegate` remains the single URL entry point. `ExternalURLRouter` opens links in the frontmost registered normal window through `BrowserModel.openInNewTabs`, preserving existing tabs and restoring a minimized destination. A sole blank tab is reused. If no normal window is available, links wait for a normal window. Closing a window unregisters its model immediately, even if SwiftUI retains that model.

## Validation

`DefaultBrowserFlowTests` injects a fake system service. It covers both schemes, split and unknown states, one or two requests, cancellation, permission failure, unchanged results, delayed refresh, repeated clicks, and System Settings failure. It never calls the real default-application setter. Existing `DefaultBrowserTests` checks the built app's declarations and external URL routing.

Safe native inspection:

1. Build and verify the Release app with a dedicated `DERIVED_DATA` directory. Do not replace another conversation's app in `/Applications`.
2. Open General settings. Check the current state, labels, layout, and keyboard navigation without clicking **Make Default…**.
3. Follow **Open System Settings…**. Verify Desktop & Dock opens, then return to Lisière and check the status again. Do not select another browser.
4. Compare the system's HTTP/HTTPS handlers before and after. Explicitly launching a URL in the test app verifies delivery, not the system's default-browser selection.
5. Send HTTP and HTTPS URLs with `open -a /path/to/the/isolated/Lisiere.app URL...`. With an existing page open, both URLs must append tabs to the same normal window. Also check multiple normal windows, a frontmost private window, a minimized normal window, and a closed normal window with only private browsing remaining. Existing tabs must survive, and private browsing must not receive external links.

The following requires the user's own action or a disposable macOS account: accept the native default-browser change, verify both schemes, open HTTP and HTTPS links from another app without specifying an application, then choose a different browser in System Settings and verify Lisière refreshes on return. Test keeping the current browser in a separate run. Do not infer these outcomes from mock tests or a successful build.
