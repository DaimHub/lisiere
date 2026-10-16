# Navigation toolbar

The default order is Profile, a group containing Back, Forward and Reload, Address & Search, New Tab, then All Actions. New Tab and All Actions use the same 30 pt icon target, 2 pt padding, 10 pt corner radius and translucent background as grouped navigation buttons. BrowserChrome heights, page inset, profile tint and native menus remain unchanged.

The tab strip has no layout toggle or duplicate New Tab button. Tab layout remains available in Appearance settings, the View menu and the tab-strip context menu. Keyboard shortcuts remain available.

## Customization

Settings > Appearance > Customize Toolbar edits the selected profile immediately. All Actions also opens this editor for the current window, including its ephemeral private preferences.

The editor uses a native NSOutlineView with reusable cells and gap insertion feedback. Drag a row between rows to reorder it, onto a standalone row to group the two, or onto a group to join it. Groups can be moved as a whole. Child rows can move within or out of their group. Dropping onto a child inserts beside that child, without creating nested groups. A local custom pasteboard type and a source-view check keep external drops out of this settings editor.

The arrows remain available. They move whole groups among top-level entries, or individual buttons within their group. The link button offers Group With; the split button separates the whole group or takes one child out. One-button groups automatically become ordinary buttons. Group members share one rounded background on the real toolbar. Profile and Address & Search can join groups and move but cannot be removed. Restore Default returns to the initial layout.

Every action can be added individually: Back, Forward, Reload, New Tab, Home, New Private Window, History, Downloads, Bookmarks Bar, Settings and All Actions. The ellipsis opens a native menu containing all actions, including those absent from the visible toolbar, plus a profile submenu, address focus and Customize Toolbar. Navigation enablement/loading states and private-mode restrictions match the visible controls.

## Persistence and layout

`navigationToolbarLayoutV2` stores a versioned JSON payload with stable group IDs and action identifiers. The legacy `navigationToolbarItems` array is preserved for rollback. On upgrade, its navigation item becomes a Back/Forward/Reload group in the same position, all other customized positions are retained, and All Actions is appended. Existing V2 choices, including removing All Actions, remain unchanged. Unknown/duplicate controls and malformed records are normalized while keeping Profile and Address & Search available. Profile copies inherit independent layout settings.

At narrow widths the profile badge uses its icon and accessible name. Optional actions leave the visible bar before the address field becomes too narrow; they stay available in All Actions. If All Actions was removed, overflow adds it temporarily. This never changes saved groups or ordering. Downloads also appear automatically when downloads exist, without duplicating a configured Downloads button.

Home opens the native start page in an existing empty tab, or a new tab when needed. It preserves the current page and its history, and does not change the preference for new tabs. Private windows retain independent ephemeral preferences and their visible Private badge.

Initial implementation evidence is in VERIFICATION.md. Grouping, drag support and All Actions evidence is in GROUPS-VERIFICATION.md.
