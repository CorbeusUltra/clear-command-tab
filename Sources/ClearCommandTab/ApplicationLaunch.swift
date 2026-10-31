import AppKit
import Carbon

/// Explicit launches (Finder/Spotlight) open Settings once, including a cold
/// start. Login and service launches continue running quietly in the background.
enum ApplicationLaunch {
    static func opensSettings(_ event: NSAppleEventDescriptor) -> Bool {
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let origin = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return origin != AEKeyword(keyAELaunchedAsLogInItem) && origin != AEKeyword(keyAELaunchedAsServiceItem)
    }
}
