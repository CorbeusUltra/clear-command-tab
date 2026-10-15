import Foundation
import CoreGraphics
import ClearCommandTabCore

final class SwitcherLayoutTests {
    func testCompactWidthGrowsWithApplicationCount() {
        let screen = CGSize(width: 1440, height: 900)
        let one = SwitcherLayout(applicationCount: 1, availableSize: screen)!
        let three = SwitcherLayout(applicationCount: 3, availableSize: screen)!
        let six = SwitcherLayout(applicationCount: 6, availableSize: screen)!
        expectTrue(one.size.width < three.size.width && three.size.width < six.size.width)
        expectEqual(one.tileSize, six.tileSize)
        expectFalse(six.needsScrolling)
    }

    func testLargeCountsShrinkBothWidthAndHeightBeforeScrolling() {
        let screen = CGSize(width: 1024, height: 768)
        let few = SwitcherLayout(applicationCount: 3, availableSize: screen)!
        let many = SwitcherLayout(applicationCount: 15, availableSize: screen)!
        let crowded = SwitcherLayout(applicationCount: 100, availableSize: screen)!
        expectTrue(many.tileSize < few.tileSize)
        expectTrue(many.size.height < few.size.height)
        expectFalse(many.needsScrolling)
        expectTrue(crowded.needsScrolling)
        for layout in [few, many, crowded] {
            expectTrue(layout.size.width <= screen.width * 0.9 + 0.5)
            expectTrue(layout.size.height < screen.height)
            expectTrue(layout.tileSize >= 40)
        }
    }

    func testCaptionTracksSelectionAndStaysInsidePanel() {
        let layout = SwitcherLayout(applicationCount: 6, availableSize: CGSize(width: 1440, height: 900))!
        let first = layout.labelFrame(at: 0, scrollOrigin: 0, textWidth: 70)
        let last = layout.labelFrame(at: 5, scrollOrigin: 0, textWidth: 70)
        expectTrue(first.midX < last.midX)
        for index in 0..<6 {
            let caption = layout.labelFrame(at: index, scrollOrigin: 0, textWidth: 1000)
            expectTrue(caption.minX >= 0 && caption.maxX <= layout.size.width)
            expectTrue(caption.maxY <= layout.rowBottom)
            expectTrue(layout.tileFrame(at: index).maxX <= layout.documentWidth + 0.5)
        }
    }

    func testCaptionAfterOverflowScrollAndSmallDisplay() {
        let layout = SwitcherLayout(applicationCount: 100, availableSize: CGSize(width: 800, height: 600))!
        let offset = layout.documentWidth - layout.viewportWidth
        let caption = layout.labelFrame(at: 99, scrollOrigin: offset, textWidth: 160)
        expectTrue(caption.minX >= 0 && caption.maxX <= layout.size.width)
        expectTrue(caption.midX > layout.size.width / 2)
        let narrow = SwitcherLayout(applicationCount: 1, availableSize: CGSize(width: 200, height: 220))!
        expectTrue(narrow.size.width <= 180)
        expectTrue(narrow.size.height <= 220)
        expectNil(SwitcherLayout(applicationCount: 0, availableSize: CGSize(width: 1440, height: 900)))
    }
}
