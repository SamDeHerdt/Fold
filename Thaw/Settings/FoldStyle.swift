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

    static var current: FoldMotion {
        FoldMotion(rawValue: UserDefaults.standard.string(forKey: FoldKey.motion) ?? "") ?? .liquid
    }

    var openAnimation: Animation? {
        switch self {
        case .liquid: .spring(duration: 0.55, bounce: 0.25)
        case .unfold: .spring(duration: 0.35, bounce: 0.3)
        case .drop: .timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
        case .fade: .easeOut(duration: 0.15)
        case .none: nil
        }
    }

    var closeAnimation: Animation? {
        switch self {
        case .liquid: .timingCurve(0.22, 1, 0.36, 1, duration: 0.3)
        case .unfold: .timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
        case .drop: .timingCurve(0.22, 1, 0.36, 1, duration: 0.15)
        case .fade: .easeIn(duration: 0.12)
        case .none: nil
        }
    }

    /// How long the panel stays up after a close starts, matching `closeAnimation`.
    var closeDelay: TimeInterval {
        switch self {
        case .liquid: 0.3
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
struct FoldMorphReveal: ViewModifier {
    /// 0 = folded into the button, 1 = fully open.
    let progress: CGFloat
    let anchorX: CGFloat?
    let motion: FoldMotion
    let pourCenterY: CGFloat

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
        let grow: CGFloat = isLiquid ? Self.unit((p - 0.3) / 0.7) : Self.unit(p)
        let fall: CGFloat = isLiquid ? Self.unit(p / 0.45) : 1
        let seedTop: CGFloat = isLiquid ? pourCenterY - Self.seed.height / 2 : 0
        let width: CGFloat = min(size.width, Self.seed.width + (size.width - Self.seed.width) * grow)
        let height: CGFloat = min(size.height, Self.seed.height + (size.height - Self.seed.height) * grow)
        let anchor: CGFloat = anchorX ?? size.width / 2
        let x: CGFloat = min(max(anchor - width / 2, 0), max(0, size.width - width))
        return CGRect(x: x, y: seedTop * (1 - fall), width: width, height: height)
    }

    /// The liquid neck from the button to the falling droplet; it thins away.
    private func stemRect(in size: CGSize, bar: CGRect) -> CGRect? {
        guard motion == .liquid else { return nil }
        let thickness: CGFloat = 1 - Self.unit((progress - 0.35) / 0.5)
        guard thickness > 0.02 else { return nil }
        let anchor: CGFloat = anchorX ?? size.width / 2
        let width: CGFloat = Self.seed.width * 0.6 * thickness
        let top: CGFloat = pourCenterY - Self.seed.height / 2 * thickness
        let bottom: CGFloat = bar.midY
        guard bottom > top else { return nil }
        return CGRect(x: anchor - width / 2, y: top, width: width, height: bottom - top)
    }

    private var contentOpacity: Double {
        switch motion {
        case .liquid: Double(Self.unit((progress - 0.45) / 0.45))
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
                    let r = barRect(in: geometry.size)
                    Capsule()
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .background(alignment: .topLeading) {
                GeometryReader { geometry in
                    surface(in: geometry.size)
                }
            }
            .offset(y: dropOffset)
    }

    private func surface(in size: CGSize) -> some View {
        let bar = barRect(in: size)
        let stem = stemRect(in: size, bar: bar)
        return GlassEffectContainer(spacing: 14) {
            ZStack(alignment: .topLeading) {
                if let stem {
                    Color.clear
                        .frame(width: stem.width, height: stem.height)
                        .modifier(FoldSurface(shape: Capsule()))
                        .position(x: stem.midX, y: stem.midY)
                }
                Color.clear
                    .frame(width: bar.width, height: bar.height)
                    .modifier(FoldSurface(shape: Capsule()))
                    .position(x: bar.midX, y: bar.midY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .opacity(surfaceOpacity)
    }
}
