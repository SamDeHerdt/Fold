//
//  FoldStyle.swift
//  Fold
//
//  Licensed under the GNU GPLv3
//

import SwiftUI

/// UserDefaults keys for Fold's own presentation settings.
enum FoldKey {
    nonisolated static let appearance = "FoldAppearanceV1"
    static let glass = "FoldGlassV1"
    static let look = "FoldLookV1"
    /// Maximum drawer length in points; 0 means "as wide as the screen allows".
    static let maxWidth = "FoldMaxWidthV1"
    static let motion = "FoldMotionV1"
    /// Seconds the pointer rests on the menu-bar icon before the drawer opens.
    static let hoverDelay = "FoldHoverDelayV1"
    /// Extra points between icons inside the drawer (drawer only).
    static let iconSpacing = "FoldIconSpacingV1"
    /// Icon size inside the drawer, as a multiple of the menu bar's (0.7–1.4).
    static let iconScale = "FoldIconScaleV1"

    /// Rows visible in the grid and column arrangements before they scroll.
    static let maxRows = "FoldMaxRowsV1"
    /// Show each app's name beside its icon in the column arrangement.
    static let columnNames = "FoldColumnNamesV1"
    /// Animation speed: 1 is normal, lower is slower, higher is faster.
    static let motionSpeed = "FoldMotionSpeedV1"
    /// Show a dot on the menu-bar icon when a hidden icon changes.
    static let attentionDot = "FoldAttentionDotV1"

    /// The colour of the Accent look and of coloured glass, as "#RRGGBB";
    /// empty follows the system accent colour.
    static let tint = "FoldTintColorV1"

    static var attentionDotEnabled: Bool {
        UserDefaults.standard.object(forKey: attentionDot) as? Bool ?? true
    }

    /// Live icons (default): the drawer shows the real, minimal menu-bar
    /// icons, captured from the menu bar — needs Screen Recording. Off: each
    /// item's greyscale app icon (system items get a symbol) and Fold never
    /// looks at the screen.
    nonisolated static let liveIcons = "FoldLiveIconsV1"

    nonisolated static var liveIconsEnabled: Bool {
        UserDefaults.standard.object(forKey: liveIcons) as? Bool ?? true
    }

    /// 0.4 s: long enough that sweeping across the menu bar never opens the
    /// drawer; the pointer also has to rest (see ControlItem's hover watch).
    static var hoverDelaySeconds: Double {
        UserDefaults.standard.object(forKey: hoverDelay) as? Double ?? 0.4
    }
}

/// How the drawer opens and closes. Every motion starts at the menu-bar icon.
enum FoldMotion: String, CaseIterable, Identifiable {
    case liquid
    case bubbles
    case pop
    case hinge
    case cascade
    case materialize
    case drop
    case fade
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquid: "Liquid"
        case .bubbles: "Bubbles"
        case .pop: "Pop"
        case .hinge: "Fold"
        case .cascade: "Cascade"
        case .materialize: "Materialize"
        case .drop: "Glide"
        case .fade: "Fade"
        case .none: "None"
        }
    }

    var symbol: String {
        switch self {
        case .liquid: "drop.fill"
        case .bubbles: "circle.grid.3x3.fill"
        case .pop: "sparkle"
        case .hinge: "rectangle.portrait.bottomhalf.inset.filled"
        case .cascade: "ellipsis"
        case .materialize: "camera.metering.center.weighted"
        case .drop: "arrow.down.to.line"
        case .fade: "circle.lefthalf.filled"
        case .none: "nosign"
        }
    }

    var caption: String {
        switch self {
        case .liquid: "Pours out of the icon and melts into the bar"
        case .bubbles: "A chip per icon pops up, then they merge"
        case .pop: "Springs out of the icon"
        case .hinge: "Swings down like a hinged flap"
        case .cascade: "Icons pop in one after another"
        case .materialize: "Pulls into focus"
        case .drop: "Settles into place, like a macOS menu"
        case .fade: "Fades in"
        case .none: "Appears at once"
        }
    }

    /// Hidden debug knob: `defaults write com.samdeherdt.fold FoldMotionDebugSlowdown 6`
    /// plays every open/close six times slower, for frame-by-frame review.
    static var debugSlowdown: Double {
        max(1, UserDefaults.standard.double(forKey: "FoldMotionDebugSlowdown"))
    }

    static var current: FoldMotion {
        FoldMotion(rawValue: UserDefaults.standard.string(forKey: FoldKey.motion) ?? "") ?? .liquid
    }

    /// The Speed setting (0.4–2), 1 when unset.
    static var speed: Double {
        let stored = UserDefaults.standard.object(forKey: FoldKey.motionSpeed) as? Double ?? 1
        return min(max(stored, 0.4), 2)
    }

    /// Closing follows the Speed setting less than opening does: a slow,
    /// showy open is pleasant, a slow close is in the way.
    private static var closeSpeed: Double {
        max(speed, 0.75)
    }

    var openAnimation: Animation? {
        baseOpenAnimation?.speed(Self.speed / Self.debugSlowdown)
    }

    var closeAnimation: Animation? {
        baseCloseAnimation?.speed(Self.closeSpeed / Self.debugSlowdown)
    }

    private var baseOpenAnimation: Animation? {
        switch self {
        case .liquid: .spring(duration: 0.8, bounce: 0.2)
        case .bubbles: .spring(duration: 0.75, bounce: 0.2)
        case .pop: .spring(duration: 0.5, bounce: 0.42)
        case .hinge: .spring(duration: 0.6, bounce: 0.3)
        case .cascade: .spring(duration: 0.4, bounce: 0.2)
        case .materialize: .timingCurve(0.22, 1, 0.36, 1, duration: 0.5)
        case .drop: .spring(duration: 0.42, bounce: 0)
        case .fade: .easeOut(duration: 0.25)
        case .none: nil
        }
    }

    private var baseCloseAnimation: Animation? {
        switch self {
        case .liquid: .timingCurve(0.22, 1, 0.36, 1, duration: 0.24)
        case .bubbles: .timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
        case .pop: .easeIn(duration: 0.16)
        case .hinge: .timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
        case .cascade: .easeIn(duration: 0.14)
        case .materialize: .easeIn(duration: 0.16)
        case .drop: .timingCurve(0.22, 1, 0.36, 1, duration: 0.15)
        case .fade: .easeIn(duration: 0.12)
        case .none: nil
        }
    }

    /// How long the panel stays up after a close starts, matching `closeAnimation`.
    var closeDelay: TimeInterval {
        baseCloseDelay * Self.debugSlowdown / Self.closeSpeed
    }

    private var baseCloseDelay: TimeInterval {
        switch self {
        case .liquid: 0.24
        case .bubbles: 0.22
        case .pop: 0.16
        case .hinge: 0.2
        case .cascade: 0.14
        case .materialize: 0.16
        case .drop: 0.15
        case .fade: 0.12
        case .none: 0
        }
    }

    /// Motions that pour out of the menu-bar button reach up over the menu
    /// bar, so their window extends over it. The extra strip stays transparent.
    var poursFromButton: Bool {
        self == .liquid
    }

    /// Motions drawn as blobs that settle into the bar.
    var usesBlobs: Bool {
        self == .liquid || self == .bubbles
    }

    func pourInset(menuBarHeight: CGFloat) -> CGFloat {
        poursFromButton ? menuBarHeight : 0
    }

    /// Every motion plays in every arrangement; rows, columns and grids each
    /// get their own blob choreography in `FoldMorphReveal`.
    func effective(inRow _: Bool) -> FoldMotion {
        self
    }
}

/// The surface drawn behind the drawer's icons.
enum FoldLook: String, CaseIterable, Identifiable {
    case glass
    case frosted
    case solid
    case outline
    case minimal
    case accent
    case paper
    case obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        case .outline: "Outline"
        case .minimal: "Minimal"
        case .accent: "Accent"
        case .paper: "Paper"
        case .obsidian: "Obsidian"
        }
    }

    /// Coloured looks carry white icons whatever the appearance, unless the
    /// chosen colour is a light one.
    var forcesLightIcons: Bool {
        self == .obsidian || (self == .accent && !FoldTint.isBright)
    }

    /// Paper is a light card whatever the appearance, so its icons are dark;
    /// so is an Accent look in a light colour.
    var forcesDarkIcons: Bool {
        self == .paper || (self == .accent && FoldTint.isBright)
    }

    static var current: FoldLook {
        FoldLook(rawValue: UserDefaults.standard.string(forKey: FoldKey.look) ?? "") ?? .glass
    }
}

enum FoldWidth {
    /// Clear space the drawer window keeps around the bar so its shadow (and
    /// Pop/Elastic overshoot) isn't cut off by the window's edge.
    static let sideMargin: CGFloat = 14
    static let bottomMargin: CGFloat = 16

    static let minimum: CGFloat = 120
    static let screenMargin: CGFloat = 48

    static func screenCap(for screenWidth: CGFloat) -> CGFloat {
        screenWidth - screenMargin
    }

    /// The drawer's length limit for a stored slider value. Icons past it scroll.
    static func cap(stored: Double, screenWidth: CGFloat) -> CGFloat {
        let screenCap = screenCap(for: screenWidth)
        guard stored > 0 else { return screenCap }
        return min(screenCap, max(minimum, CGFloat(stored)))
    }
}

/// The pointer in AppKit screen coordinates, read straight from the window
/// server. `NSEvent.mouseLocation` can lag in a background app that isn't
/// receiving mouse events.
enum FoldPointer {
    static var location: NSPoint {
        guard let cg = CGEvent(source: nil)?.location else { return NSEvent.mouseLocation }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: cg.x, y: primaryHeight - cg.y)
    }
}

/// Where Fold's menu-bar icon is on a given screen, in AppKit coordinates.
/// The real status-item window lives on one display; the copies macOS draws in
/// other displays' menu bars aren't windows Fold can query, but menu bars are
/// laid out from the right, so the copy sits the same distance from its
/// display's top-right corner.
/// The hidden icons that changed since the drawer was last open; the drawer
/// marks them with a dot so you can see which app wanted attention.
@MainActor
@Observable
final class FoldAttention {
    static let shared = FoldAttention()
    /// Icons whose image changed while the drawer was closed.
    var tags = Set<MenuBarItemTag>()
    /// Icons whose app currently shows a badge on its Dock icon.
    var badgeTags = Set<MenuBarItemTag>()

    func marks(_ tag: MenuBarItemTag) -> Bool {
        tags.contains(tag) || badgeTags.contains(tag)
    }
}

/// Reads which running apps have a badge on their Dock icon (unread counts
/// and the like), through the Dock's accessibility tree.
enum FoldDockBadges {
    nonisolated static func badgedAppURLs() -> Set<URL> {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }
        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return value as? [AXUIElement] ?? []
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var result = Set<URL>()
        for list in children(app) {
            for item in children(list) {
                var label: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &label) == .success,
                      let text = label as? String, !text.isEmpty
                else { continue }
                var url: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url) == .success,
                      let appURL = url as? URL
                else { continue }
                result.insert(appURL.standardizedFileURL)
            }
        }
        return result
    }
}

enum FoldChevron {
    static func frame(of window: NSWindow?, on screen: NSScreen) -> CGRect? {
        guard let window, let home = window.screen ?? NSScreen.screens.first else { return nil }
        let frame = window.frame
        guard home != screen else { return frame }
        return CGRect(
            x: screen.frame.maxX - (home.frame.maxX - frame.minX),
            y: screen.frame.maxY - (home.frame.maxY - frame.minY),
            width: frame.width,
            height: frame.height
        )
    }
}

/// Open/closed state shared by the drawer panel and its SwiftUI content, so
/// the panel can let the content morph back into the chevron before it hides.
@Observable
final class FoldMorph {
    var isOpen = false
    /// Whether the screen behind the bar is bright, sampled each time the
    /// drawer opens. Translucent looks pick their icon colour from it, since
    /// Liquid Glass takes on whatever is behind it. Nil until first sampled.
    var backdropIsBright: Bool?
    /// The menu-bar icon's centre, in the drawer window's coordinates; set by
    /// the panel whenever it positions itself. Motions start from here.
    var anchorWindowX: CGFloat?

    // Keyboard control (drawer opened with the shortcut).
    /// True while the drawer holds the keyboard.
    var keyboardActive = false
    /// The icon the arrow keys are on.
    var selectedWindowID: CGWindowID?
    /// Bumped to make the selected icon open, as if clicked.
    var activateRequest = 0
    /// Icons in display order, for arrow keys and type-to-jump.
    var keyItems: [FoldKeyItem] = []
    /// Column arrangement with names: each icon is a labelled row.
    var showsNames = false
    /// The one icon the pointer is over. Shared, so a row that scrolls out
    /// from under a still pointer can't stay highlighted alongside another.
    var hoveredWindowID: CGWindowID?
    /// The motion in play, so icons can stagger themselves for Cascade.
    var motion = FoldMotion.liquid
}

struct FoldKeyItem: Equatable {
    let id: CGWindowID
    let name: String
}

enum FoldBackdrop {
    /// Average perceived brightness (0–1) of an image, from an 8×8 downsample.
    static func brightness(of image: CGImage) -> Double? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return total / Double(side * side) / 255
    }
}

/// The bar's outline: a capsule for a single row, a rounded rectangle when the
/// icons are arranged in a grid or column.
struct FoldBarShape: InsettableShape {
    /// Corner radius; nil means a full capsule.
    var radius: CGFloat?
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard let radius else { return Capsule().path(in: r) }
        let corner = min(radius, min(r.width, r.height) / 2)
        return RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: r)
    }

    func inset(by amount: CGFloat) -> FoldBarShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

let foldPaperColor = Color(red: 0.97, green: 0.95, blue: 0.91)

let foldObsidianColor = Color(white: 0.09)

/// A fine highlight along the top edge that fades down the sides: the detail
/// that makes a flat fill read as a lit object.
func foldTopHighlight(_ strength: Double) -> LinearGradient {
    LinearGradient(colors: [Color.white.opacity(strength), Color.white.opacity(strength * 0.08)], startPoint: .top, endPoint: .bottom)
}

/// The colour chosen for the Accent look and coloured glass.
enum FoldTint {
    static let presets = ["#0A84FF", "#30D5C8", "#34C759", "#FFD60A", "#FF9F0A", "#FF375F", "#BF5AF2", "#8E8E93"]

    static func color(_ hex: String) -> Color {
        nsColor(hex).map(Color.init(nsColor:)) ?? .accentColor
    }

    static func nsColor(_ hex: String) -> NSColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    static func hex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    /// Whether the stored colour is light enough to need dark icons on it.
    static var isBright: Bool {
        let stored = UserDefaults.standard.string(forKey: FoldKey.tint) ?? ""
        guard let rgb = (nsColor(stored) ?? NSColor.controlAccentColor).usingColorSpace(.sRGB) else { return false }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.62
    }
}

/// Draws the selected Fold look behind content, in the given shape.
struct FoldSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.glass) private var glass = "system"
    @AppStorage(FoldKey.tint) private var tint = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { colorScheme == .dark }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch FoldLook(rawValue: look) ?? .glass {
        case .glass where !reduceTransparency:
            if glass == "clear" {
                content.glassEffect(.clear, in: shape)
            } else if glass == "color" {
                // Liquid Glass with a wash of the chosen colour: still
                // see-through, still refracting what is behind it.
                content.glassEffect(.regular.tint(FoldTint.color(tint).opacity(0.38)), in: shape)
            } else if glass == "tinted" {
                // Glass tint alone barely shifts the tone over a white (or black)
                // backdrop, so a real layer sits on the glass to hold the chosen
                // appearance: dark stays dark, light stays light, anywhere.
                content
                    .background((isDark ? Color(white: 0.08) : Color.white).opacity(0.72), in: shape)
                    .glassEffect(.regular, in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        case .frosted where !reduceTransparency:
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(isDark ? 0.14 : 0.6), lineWidth: 0.5))
        case .accent where !reduceTransparency:
            content.glassEffect(.regular.tint(FoldTint.color(tint).opacity(0.7)), in: shape)
        case .accent:
            content.background(FoldTint.color(tint), in: shape)
        case .paper:
            // The shadow belongs to the card, not to the icons on it.
            content
                .background(foldPaperColor.shadow(.drop(color: .black.opacity(0.2), radius: 5, y: 2)), in: shape)
                .overlay(shape.strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
        case .obsidian:
            // Flat near-black; the hairline top highlight is its only detail.
            content
                .background(foldObsidianColor, in: shape)
                .overlay(shape.strokeBorder(foldTopHighlight(0.3), lineWidth: 1))
        case .outline:
            content
                .background((isDark ? Color.black : Color.white).opacity(0.28), in: shape)
                .overlay(shape.strokeBorder((isDark ? Color.white : Color.black).opacity(0.4), lineWidth: 1))
        case .minimal:
            content.shadow(color: .black.opacity(isDark ? 0.55 : 0.25), radius: 2.5, y: 0.5)
        default:
            // Solid, and the Reduce Transparency fallback for glass/frosted.
            content
                .background(isDark ? Color(white: 0.14) : Color(white: 0.95), in: shape)
                .overlay(shape.strokeBorder(foldTopHighlight(isDark ? 0.2 : 0.9), lineWidth: 1))
                .overlay(shape.strokeBorder((isDark ? Color.white : Color.black).opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Reveals a bar with the chosen motion. `anchorX` is the menu-bar button's
/// centre along the bar and `pourCenterY` its centre above the bar (negative),
/// both in the bar's own coordinates unless `anchorInWindow` is set.
struct FoldMorphReveal: ViewModifier, Animatable {
    /// 0 = folded into the button, 1 = fully open.
    var progress: CGFloat

    /// Without this SwiftUI only tweens the frames this modifier produces; the
    /// goo Canvas would get the final progress at once and never play.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var anchorX: CGFloat?
    let motion: FoldMotion
    let pourCenterY: CGFloat
    /// Icons in the bar; Liquid and Bubbles burst one ball out per icon.
    var slotCount: Int = 7
    /// When true, `anchorX` is in window coordinates and is converted to the
    /// bar's own space at draw time (the bar's real position can differ from
    /// any estimate, e.g. when icon widths differ from their cached sizes).
    var anchorInWindow = false
    /// Corner radius for grid/column bars; nil keeps the single-row capsule.
    var cornerRadius: CGFloat?
    /// Icons per row in a grid; 1 for a column.
    var columns = 1

    /// This modifier with `anchorX` resolved into the geometry's local space.
    private func local(_ geometry: GeometryProxy) -> FoldMorphReveal {
        guard anchorInWindow, let anchorX else { return self }
        var copy = self
        copy.anchorX = anchorX - geometry.frame(in: .global).minX
        copy.anchorInWindow = false
        return copy
    }

    private static let seed = CGSize(width: 30, height: 22)

    private static func unit(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    private var pours: Bool { motion.poursFromButton }

    private func barRect(in size: CGSize) -> CGRect {
        guard pours else {
            return CGRect(origin: .zero, size: size)
        }
        let p: CGFloat = max(progress, 0)
        // Pouring motions: full width by 0.85 so the goo hand-off matches.
        let grow: CGFloat = Self.unit((p - 0.3) / 0.55)
        let fall: CGFloat = Self.unit(p / 0.45)
        let seedTop: CGFloat = pourCenterY - Self.seed.height / 2
        let width: CGFloat = min(size.width, Self.seed.width + (size.width - Self.seed.width) * grow)
        let height: CGFloat = min(size.height, Self.seed.height + (size.height - Self.seed.height) * grow)
        let anchor: CGFloat = anchorX ?? size.width / 2
        let x: CGFloat = min(max(anchor - width / 2, 0), max(0, size.width - width))
        return CGRect(x: x, y: seedTop * (1 - fall), width: width, height: height)
    }

    /// Silhouettes for the pour, in the bar's coordinates, after gooey-react:
    /// a blob swells on the button, a drop stretches out of it and falls, then
    /// one ball per icon bursts sideways (staggered) and the row fuses into the
    /// bar. For Liquid a blur + alpha threshold supplies the necks.
    private func gooBlobs(in size: CGSize) -> [CGRect] {
        let p: CGFloat = max(progress, 0)
        let anchor: CGFloat = anchorX ?? size.width / 2
        let h: CGFloat = size.height
        // The threshold erodes edges, so liquid shapes are pre-grown; bubbles stay crisp.
        let inflate: CGFloat = motion == .liquid ? Self.gooBlur * 0.45 : 0
        var blobs: [CGRect] = []

        func circle(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) -> CGRect {
            let dd = max(0, d + inflate * 2)
            return CGRect(x: x - dd / 2, y: y - dd / 2, width: dd, height: dd)
        }
        func ease(_ t: CGFloat) -> CGFloat {
            let u = Self.unit(t)
            return 1 - pow(1 - u, 3)
        }
        /// Ease out with a small overshoot, for chips that pop.
        func easeBack(_ t: CGFloat) -> CGFloat {
            let u = Self.unit(t) - 1
            return 1 + 2.4 * u * u * u + 1.4 * u * u
        }

        let count = min(max(slotCount, 3), 14)
        let span: CGFloat = max(0, size.width - h)
        let slots: [CGFloat] = (0 ..< count).map { i in
            count == 1 ? size.width / 2 : h / 2 + span * CGFloat(i) / CGFloat(count - 1)
        }
        let order = slots.indices.sorted { abs(slots[$0] - anchor) < abs(slots[$1] - anchor) }

        if motion == .bubbles {
            // Bubbles: no pour. A chip per icon pops up in place, nearest the
            // menu-bar icon first, rising a few points as it grows.
            for (rank, index) in order.enumerated() {
                let t: CGFloat = (p - 0.02 - CGFloat(rank) * 0.045) / 0.34
                guard t > 0 else { continue }
                let grown: CGFloat = easeBack(t)
                let rise: CGFloat = 7 * (1 - ease(t))
                blobs.append(circle(slots[index], h / 2 + rise, h * 0.84 * grown))
            }
            let fuse: CGFloat = ease((p - 0.66) / 0.3)
            if fuse > 0 {
                // The chips swell into one another until the bar is whole.
                let inset: CGFloat = (h * 0.08) * (1 - fuse)
                let w: CGFloat = h + (size.width - h) * fuse
                let x: CGFloat = min(max(anchor - w / 2, 0), size.width - w)
                blobs.append(CGRect(x: x, y: 0, width: w, height: h).insetBy(dx: 0, dy: inset))
            }
            return blobs
        }

        // 1. Button blob: swells, then drains into the drop.
        let swell: CGFloat = Self.unit(p / 0.12)
        let drain: CGFloat = Self.unit((p - 0.22) / 0.33)
        let buttonD: CGFloat = Self.seed.height * (0.9 + 0.35 * swell) * (1 - drain)
        if buttonD > 1 { blobs.append(circle(anchor, pourCenterY, buttonD)) }

        // 2. The drop: stretches out of the blob and falls to the bar's centre.
        let fall: CGFloat = ease((p - 0.06) / 0.34)
        let dropY: CGFloat = pourCenterY + (h / 2 - pourCenterY) * fall
        let dropD: CGFloat = (h - inflate * 2) * (0.6 + 0.4 * fall)
        if p > 0.04 { blobs.append(circle(anchor, dropY, dropD)) }

        // 3. Burst: one ball per icon flies from the drop to its slot.
        for (rank, index) in order.enumerated() {
            let start: CGFloat = 0.32 + CGFloat(rank) * 0.035
            let t: CGFloat = ease((p - start) / 0.42)
            guard t > 0 else { continue }
            let x: CGFloat = anchor + (slots[index] - anchor) * t
            blobs.append(circle(x, h / 2, (h - inflate * 2) * (0.6 + 0.4 * t)))
        }

        // 4. Fuse: a capsule grows over the row and smooths the bumps.
        let fuse: CGFloat = ease((p - 0.72) / 0.28)
        if fuse > 0 {
            let w: CGFloat = h + (size.width - h) * fuse
            let x: CGFloat = min(max(anchor - w / 2, 0), size.width - w)
            blobs.append(CGRect(x: x, y: 0, width: w, height: h))
        }
        return blobs
    }

    /// The same choreography for a column or grid: the drop lands on the top
    /// row, balls burst outwards over the whole panel (nearest the menu-bar
    /// icon first) and a rounded panel grows over them.
    private func gooPanelBlobs(in size: CGSize, radius: CGFloat) -> [(CGRect, CGFloat?)] {
        let p: CGFloat = max(progress, 0)
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let anchor: CGFloat = min(max(anchorX ?? w / 2, 0), w)
        let inflate: CGFloat = motion == .liquid ? Self.gooBlur * 0.45 : 0
        var blobs: [(CGRect, CGFloat?)] = []

        func ease(_ t: CGFloat) -> CGFloat {
            let u = Self.unit(t)
            return 1 - pow(1 - u, 3)
        }
        func easeBack(_ t: CGFloat) -> CGFloat {
            let u = Self.unit(t) - 1
            return 1 + 2.4 * u * u * u + 1.4 * u * u
        }
        /// `d` is the diameter as it should look; the threshold's erosion is
        /// already accounted for.
        func circle(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) -> (CGRect, CGFloat?) {
            let dd = max(0, d)
            return (CGRect(x: x - dd / 2, y: y - dd / 2, width: dd, height: dd), nil)
        }

        // One chip per icon cell: a pill per row in a column, a chip per
        // icon in a grid.
        let cols = max(1, min(columns, slotCount))
        var rows = max(1, Int((CGFloat(max(slotCount, 1)) / CGFloat(cols)).rounded(.up)))
        if h / CGFloat(rows) < 22 {
            // More rows than fit (the drawer scrolls): use what is visible.
            rows = max(1, Int((h / 32).rounded()))
        }
        let cellSize = CGSize(width: w / CGFloat(cols), height: h / CGFloat(rows))
        let ball: CGFloat = min(cellSize.width, cellSize.height)
        var slots: [CGPoint] = []
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                slots.append(CGPoint(x: cellSize.width * (CGFloat(c) + 0.5), y: cellSize.height * (CGFloat(r) + 0.5)))
            }
        }
        /// A chip centred on a point; `grown` 1 is the full cell.
        func chip(_ x: CGFloat, _ y: CGFloat, _ grown: CGFloat) -> (CGRect, CGFloat?) {
            let cw = max(0, (cellSize.width - 3) * grown)
            let ch = max(0, (cellSize.height - 3) * grown)
            return (CGRect(x: x - cw / 2, y: y - ch / 2, width: cw, height: ch), nil)
        }
        func distance(_ point: CGPoint) -> CGFloat { hypot(point.x - anchor, point.y) }
        let order = slots.indices.sorted { distance(slots[$0]) < distance(slots[$1]) }
        let landing = CGPoint(x: min(max(anchor, ball / 2), max(ball / 2, w - ball / 2)), y: ball / 2)

        /// The panel that grows over the balls, from the landing point.
        func panel(_ fuse: CGFloat) -> (CGRect, CGFloat?) {
            let pw: CGFloat = ball + (w - ball) * fuse
            let ph: CGFloat = ball + (h - ball) * fuse
            let x: CGFloat = min(max(anchor - pw / 2, 0), max(0, w - pw))
            return (CGRect(x: x, y: 0, width: pw, height: ph), min(radius + inflate * 0.5, min(pw, ph) / 2))
        }

        if motion == .bubbles {
            let step: CGFloat = min(0.06, 0.36 / CGFloat(max(slots.count, 1)))
            for (rank, index) in order.enumerated() {
                let t: CGFloat = (p - 0.02 - CGFloat(rank) * step) / 0.34
                guard t > 0 else { continue }
                let rise: CGFloat = 7 * (1 - ease(t))
                blobs.append(chip(slots[index].x, slots[index].y + rise, easeBack(t)))
            }
            let fuse: CGFloat = ease((p - 0.66) / 0.3)
            if fuse > 0 { blobs.append(panel(fuse)) }
            return blobs
        }

        // 1. Button blob: swells, then drains into the drop.
        let swell: CGFloat = Self.unit(p / 0.12)
        let drain: CGFloat = Self.unit((p - 0.22) / 0.33)
        let buttonD: CGFloat = Self.seed.height * (0.9 + 0.35 * swell) * (1 - drain)
        if buttonD > 1 { blobs.append(circle(anchor, pourCenterY, buttonD + inflate * 2)) }

        // 2. The drop falls onto the top row.
        let fall: CGFloat = ease((p - 0.06) / 0.34)
        let dropY: CGFloat = pourCenterY + (landing.y - pourCenterY) * fall
        if p > 0.04 { blobs.append(circle(landing.x + (anchor - landing.x) * (1 - fall), dropY, ball * (0.6 + 0.4 * fall))) }

        // 3. Burst: balls spread from the drop over the whole panel.
        let step: CGFloat = min(0.035, 0.26 / CGFloat(max(slots.count, 1)))
        for (rank, index) in order.enumerated() {
            let t: CGFloat = ease((p - 0.32 - CGFloat(rank) * step) / 0.4)
            guard t > 0 else { continue }
            let x: CGFloat = landing.x + (slots[index].x - landing.x) * t
            let y: CGFloat = landing.y + (slots[index].y - landing.y) * t
            blobs.append(chip(x, y, 0.5 + 0.5 * t))
        }

        // 4. Fuse: the panel grows over the balls and squares them off.
        let fuse: CGFloat = ease((p - 0.7) / 0.3)
        if fuse > 0 { blobs.append(panel(fuse)) }
        return blobs
    }

    /// The real capsule fades in underneath before the blobs fade off the top,
    /// so the hand-off never shows two half-transparent layers.
    private var capsuleOpacity: Double {
        motion.usesBlobs ? Double(Self.unit((progress - 0.8) / 0.08)) : 1
    }

    /// Blobs while opening, the real capsule once settled (keeps the glass rim).
    private var gooAmount: Double {
        motion.usesBlobs ? Double(1 - Self.unit((progress - 0.9) / 0.1)) : 0
    }

    private var contentOpacity: Double {
        switch motion {
        // Pouring motions: icons wait until the bar has fused under them.
        case .liquid: Double(Self.unit((progress - 0.68) / 0.2))
        case .bubbles: Double(Self.unit((progress - 0.6) / 0.25))
        case .pop: Double(Self.unit(progress / 0.4))
        case .hinge: Double(Self.unit(progress / 0.45))
        case .cascade: Double(Self.unit(progress / 0.2))
        case .materialize: Double(Self.unit(progress))
        case .drop, .fade: Double(Self.unit(progress))
        case .none: 1
        }
    }

    private var surfaceOpacity: Double {
        switch motion {
        case .drop, .fade, .materialize: Double(Self.unit(progress))
        case .pop, .cascade: Double(Self.unit(progress / 0.25))
        case .hinge: Double(Self.unit(progress / 0.3))
        default: 1
        }
    }

    private var dropOffset: CGFloat {
        motion == .drop ? -14 * (1 - min(progress, 1)) : 0
    }

    /// Pop springs out of the icon; Elastic drops and wobbles like rubber.
    private var scale: CGSize {
        let p: CGFloat = max(progress, 0)
        switch motion {
        case .pop:
            let s: CGFloat = 0.35 + 0.65 * p
            return CGSize(width: s, height: s)
        case .drop:
            // Glide: barely-there, origin-aware scale, as macOS menus do.
            let s: CGFloat = 0.93 + 0.07 * min(p, 1)
            return CGSize(width: s, height: s)
        case .cascade:
            // Origin-aware and subtle: never from zero.
            let s: CGFloat = 0.9 + 0.1 * p
            return CGSize(width: s, height: s)
        case .materialize:
            let s: CGFloat = 1.12 - 0.12 * min(p, 1)
            return CGSize(width: s, height: s)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    /// Fold: degrees the flap still has to swing down, hinged on its top edge.
    private var hingeAngle: Double {
        motion == .hinge ? -86 * Double(1 - max(progress, 0)) : 0
    }

    private var focusBlur: CGFloat {
        motion == .materialize ? 16 * (1 - Self.unit(progress)) : 0
    }

    func body(content: Content) -> some View {
        let hingeAngle = hingeAngle
        let focusBlur = focusBlur
        let scale = scale
        let anchorX = anchorX
        let anchorInWindow = anchorInWindow
        return content
            .opacity(contentOpacity)
            .mask(alignment: .topLeading) {
                GeometryReader { geometry in
                    let r = local(geometry).barRect(in: geometry.size)
                    FoldBarShape(radius: cornerRadius)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .background(alignment: .topLeading) {
                GeometryReader { geometry in
                    local(geometry).surface(in: geometry.size)
                }
            }
            .offset(y: dropOffset)
            .visualEffect { effect, proxy in
                let frame = proxy.frame(in: .global)
                let width = max(proxy.size.width, 1)
                let localAnchor = anchorInWindow ? (anchorX ?? frame.midX) - frame.minX : (anchorX ?? width / 2)
                return effect
                    .scaleEffect(
                        x: scale.width,
                        y: scale.height,
                        anchor: UnitPoint(x: min(max(localAnchor / width, 0), 1), y: 0)
                    )
                    .rotation3DEffect(.degrees(hingeAngle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.7)
                    .blur(radius: focusBlur)
            }
    }

    /// gooey-react's "medium" is a 12 px blur at 100 px-scale shapes; the bar is
    /// ~37 pt tall, so scale it to keep the same neck-to-body proportion.
    private static let gooBlur: CGFloat = 8
    private static let gooPadding: CGFloat = 24

    private func surface(in size: CGSize) -> some View {
        let bar = barRect(in: size)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: bar.width, height: bar.height)
                .modifier(FoldSurface(shape: FoldBarShape(radius: cornerRadius)))
                // The bar's own soft shadow (the window has none); Minimal
                // has no surface to cast one.
                .compositingGroup()
                // Tight and low, like macOS's own menus.
                .shadow(color: .black.opacity(FoldLook.current == .minimal ? 0 : 0.2), radius: 4, y: 1.5)
                .position(x: bar.midX, y: bar.midY)
                .opacity(capsuleOpacity)
            if gooAmount > 0 {
                gooSurface(in: size)
                    .opacity(gooAmount)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(surfaceOpacity)
    }

    private func gooSurface(in size: CGSize) -> some View {
        let pad = Self.gooPadding
        let top: CGFloat = min(0, pourCenterY - Self.seed.height) - pad
        let canvas = CGRect(x: -pad, y: top, width: size.width + pad * 2, height: size.height + pad - top)
        let blobs: [(CGRect, CGFloat?)] = if let cornerRadius {
            gooPanelBlobs(in: size, radius: cornerRadius)
        } else {
            gooBlobs(in: size).map { ($0, nil) }
        }
        let gooey = motion == .liquid
        return FoldGooFill()
            .frame(width: canvas.width, height: canvas.height)
            .mask {
                Canvas { context, _ in
                    if gooey {
                        context.addFilter(.alphaThreshold(min: 0.5))
                        context.addFilter(.blur(radius: Self.gooBlur))
                    }
                    context.drawLayer { layer in
                        for (blob, radius) in blobs {
                            let local = blob.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
                            let path = if let radius {
                                RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: local)
                            } else {
                                Capsule().path(in: local)
                            }
                            layer.fill(path, with: .color(.black))
                        }
                    }
                }
            }
            .position(x: canvas.midX, y: canvas.midY)
    }
}

/// The goo's paint. Liquid Glass renders nothing once masked into an arbitrary
/// shape, so the pour uses a flat tone that matches the chosen look, and the
/// real surface takes over when the bar settles.
private struct FoldGooFill: View {
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.glass) private var glass = "system"
    @AppStorage(FoldKey.tint) private var tint = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        switch FoldLook(rawValue: look) ?? .glass {
        case .minimal:
            Color.clear
        case .solid, .outline:
            Rectangle().fill(isDark ? Color(white: 0.14) : Color(white: 0.95))
        case .glass where glass == "color":
            Rectangle().fill(FoldTint.color(tint).opacity(0.55))
        case .glass, .frosted:
            let opacity = glass == "clear" ? 0.55 : 0.82
            Rectangle().fill((isDark ? Color(white: 0.16) : Color(white: 0.96)).opacity(opacity))
        case .accent:
            Rectangle().fill(FoldTint.color(tint).opacity(0.85))
        case .paper:
            Rectangle().fill(foldPaperColor)
        case .obsidian:
            Rectangle().fill(foldObsidianColor)
        }
    }
}
