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

/// Grows a bar out of a chevron-sized droplet at `anchorX` (in the bar's own
/// coordinates), Liquid-Glass style, and folds it back on close.
struct FoldMorphReveal: ViewModifier {
    /// 0 = folded into the chevron, 1 = fully open.
    let progress: CGFloat
    let anchorX: CGFloat?

    private static let seedSize = CGSize(width: 30, height: 22)

    private func rect(in size: CGSize) -> CGRect {
        let p = min(max(progress, 0), 1.2)
        let width = max(Self.seedSize.width, Self.seedSize.width + (size.width - Self.seedSize.width) * p)
        let height = min(size.height, Self.seedSize.height + (size.height - Self.seedSize.height) * min(p, 1))
        let anchor = anchorX ?? size.width / 2
        let x = min(max(anchor - width / 2, 0), max(0, size.width - width))
        return CGRect(x: x, y: 0, width: min(width, size.width), height: height)
    }

    private var contentOpacity: Double {
        let raw: CGFloat = (progress - 0.25) / 0.6
        return Double(min(1, max(0, raw)))
    }

    private var contentBlur: CGFloat {
        max(0, 1 - progress) * 2
    }

    func body(content: Content) -> some View {
        content
            .opacity(contentOpacity)
            .blur(radius: contentBlur)
            .mask(alignment: .topLeading) {
                GeometryReader { geometry in
                    let r = rect(in: geometry.size)
                    Capsule().frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
            }
            .background(alignment: .topLeading) {
                GeometryReader { geometry in
                    let r = rect(in: geometry.size)
                    Color.clear
                        .frame(width: r.width, height: r.height)
                        .modifier(FoldSurface(shape: Capsule()))
                        .offset(x: r.minX, y: r.minY)
                }
            }
    }
}
