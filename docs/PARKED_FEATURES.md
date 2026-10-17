# Parked features

## Option-Tab window switching — 2026-10-17

Option-Tab and Shift-Option-Tab are not claimed by ClearCommandTab. There is no user-facing switch or hidden preference that enables window-only switching. The Guide and readiness message describe only Command-Tab and Command-Option-Tab.

The existing window-switching implementation is retained for possible future work:

- `ClearCommandTabCore/SwitcherMode.swift` retains the `.windows` mode, window recency/grouping and selection models. `SwitcherMode.starting(with:)` currently returns no mode for a chord without Command. This is the entry-point boundary that parks the feature.
- `AppController.swift` retains window-session navigation, discovery completion and reconciliation paths. They cannot be entered through the enabled shortcut dispatcher.
- `WindowTracker`, exact-window focus and panel title/layout support remain available. Window tracking and preferred-window focus are still used by app switching; removing them would change Command-Tab behavior.
- Model, layout and opt-in window-focus checks are kept to protect both the shared code and the retained feature. Passing them does not mean Option-Tab is an enabled product shortcut.

To reconsider the feature, review and restore its shortcut dispatch, update the Guide/README/readiness message, and rerun event dispatch, modifier release, window-session reconciliation and live OS checks. Re-enabling the entry point alone is not a product release checklist.

Git history records committed versions only. The latest working tree contains changes that have not been committed, so keeping this implementation in the source is deliberate. A private, history-free pre-retirement source snapshot is also preserved under the ignored `.local/parked/` directory. It is excluded from the publication export. No Git commit or publication was made for this change.
