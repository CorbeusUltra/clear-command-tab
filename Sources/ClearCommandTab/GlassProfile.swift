import AppKit
import ObjectiveC

/// A solid surface with dynamic system colors, without a visual-effect view.
final class MatteSurface: NSView {
    let isSelection: Bool

    init(selection: Bool = false) {
        isSelection = selection
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = (isSelection ? NSColor.unemphasizedSelectedContentBackgroundColor : NSColor.windowBackgroundColor)
            .withAlphaComponent(1).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

enum GlassProfile: String, CaseIterable {
    case current, altTab, matte
    static let preferenceKey = "glassProfile"

    var title: String {
        switch self {
        case .current: return "fully transparent"
        case .altTab: return "original"
        case .matte: return "Matte"
        }
    }

    static var selected: Self {
        selected(in: .standard)
    }

    static func selected(in defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "altTab") ?? .current
    }

    static var altTabAvailable: Bool {
        if #available(macOS 26.0, *) { return variantSetter != nil }
        return false
    }

    @available(macOS 26.0, *)
    private static var variantSetter: Method? {
        guard let method = class_getInstanceMethod(NSGlassEffectView.self, NSSelectorFromString("set_variant:")),
              method_getNumberOfArguments(method) == 3,
              let argument = method_copyArgumentType(method, 2) else { return nil }
        let result = method_copyReturnType(method)
        defer { free(argument); free(result) }
        guard ["q", "Q"].contains(String(cString: argument)), String(cString: result) == "v" else { return nil }
        return method
    }

    func makeSurface(content: NSView) -> NSView {
        if self == .matte {
            let surface = MatteSurface()
            surface.addSubview(content)
            return surface
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.tintColor = nil
            if self == .altTab, let method = Self.variantSetter {
                // Bounded adaptation of AltTab's clear-glass profile; see docs/PROVENANCE.md.
                // Only the material variant changes; focus, refraction, and content remain native.
                typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
                let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
                setter(glass, NSSelectorFromString("set_variant:"), 3)
            }
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.addSubview(content)
        return blur
    }

    func makeSelection() -> NSView {
        if self == .matte { return MatteSurface(selection: true) }
        let selection = NSVisualEffectView()
        selection.material = .selection
        selection.blendingMode = .withinWindow
        selection.state = .active
        selection.isEmphasized = false
        selection.wantsLayer = true
        return selection
    }
}
