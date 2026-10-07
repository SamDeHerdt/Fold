//
//  FoldStyle.swift
//  Fold
//
//  Licensed under the GNU GPLv3
//

import SwiftUI

/// UserDefaults keys for Fold's own presentation settings.
enum FoldKey {
    static let appearance = "FoldAppearanceV1"
    static let glass = "FoldGlassV1"
    static let look = "FoldLookV1"
    /// Maximum drawer length in points; 0 means "as wide as the screen allows".
    static let maxWidth = "FoldMaxWidthV1"
    static let motion = "FoldMotionV1"
    /// Seconds the pointer rests on the menu-bar icon before the drawer opens.
    static let hoverDelay = "FoldHoverDelayV1"
    /// Extra points between icons inside the drawer (drawer only).
    static let iconSpacing = "FoldIconSpacingV1"

    static var hoverDelaySeconds: Double {
        UserDefaults.standard.object(forKey: hoverDelay) as? Double ?? 0.18
    }
}

/// How the drawer opens and closes.
enum FoldMotion: String, CaseIterable, Identifiable {
    case liquid
    case unfold
    case drop
    case fade
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquid: "Liquid"
        case .unfold: "Unfold"
        case .drop: "Drop"
        case .fade: "Fade"
        case .none: "None"
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

    var openAnimation: Animation? {
        baseOpenAnimation?.speed(1 / Self.debugSlowdown)
    }

    var closeAnimation: Animation? {
        baseCloseAnimation?.speed(1 / Self.debugSlowdown)
    }

    private var baseOpenAnimation: Animation? {
        switch self {
        case .liquid: .spring(duration: 0.75, bounce: 0.22)
        case .unfold: .spring(duration: 0.35, bounce: 0.3)
        case .drop: .timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
        case .fade: .easeOut(duration: 0.15)
        case .none: nil
        }
    }

    private var baseCloseAnimation: Animation? {
        switch self {
        case .liquid: .timingCurve(0.22, 1, 0.36, 1, duration: 0.35)
        case .unfold: .timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
        case .drop: .timingCurve(0.22, 1, 0.36, 1, duration: 0.15)
        case .fade: .easeIn(duration: 0.12)
        case .none: nil
        }
    }

    /// How long the panel stays up after a close starts, matching `closeAnimation`.
    var closeDelay: TimeInterval {
        baseCloseDelay * Self.debugSlowdown
    }

    private var baseCloseDelay: TimeInterval {
        switch self {
        case .liquid: 0.35
        case .unfold: 0.22
        case .drop: 0.15
        case .fade: 0.12
        case .none: 0
        }
    }

    /// Liquid pours out of the menu-bar button, so its window reaches up over
    /// the menu bar. The extra strip stays transparent.
    func pourInset(menuBarHeight: CGFloat) -> CGFloat {
        self == .liquid ? menuBarHeight : 0
    }
}

/// The surface drawn behind the drawer's icons.
enum FoldLook: String, CaseIterable, Identifiable {
    case glass
    case frosted
    case solid
    case outline
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        case .outline: "Outline"
        case .minimal: "Minimal"
        }
    }
}

enum FoldWidth {
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

/// Open/closed state shared by the drawer panel and its SwiftUI content, so
/// the panel can let the content morph back into the chevron before it hides.
@Observable
final class FoldMorph {
    var isOpen = false
}

/// Draws the selected Fold look behind content, in the given shape.
struct FoldSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.glass) private var glass = "system"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { colorScheme == .dark }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch FoldLook(rawValue: look) ?? .glass {
        case .glass where !reduceTransparency:
            if glass == "clear" {
                content.glassEffect(.clear, in: shape)
            } else if glass == "tinted" {
                content.glassEffect(.regular.tint((isDark ? Color.black : Color.white).opacity(0.35)), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        case .frosted where !reduceTransparency:
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(isDark ? 0.14 : 0.6), lineWidth: 0.5))
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
                .overlay(shape.strokeBorder((isDark ? Color.white : Color.black).opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Reveals a bar with the chosen motion. `anchorX` is the menu-bar button's
/// centre along the bar and `pourCenterY` its centre above the bar (negative),
/// both in the bar's own coordinates.
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
    /// Icons in the bar; Liquid bursts one goo ball out per icon.
    var slotCount: Int = 7
    /// When true, `anchorX` is in window coordinates and is converted to the
    /// bar's own space at draw time (the bar's real position can differ from
    /// any estimate, e.g. when icon widths differ from their cached sizes).
    var anchorInWindow = false

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

    private func barRect(in size: CGSize) -> CGRect {
        guard motion == .liquid || motion == .unfold else {
            return CGRect(origin: .zero, size: size)
        }
        let p: CGFloat = max(progress, 0)
        let isLiquid = motion == .liquid
        // Liquid: the droplet falls from the button first, then stretches.
        // Liquid: full width by 0.85 so it matches the goo before the hand-off.
        let grow: CGFloat = isLiquid ? Self.unit((p - 0.3) / 0.55) : Self.unit(p)
        let fall: CGFloat = isLiquid ? Self.unit(p / 0.45) : 1
        let seedTop: CGFloat = isLiquid ? pourCenterY - Self.seed.height / 2 : 0
        let width: CGFloat = min(size.width, Self.seed.width + (size.width - Self.seed.width) * grow)
        let height: CGFloat = min(size.height, Self.seed.height + (size.height - Self.seed.height) * grow)
        let anchor: CGFloat = anchorX ?? size.width / 2
        let x: CGFloat = min(max(anchor - width / 2, 0), max(0, size.width - width))
        return CGRect(x: x, y: seedTop * (1 - fall), width: width, height: height)
    }

    /// Goo silhouettes for the liquid pour, in the bar's coordinates, after
    /// gooey-react: a blob swells on the button, a drop stretches out of it and
    /// falls, then one ball per icon bursts sideways out of the drop (staggered)
    /// and the row fuses into the bar. Blur + alpha threshold supplies the necks.
    private func gooBlobs(in size: CGSize, bar _: CGRect) -> [CGRect] {
        let p: CGFloat = max(progress, 0)
        let anchor: CGFloat = anchorX ?? size.width / 2
        let h: CGFloat = size.height
        let inflate: CGFloat = Self.gooBlur * 0.45 // threshold erodes edges; pre-grow
        var blobs: [CGRect] = []

        func circle(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) -> CGRect {
            let dd = max(0, d + inflate * 2)
            return CGRect(x: x - dd / 2, y: y - dd / 2, width: dd, height: dd)
        }
        func ease(_ t: CGFloat) -> CGFloat {
            let u = Self.unit(t)
            return 1 - pow(1 - u, 3)
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
        let count = min(max(slotCount, 3), 14)
        let span: CGFloat = max(0, size.width - h)
        let slots: [CGFloat] = (0 ..< count).map { i in
            count == 1 ? size.width / 2 : h / 2 + span * CGFloat(i) / CGFloat(count - 1)
        }
        let order = slots.indices.sorted { abs(slots[$0] - anchor) < abs(slots[$1] - anchor) }
        for (rank, index) in order.enumerated() {
            let start: CGFloat = 0.32 + CGFloat(rank) * 0.035
            let t: CGFloat = ease((p - start) / 0.42)
            guard t > 0 else { continue }
            let x: CGFloat = anchor + (slots[index] - anchor) * t
            // Ends exactly bar-high once the threshold's pre-grow is added.
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

    /// The real capsule fades in underneath before the goo fades off the top,
    /// so the hand-off never shows two half-transparent layers.
    private var capsuleOpacity: Double {
        motion == .liquid ? Double(Self.unit((progress - 0.8) / 0.08)) : 1
    }

    /// Goo while pouring, the real capsule once settled (keeps the glass rim).
    private var gooAmount: Double {
        motion == .liquid ? Double(1 - Self.unit((progress - 0.9) / 0.1)) : 0
    }

    private var contentOpacity: Double {
        switch motion {
        case .liquid: Double(Self.unit((progress - 0.6) / 0.3))
        case .unfold: Double(Self.unit((progress - 0.25) / 0.6))
        case .drop, .fade: Double(Self.unit(progress))
        case .none: 1
        }
    }

    private var surfaceOpacity: Double {
        motion == .drop || motion == .fade ? Double(Self.unit(progress)) : 1
    }

    private var dropOffset: CGFloat {
        motion == .drop ? -10 * (1 - min(progress, 1)) : 0
    }

    private var contentBlur: CGFloat {
        motion == .none ? 0 : max(0, 1 - progress) * 2
    }

    func body(content: Content) -> some View {
        content
            .opacity(contentOpacity)
            .blur(radius: contentBlur)
            .mask(alignment: .topLeading) {
                GeometryReader { geometry in
                    let r = local(geometry).barRect(in: geometry.size)
                    Capsule()
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
                .modifier(FoldSurface(shape: Capsule()))
                .position(x: bar.midX, y: bar.midY)
                .opacity(capsuleOpacity)
            if gooAmount > 0 {
                gooSurface(in: size, bar: bar)
                    .opacity(gooAmount)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(surfaceOpacity)
    }

    private func gooSurface(in size: CGSize, bar: CGRect) -> some View {
        let pad = Self.gooPadding
        let top: CGFloat = min(0, pourCenterY - Self.seed.height) - pad
        let canvas = CGRect(x: -pad, y: top, width: size.width + pad * 2, height: size.height + pad - top)
        let blobs = gooBlobs(in: size, bar: bar)
        return FoldGooFill()
            .frame(width: canvas.width, height: canvas.height)
            .mask {
                Canvas { context, _ in
                    context.addFilter(.alphaThreshold(min: 0.5))
                    context.addFilter(.blur(radius: Self.gooBlur))
                    context.drawLayer { layer in
                        for blob in blobs {
                            let local = blob.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
                            layer.fill(Capsule().path(in: local), with: .color(.black))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        switch FoldLook(rawValue: look) ?? .glass {
        case .minimal:
            Color.clear
        case .solid, .outline:
            Rectangle().fill(isDark ? Color(white: 0.14) : Color(white: 0.95))
        case .glass, .frosted:
            let opacity = glass == "clear" ? 0.55 : 0.82
            Rectangle().fill((isDark ? Color(white: 0.16) : Color(white: 0.96)).opacity(opacity))
        }
    }
}
