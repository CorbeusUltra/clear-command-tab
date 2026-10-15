import AppKit
import ObjectiveC

enum GlassProfile: String {
    case current, altTab
    static let preferenceKey = "glassProfile"

    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "altTab") ?? .current
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
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.tintColor = nil
            if self == .altTab, let method = Self.variantSetter {
                // Independent, bounded adaptation of AltTab's clear-glass profile.
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
}
