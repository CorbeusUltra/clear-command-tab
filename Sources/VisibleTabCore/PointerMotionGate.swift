import Foundation
import CoreGraphics

/// Window movement and tracking-area entry must never change keyboard selection.
public struct PointerMotionGate {
    private var anchor: CGPoint?

    public init() {}

    public mutating func reset(at point: CGPoint) { anchor = point }

    public mutating func accept(_ point: CGPoint) -> Bool {
        guard let anchor else { self.anchor = point; return false }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        guard dx * dx + dy * dy >= 1 else { return false }
        self.anchor = point
        return true
    }
}

public enum BadgeText {
    public static func normalized(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let number = Int(text), number == 0 { return nil }
        return text
    }
}
