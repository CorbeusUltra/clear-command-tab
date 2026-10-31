# Using ClearCmdTab

Hold Command while browsing with Command-Tab, or Command and Option with Command-Option-Tab. Add Shift to navigate backward, use the arrow keys to move, or press Escape to cancel. Release the opening modifier to switch. A quick tap switches immediately; holding shows the panel after 150 ms. Hidden apps are excluded from Command-Tab and included in Command-Option-Tab. Window-only switching is [parked](PARKED_FEATURES.md).

Settings provides glass appearance, launch at login, menu-bar visibility, optional yellow-button Hide, and status. The matte appearance uses opaque theme-adaptive colors. Pause suspends switching and the optional yellow-button behavior.

With **Yellow button hides app** enabled, a plain click on another app's yellow button hides all its windows instead of minimizing one. Command-click and Option-click retain normal macOS behavior. Regions are prepared in the background; uncertain controls use an accessibility hit-test fallback.

The menu-bar icon opens Pause / Resume, Settings, Guide, About and Quit. The icon dims while paused. Command-W closes Settings, Guide or About without quitting the service; Command-Q quits when one of these tabs is active. Reopening the app opens Settings even when the menu-bar icon is hidden. macOS can separately restrict its visibility; **Menu Bar Settings…** opens the system setting.

Terminated apps are removed on the macOS termination event, with a process-liveness backstop for delayed or missing events. While switching is enabled, a one-second health check attempts recovery if the keyboard event tap is silently disabled. Pause and Quit stop this check; Secure Input remains respected.
