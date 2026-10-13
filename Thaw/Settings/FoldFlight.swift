//
//  FoldFlight.swift
//  Fold
//
//  The icon's trip between the drawer and the menu bar: when an icon is
//  opened from the drawer it flies up to the spot beside the Fold icon where
//  macOS shows it, and when the app's menu closes it flies back into Fold.
//

import AppKit
import QuartzCore

@MainActor
enum FoldFlight {
    private static var window: NSWindow?
    private static var generation = 0

    /// What is needed to fly the last opened icon back.
    private struct Landed {
        let image: NSImage
        let frame: CGRect
        let chevron: CGRect
        weak var chevronWindow: NSWindow?
        let screen: NSScreen
    }

    private static var landed: Landed?
    private static weak var lastChevronWindow: NSWindow?

    /// The menu bar's own ink: white on a dark bar, black on a light one.
    private static var ink: NSColor {
        let appearance = lastChevronWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }

    private static var isEnabled: Bool {
        Constants.bundleIdentifier == "com.samdeherdt.fold"
            && FoldMotion.current != .none
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var timeScale: Double {
        FoldMotion.debugSlowdown / max(FoldMotion.speed, 0.1)
    }

    /// Flies `image` from its slot in the drawer (`source`, screen
    /// coordinates) to the place left of the Fold icon.
    static func depart(image: NSImage, tint: NSColor, from source: CGRect, chevronWindow: NSWindow?, on screen: NSScreen) {
        guard isEnabled, source.width > 0,
              let chevron = FoldChevron.frame(of: chevronWindow, on: screen)
        else { return }
        let size = image.size
        let target = CGRect(
            x: chevron.minX - size.width,
            y: chevron.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        landed = Landed(image: image, frame: target, chevron: chevron, chevronWindow: chevronWindow, screen: screen)

        let duration = 0.34 * timeScale
        lastChevronWindow = chevronWindow
        let (host, origin) = prepare(covering: source.union(target).union(chevron), on: screen)
        let from = CGPoint(x: source.midX - origin.x, y: source.midY - origin.y)
        let to = CGPoint(x: target.midX - origin.x, y: target.midY - origin.y)

        let icon = iconLayer(image: image, tint: tint, size: source.size)
        icon.position = to
        icon.opacity = 0
        host.addSublayer(icon)

        let path = CGMutablePath()
        path.move(to: from)
        // A shallow arc, so it reads as a hop rather than a slide.
        path.addQuadCurve(to: to, control: CGPoint(x: from.x + (to.x - from.x) * 0.25, y: max(from.y, to.y) - 2))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.22, size.height / max(source.height, 1)]
        scale.keyTimes = [0, 0.45, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.82, 1]
        run([move, scale, fade], on: icon, duration: duration, timing: CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.3, 1))

        // A soft ring where it lands, tying the icon to what opens under it.
        let ringRect = target.insetBy(dx: -7, dy: -3).offsetBy(dx: -origin.x, dy: -origin.y)
        pulse(in: host, rect: ringRect, from: 0.72, to: 1.18, delay: duration * 0.7, duration: 0.36 * timeScale)

        finish(after: duration * 0.7 + 0.36 * timeScale)
    }

    /// Flies the last opened icon from the menu bar back into the Fold icon.
    static func comeBack() {
        unlink(animated: true)
        guard isEnabled, let landed else { return }
        self.landed = nil
        let chevron = FoldChevron.frame(of: landed.chevronWindow, on: landed.screen) ?? landed.chevron
        let dark = landed.chevronWindow?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let duration = 0.34 * timeScale
        let (host, origin) = prepare(covering: landed.frame.union(chevron), on: landed.screen)
        let from = CGPoint(x: landed.frame.midX - origin.x, y: landed.frame.midY - origin.y)
        let to = CGPoint(x: chevron.midX - origin.x, y: chevron.midY - origin.y)

        let icon = iconLayer(image: landed.image, tint: dark ? .white : .black, size: landed.frame.size)
        icon.position = to
        icon.opacity = 0
        host.addSublayer(icon)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = from
        move.toValue = to
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.12, 0.35]
        scale.keyTimes = [0, 0.25, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.95, 0.95, 0]
        fade.keyTimes = [0, 0.7, 1]
        run([move, scale, fade], on: icon, duration: duration, timing: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.7, 0.4))

        // The Fold icon takes it in: a ring closing on it.
        let ringRect = chevron.insetBy(dx: 1, dy: 2).offsetBy(dx: -origin.x, dy: -origin.y)
        pulse(in: host, rect: ringRect, from: 1.3, to: 0.92, delay: duration * 0.55, duration: 0.3 * timeScale)

        finish(after: duration * 0.55 + 0.3 * timeScale)
    }

    // MARK: Link outline

    private static var linkWindow: NSWindow?
    private static var linkTask: Task<Void, Never>?
    private static var linkFrames: (item: CGRect, popup: CGRect)?

    /// Where the visible panel sits inside a window's bounds. Window bounds
    /// include the shadow's margin, which differs per app, so the outline is
    /// fitted to the opaque pixels instead.
    private struct Fit: Equatable {
        var left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat
        var radius: CGFloat
    }

    private static func fit(windowID: CGWindowID, bounds: CGRect) -> Fit? {
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w > 40, h > 20, w < 4000, h < 4000,
              let image = ScreenCapture.captureWindow(with: windowID, option: [.nominalResolution]),
              let context = CGContext(
                  data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Solid enough to be the panel, not its shadow.
        func solid(_ x: Int, _ y: Int) -> Bool { pixels[(y * w + x) * 4 + 3] > 120 }
        var counts = [Int](repeating: 0, count: h)
        for y in 0 ..< h {
            var n = 0
            for x in 0 ..< w where solid(x, y) { n += 1 }
            counts[y] = n
        }
        guard let widest = counts.max(), widest > 40 else { return nil }
        // Rows belonging to the body (the arrow of a popover is narrower).
        guard let top = counts.firstIndex(where: { $0 * 10 >= widest * 6 }),
              let bottom = counts.lastIndex(where: { $0 * 10 >= widest * 6 }),
              bottom - top > 20
        else { return nil }
        let middle = (top + bottom) / 2
        guard let left = (0 ..< w).first(where: { solid($0, middle) }),
              let right = (0 ..< w).last(where: { solid($0, middle) })
        else { return nil }
        let full = counts[top ... bottom].firstIndex(where: { $0 * 100 >= widest * 97 }) ?? top
        let radius = min(max(CGFloat(full - top), 6), 28)
        return Fit(
            left: CGFloat(left), top: CGFloat(top),
            right: CGFloat(w - 1 - right), bottom: CGFloat(h - 1 - bottom),
            radius: radius
        )
    }

    /// Draws one outline around the menu-bar icon and the window it opened,
    /// for as long as that window stays open.
    static func link(itemWindowID: CGWindowID, popupWindowID: CGWindowID) {
        // Off unless asked for: another app's menu gives no reliable edge to
        // trace (its bounds include shadow, its glass is see-through), so the
        // outline rarely fits. `defaults write com.samdeherdt.fold FoldLinkOutline -bool YES`
        guard Constants.bundleIdentifier == "com.samdeherdt.fold",
              UserDefaults.standard.bool(forKey: "FoldLinkOutline")
        else { return }
        unlink(animated: false)
        linkTask = Task { @MainActor in
            var first = true
            var fitted: Fit?
            // Let the window finish fading in before measuring it.
            try? await Task.sleep(for: .milliseconds(220))
            while !Task.isCancelled {
                guard Bridging.getWindowList(option: .onScreen).contains(popupWindowID),
                      let item = Bridging.getWindowBounds(for: itemWindowID),
                      let popup = Bridging.getWindowBounds(for: popupWindowID),
                      popup.width > 40, popup.height > 20
                else { break }
                if linkFrames?.item != item || linkFrames?.popup != popup {
                    linkFrames = (item, popup)
                    fitted = fit(windowID: popupWindowID, bounds: popup)
                    if let fitted {
                        let body = CGRect(
                            x: popup.minX + fitted.left, y: popup.minY + fitted.top,
                            width: popup.width - fitted.left - fitted.right,
                            height: popup.height - fitted.top - fitted.bottom
                        )
                        drawLink(item: item, popup: body, radius: fitted.radius, animated: first)
                        first = false
                    } else {
                        // No outline is better than one that doesn't fit.
                        linkWindow?.orderOut(nil)
                    }
                }
                try? await Task.sleep(for: .milliseconds(90))
            }
            if !Task.isCancelled { unlink(animated: true) }
        }
    }

    static func unlink(animated: Bool) {
        linkTask?.cancel()
        linkTask = nil
        linkFrames = nil
        guard let window = linkWindow, window.isVisible else { return }
        guard animated else { window.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if linkTask == nil { window.orderOut(nil) }
            }
        }
    }

    /// `item` and `popup` are in Quartz coordinates (origin top-left).
    private static func drawLink(item: CGRect, popup: CGRect, radius: CGFloat, animated: Bool) {
        guard let primary = NSScreen.screens.first else { return }
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primary.frame.height - r.maxY, width: r.width, height: r.height)
        }
        let pill = flip(item).insetBy(dx: -1, dy: 2.5)
        let body = flip(popup).insetBy(dx: -2.5, dy: -2.5)
        // Only when the window really hangs under the icon.
        guard body.maxY <= pill.maxY, pill.minY - body.maxY < 40,
              body.minX - 8 <= pill.midX, pill.midX <= body.maxX + 8
        else { unlink(animated: false); return }

        let frame = pill.union(body).insetBy(dx: -8, dy: -8)
        let window = linkWindow ?? {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSView()
            view.wantsLayer = true
            w.contentView = view
            linkWindow = w
            return w
        }()
        window.setFrame(frame, display: false)
        let host = window.contentView!.layer!
        host.sublayers?.forEach { $0.removeFromSuperlayer() }

        let o = frame.origin
        let pillLocal = pill.offsetBy(dx: -o.x, dy: -o.y)
        let bodyLocal = body.offsetBy(dx: -o.x, dy: -o.y)
        let bodyRadius: CGFloat = min(radius + 2.5, bodyLocal.height / 2)
        // The neck runs from the middle of the pill down into the window.
        let neck = CGRect(
            x: pillLocal.minX, y: bodyLocal.maxY - bodyRadius,
            width: pillLocal.width, height: pillLocal.midY - bodyLocal.maxY + bodyRadius
        ).intersection(CGRect(x: bodyLocal.minX, y: 0, width: bodyLocal.width, height: 10000))
        var path = CGPath(roundedRect: bodyLocal, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
        path = path.union(CGPath(roundedRect: pillLocal, cornerWidth: pillLocal.height / 2, cornerHeight: pillLocal.height / 2, transform: nil))
        if !neck.isNull, neck.width > 2, neck.height > 0 {
            path = path.union(CGPath(rect: neck, transform: nil))
        }

        let outline = CAShapeLayer()
        outline.frame = host.bounds
        outline.path = path
        outline.fillColor = nil
        outline.strokeColor = ink.withAlphaComponent(0.45).cgColor
        outline.lineWidth = 1
        outline.lineJoin = .round
        host.addSublayer(outline)

        window.alphaValue = 1
        window.orderFrontRegardless()
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [draw, fade]
            group.duration = 0.42 * timeScale
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            outline.add(group, forKey: "draw")
        }
    }

    // MARK: Pieces

    private static func prepare(covering rect: CGRect, on screen: NSScreen) -> (CALayer, CGPoint) {
        generation += 1
        let frame = rect.insetBy(dx: -40, dy: -24)
        let window = self.window ?? {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
            w.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSView()
            view.wantsLayer = true
            w.contentView = view
            self.window = w
            return w
        }()
        window.setFrame(frame, display: false)
        let host = window.contentView!.layer!
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        host.contentsScale = screen.backingScaleFactor
        window.orderFrontRegardless()
        return (host, frame.origin)
    }

    private static func iconLayer(image: NSImage, tint: NSColor, size: CGSize) -> CALayer {
        let tinted = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        let scale = window?.screen?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        layer.contents = tinted.layerContents(forContentsScale: scale)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: -1)
        return layer
    }

    private static func pulse(in host: CALayer, rect: CGRect, from: CGFloat, to: CGFloat, delay: Double, duration: Double) {
        let ring = CAShapeLayer()
        ring.frame = rect
        ring.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: rect.size),
            cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil
        )
        ring.strokeColor = ink.withAlphaComponent(0.55).cgColor
        ring.fillColor = ink.withAlphaComponent(0.1).cgColor
        ring.lineWidth = 1
        ring.opacity = 0
        host.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = from
        scale.toValue = to
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.3, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "pulse")
    }

    private static func run(_ animations: [CAAnimation], on layer: CALayer, duration: Double, timing: CAMediaTimingFunction) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = timing
        layer.add(group, forKey: "flight")
    }

    private static func finish(after seconds: Double) {
        let current = generation
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.05))
            guard current == generation else { return }
            window?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            window?.orderOut(nil)
        }
    }
}
