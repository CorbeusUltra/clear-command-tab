import Foundation
import CoreGraphics
import ClearCommandTabCore

struct PointerAndBadgeTests {
    func testStationaryPointerAndRealMovement() {
        var gate = PointerMotionGate()
        gate.reset(at: CGPoint(x: 800, y: 500))
        // Opening/reframing the panel and keyboard selection leave the pointer unchanged.
        expectFalse(gate.accept(CGPoint(x: 800, y: 500)))
        expectFalse(gate.accept(CGPoint(x: 800, y: 500)))
        expectFalse(gate.accept(CGPoint(x: 800.2, y: 500.1)))
        expectTrue(gate.accept(CGPoint(x: 802, y: 500)))
        expectFalse(gate.accept(CGPoint(x: 802, y: 500)))
        expectTrue(gate.accept(CGPoint(x: 802, y: 502)))
        gate.reset(at: CGPoint(x: 200, y: 100))
        expectFalse(gate.accept(CGPoint(x: 200, y: 100)))
        expectTrue(gate.accept(CGPoint(x: 199, y: 100)))
    }

    func testActualBadgeLabels() {
        expectNil(BadgeText.normalized(nil))
        expectNil(BadgeText.normalized(" \n"))
        expectNil(BadgeText.normalized("0"))
        expectEqual(BadgeText.normalized(" 1 "), "1")
        expectEqual(BadgeText.normalized("123"), "123")
        expectEqual(BadgeText.normalized("!"), "!")
        expectEqual(BadgeText.normalized("99+"), "99+")
    }
}
