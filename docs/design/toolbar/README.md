# Navigation toolbar

The default order is Profile, the Back/Forward/Reload group, Address & Search, then New Tab. The new-tab button uses the same 30 pt icon target, 2 pt padding, 10 pt corner radius and translucent background as the navigation group. BrowserChrome heights, page inset, profile tint and native menu behavior remain unchanged.

The tab strip no longer contains a layout toggle or a duplicate new-tab button. Tab layout remains available in Appearance settings, the View menu and the tab-strip context menu. Keyboard shortcuts remain available.

Settings > Appearance > Customize Toolbar edits the selected profile's toolbar immediately. Rows have explicit move buttons and named accessibility actions. Additional actions are Home, New Private Window, History, Downloads, Bookmarks Bar and Settings. Profile and Address & Search can move but cannot be removed; navigation remains one group. Restore Default restores the original four items. Profile copies inherit the toolbar as an independent preference. Old or unknown stored layouts recover the required controls without duplicating items.

At narrow widths the profile badge uses its icon and accessible profile name. Additional actions move to More Toolbar Actions before the address field becomes too narrow. Downloads appear automatically when there are downloads, unless already present in the configured toolbar. The configured Downloads button also works with an empty list.

Home opens the native start page in an existing empty tab, or a new tab when needed. It preserves the current page and its history, and does not change the preference for new tabs. Private windows retain their independent ephemeral preferences and visible Private badge; regular profile settings are not imported into them.

Native Release verification and test results are recorded separately in VERIFICATION.md.
