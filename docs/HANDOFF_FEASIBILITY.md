# Handoff feasibility investigation

Date: 2026-10-25. Research only; application code, installed app, preferences,
permissions and running services were not changed.

## Conclusion

Adding a selectable Handoff entry to ClearCommandTab appears feasible by bridging
the Dock's existing accessibility element. Confidence is sufficient to justify a
prototype, but an actual iPhone-to-Mac transfer has not been tested in this study.

The proposed feature exposes the system's available continuation. macOS continues
to choose the receiving app and transfer the activity. ClearCommandTab would not
implement its own iPhone discovery, activity transport or video synchronization.

## Evidence and its limits

Apple documents Handoff in both the Dock and the native Command-Tab switcher.
It requires a compatible source app and the usual device/account setup. See
[Apple's Handoff instructions](https://support.apple.com/en-us/102426).

The public NSUserActivity APIs describe activities produced or received by an app;
ordinary native activity routing depends on the activity type and developer team.
Web-browser continuation is a separate documented case. No documented public API
for enumerating and accepting arbitrary apps' pending Handoff offers was identified.
Declaring NSUserActivity support in ClearCommandTab would not by itself provide a
replacement for the Dock's list. See
[Implementing Handoff](https://developer.apple.com/documentation/foundation/implementing-handoff-in-your-app)
and the [archived programming guide](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/Handoff/AdoptingHandoff/AdoptingHandoff.html).

A published [Talon integration by phillco](https://gist.github.com/phillco/4b52e50afc714e70511b1484afc92e59)
finds Dock elements with role AXDockItem and subrole AXHandoffDockItem, reads
AXTitle/AXStatusLabel and invokes AXPress. This is a concrete implementation
reference, not a compatibility guarantee for current macOS.

Read-only inspection of this Mac established:

- macOS version: 27.0.1, build 26A434.
- The installed Dock executable contains the exact string AXHandoffDockItem.
  This is static corroboration, not proof that a live offer is currently exposed.
- A fresh Swift research process returned AXIsProcessTrusted() == false. No
  authorization was requested and no live Dock traversal or activation was tried.
  This says nothing about the installed ClearCommandTab GUI's permission.

The action would use the public
[AXUIElementPerformAction API](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction).
The Handoff-specific Dock structure is undocumented and may change independently.

## Why the current app omits it

- ApplicationTracker builds history from running applications. A remote activity
  is a distinct action, and its receiving app may not yet be running.
- DockBadgeReader.swift currently accepts only AXApplicationDockItem entries with
  a nonempty badge and an app URL. It intentionally skips other Dock subroles.
- SwitcherTargetID currently represents an application PID or a window identity;
  every target exposes a nonoptional PID.
- AppController.candidateIDs() builds its app list from visible running apps.
- AppController.finishSelection() requires a running app and commits focus to it.
  Activating Safari normally would not accept an incoming Safari Handoff activity.

Consequently, adding a badge or a second Safari icon alone is insufficient.

## Proposed implementation, subject to product choices

1. Add a bounded asynchronous Dock reader for Handoff offers, reusing the existing
   accessibility approach. Discovery must not depend on AXStatusLabel or AXURL
   being present. Verify available attributes/actions in a live probe first.
2. Represent continuation as a distinct target with its own identity, presentation
   and activation path. Do not invent a PID or add it to app recency history.
   Audit existing PID assumptions, icon loading, focus handling and H/Q actions.
3. Show a clearly differentiated entry, for example an app icon with a device
   marker and a Handoff label. Confirm how to resolve the app icon; permit a generic
   continuation icon when reliable app metadata is unavailable. Source-device
   strings from AXStatusLabel should be treated as optional, undocumented hints.
4. When the user confirms the target, dismiss the panel and invoke AXPress on the
   corresponding current Dock element. Do not substitute ordinary app activation.
   Check identity and freshness so an expired offer cannot activate a newer one.
5. Keep accessibility messaging off the keyboard callback and main thread, with
   bounded timeouts and cancellation. A scan must not delay ordinary quick switches.
   Reuse session refresh opportunities initially; evaluate supported Dock observer
   notifications before introducing idle polling.
6. Handle disappearance, permission loss and Dock restart without retaining stale
   targets or disrupting ordinary application switching. An ambiguous action timeout
   must not cause an automatic repeat that could accept the activity twice.

The recommended product direction is a separate entry in the normal application
switcher. Placement and behavior when an offer arrives during a gesture need user
agreement before implementation. In particular, app-to-app quick Command-Tab should
remain predictable when a Handoff entry is present. No choice was applied here.

Existing Accessibility authorization should be sufficient for this approach;
that expectation needs confirmation in the installed GUI. No additional permission
or account connection is inherently required by the proposed design.

## YouTube scope

The acceptance criterion is parity with clicking the system's Handoff entry.
Support by the current native YouTube iPhone app was not established. Test native
YouTube and YouTube in Safari separately: they may advertise different activities.

For browser activities, Apple documents continuation using a webpage URL. Opening
the correct video and resuming its exact playback time are separate results. The
position depends on information supplied by the source and on the receiving player;
ClearCommandTab cannot promise it just by accepting Handoff. If the system offers
no activity, this integration has nothing to display.

## Validation required before shipping

| Scenario | Required result |
| --- | --- |
| Safari page open on unlocked nearby iPhone | Identify live Handoff attributes and advertised actions |
| Confirm the corresponding switcher target | Same continuation as the Dock, including when browser is closed |
| YouTube in native app versus Safari | Record offer availability, destination, video identity and playback position separately |
| Browser already running or hidden | Continuation is distinct from ordinary browser activation |
| Offer disappears or changes while cycling | Preserve local selection where possible; never accept a different offer accidentally |
| Escape or quick local Command-Tab | No continuation or delayed activation |
| H/Q on continuation target | No hide/quit request sent to Dock or receiving app |
| Dock restart, denied access or slow response | Bounded failure; normal switching stays usable |

Pure selection tests can cover mixed target identities and reconciliation. Live
testing is essential for discovery and AXPress: static inspection cannot validate
the transfer itself. After an implemented update, follow AGENTS.md for a single
build/sign, graceful replacement, installation and relaunch.

Estimated engineering complexity: moderate. The likely bridge is small; the main
work is integrating a non-application target without regressing selection, focus
or latency. The remaining feasibility gate is a live Dock discovery/action probe
with a known working Handoff offer.
