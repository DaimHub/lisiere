# Profile switch fade

The profile button, Profiles menu, keyboard shortcuts and two-finger tab-strip swipe all activate the same `ProfileWindowController`. The visual transition belongs to `ProfileBrowserWindow`; switching and retaining browser models remain synchronous in the controller.

Profile workspaces crossfade in a stable `ZStack` over 220 ms with an ease-in-out curve. The toolbar, tab strip and page share one transition. A single window material stays at full opacity behind them. Each departing workspace retains its own color scheme; toolbar geometry and WebKit frames do not inherit the opacity animation. Layout, profile accents and transparent mascot artwork remain unchanged.

An inactive workspace is excluded from hit testing, accessibility and focused browser commands while it fades out. Reduce Motion selects an immediate identity transition. Switching to the same profile does not create a transition. There are no timers or queued profile changes, so rapid switching continues to select the latest request immediately.

Implementation starts from `82f7d56`, which matched the installed Release executable before this change. The older main checkout and its unrelated mascot work were preserved.
