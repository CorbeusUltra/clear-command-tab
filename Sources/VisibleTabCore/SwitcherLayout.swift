import Foundation
import CoreGraphics

/// Proportional geometry for the single-row app switcher, in logical screen points.
public struct SwitcherLayout: Sendable {
    public let size: CGSize
    public let tileSize: CGFloat
    public let spacing: CGFloat
    public let horizontalInset: CGFloat
    public let rowBottom: CGFloat
    public let labelHeight: CGFloat
    public let labelFontSize: CGFloat
    public let labelBottom: CGFloat
    public let documentWidth: CGFloat
    public let cornerRadius: CGFloat
    public var viewportWidth: CGFloat { max(1, size.width - horizontalInset * 2) }
    public var needsScrolling: Bool { documentWidth > viewportWidth + 0.5 }

    public init?(applicationCount: Int, availableSize: CGSize) {
        guard applicationCount > 0, availableSize.width > 0, availableSize.height > 0 else { return nil }
        let count = CGFloat(applicationCount)
        let maxWidth = availableSize.width * 0.9
        // A full-size tile includes the icon's own transparent padding. Adding another
        // inset here would make icons substantially smaller than Apple's switcher.
        let widthUnits = count + max(0, count - 1) / 9 + 4 / 9
        let heightLimit = max(24, (availableSize.height * 0.65 - 30) / 1.25)
        tileSize = min(144, heightLimit, max(40, floor(maxWidth / widthUnits)))
        let scale = tileSize / 144
        spacing = 16 * scale
        horizontalInset = min(32 * scale, maxWidth * 0.1)
        labelFontSize = max(11, 13 * scale)
        labelHeight = ceil(labelFontSize * 1.5)
        labelBottom = max(6, 10 * scale)
        rowBottom = labelBottom + labelHeight + 4 * scale
        documentWidth = count * tileSize + max(0, count - 1) * spacing
        size = CGSize(width: min(maxWidth, documentWidth + 2 * horizontalInset),
                      height: rowBottom + tileSize + 32 * scale)
        cornerRadius = min(64 * scale, size.height * 0.31)
    }

    public func tileFrame(at index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * (tileSize + spacing), y: 0, width: tileSize, height: tileSize)
    }

    public func labelFrame(at index: Int, scrollOrigin: CGFloat, textWidth: CGFloat) -> CGRect {
        // The caption follows the selected icon. Adjacent captions are absent, so long
        // names may use the empty band below neighboring icons, but never leave the panel.
        let width = min(viewportWidth, max(tileSize, min(240, textWidth + 12)))
        let center = horizontalInset + tileFrame(at: index).midX - scrollOrigin
        let x = min(max(horizontalInset, center - width / 2), size.width - horizontalInset - width)
        return CGRect(x: x, y: labelBottom, width: width, height: labelHeight)
    }
}
