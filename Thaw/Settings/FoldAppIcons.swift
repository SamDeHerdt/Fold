//
//  FoldAppIcons.swift
//  Fold
//
//  Menu-bar item images without Screen Recording: each item's app icon, or a
//  matching symbol for macOS's own items (Wi-Fi, Sound, Focus…). They come out
//  as the same `CapturedImage` the capture paths produce, so the drawer, grid
//  and named column don't know the difference. Used whenever live icons are off
//  or Screen Recording isn't granted (`ScreenCapture.captureAllowed`).
//

import AppKit
import os

nonisolated enum FoldAppIcons {
    typealias Image = MenuBarItemImageCache.CapturedImage

    /// Rendered images by bundle/symbol, pixel size and colour scheme, so the
    /// live refresh loop doesn't redraw the same icon over and over.
    private static let cache = OSAllocatedUnfairLock(initialState: [String: Image]())

    /// Images that are (greyscale) app icons. The drawer draws menu-bar glyphs
    /// as templates (one colour that suits the bar); an app icon drawn that way
    /// becomes a blank rounded square, so these are drawn as they are.
    private static let fullColor = OSAllocatedUnfairLock(initialState: Set<ObjectIdentifier>())

    static func isFullColor(_ image: CGImage) -> Bool {
        fullColor.withLock { $0.contains(ObjectIdentifier(image)) }
    }

    static func images(for items: [MenuBarItem], scale: CGFloat) -> [MenuBarItemTag: Image] {
        let dark = drawerIsDark
        var result = [MenuBarItemTag: Image]()
        for item in items where !item.isControlItem {
            let height = Bridging.getWindowBounds(for: item.windowID)?.height ?? 24
            let side = max(16, min(height, 44))
            if let image = image(for: item, side: side, scale: max(scale, 1), dark: dark) {
                result[item.tag] = image
            }
        }
        return result
    }

    // MARK: Choosing the picture

    private enum Source {
        case symbol(String)
        case app(NSRunningApplication)
    }

    private static func source(for item: MenuBarItem) -> Source? {
        let isSystem = item.tag.namespace == .controlCenter || item.tag.namespace == .systemUIServer
        if isSystem, let title = item.title, let symbol = systemSymbol(for: title) {
            return .symbol(symbol)
        }
        if let app = item.sourceApplication ?? item.owningApplication {
            return .app(app)
        }
        return nil
    }

    /// macOS's own items, by the window title Control Center / SystemUIServer
    /// gives them. Anything unknown falls back to the owning app's icon.
    private static func systemSymbol(for title: String) -> String? {
        let t = title.lowercased()
        let table: [(String, String)] = [
            ("bentobox", "switch.2"),
            ("wifi", "wifi"),
            ("battery", "battery.100percent"),
            ("sound", "speaker.wave.2.fill"),
            ("volume", "speaker.wave.2.fill"),
            ("focus", "moon.fill"),
            ("nowplaying", "play.circle.fill"),
            ("keyboardbrightness", "light.max"),
            ("display", "sun.max.fill"),
            ("brightness", "sun.max.fill"),
            ("screenmirroring", "rectangle.on.rectangle"),
            ("userswitcher", "person.crop.circle"),
            ("clock", "clock"),
            ("timemachine", "clock.arrow.circlepath"),
            ("accessibility", "accessibility"),
            ("hearing", "ear"),
            ("spotlight", "magnifyingglass"),
            ("siri", "waveform.circle"),
            ("stagemanager", "rectangle.3.group"),
            ("vpn", "network.badge.shield.half.filled"),
            ("textinput", "keyboard"),
            ("airdrop", "dot.radiowaves.left.and.right"),
            ("bluetooth", "dot.radiowaves.left.and.right"),
            ("weather", "cloud.sun.fill"),
            ("passwords", "key.fill"),
        ]
        for (needle, symbol) in table where t.contains(needle) {
            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil { return symbol }
        }
        return nil
    }

    // MARK: Rendering

    private static func image(for item: MenuBarItem, side: CGFloat, scale: CGFloat, dark: Bool) -> Image? {
        guard let source = source(for: item) else { return nil }
        let px = Int((side * scale).rounded())
        let key: String
        switch source {
        case let .symbol(name): key = "sym:\(name):\(px):\(dark)"
        case let .app(app): key = "app:\(app.bundleIdentifier ?? "\(app.processIdentifier)"):\(px)"
        }
        if let hit = cache.withLock({ $0[key] }) { return hit }

        // App icons go into a grey context: no colour in the drawer, like the
        // rest of the menu bar, while the icon's shape stays recognisable.
        let isApp: Bool = if case .app = source { true } else { false }
        guard let context = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: isApp ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        switch source {
        case let .app(app):
            guard let icon = app.icon else { return nil }
            let inset = side * 0.11
            icon.draw(in: NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
        case let .symbol(name):
            let color: NSColor = dark ? .white : NSColor(white: 0.1, alpha: 1)
            let config = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .regular)
                .applying(.init(paletteColors: [color]))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return nil }
            let size = symbol.size
            symbol.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                   width: size.width, height: size.height))
        }

        guard let cgImage = context.makeImage() else { return nil }
        let image = Image(cgImage: cgImage, scale: scale)
        cache.withLock { $0[key] = image }
        if isApp { fullColor.withLock { _ = $0.insert(ObjectIdentifier(cgImage)) } }
        return image
    }

    /// The drawer's colour scheme (Fold › Look › Appearance), without touching
    /// AppKit's main-thread-only appearance APIs.
    private static var drawerIsDark: Bool {
        switch UserDefaults.standard.string(forKey: FoldKey.appearance) ?? "dark" {
        case "light": return false
        case "dark": return true
        default: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }
}
