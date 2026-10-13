//
//  IceBar.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Combine
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "IceBarPanel")
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Thaw Bar's color.
    private let colorManager = IceBarColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// A Boolean value that indicates whether to show the panel at
    /// the mouse pointer's location, regardless of the user's
    /// settings.
    private var hotkeyLocationOverride = false

    /// Timestamp of most recent `show()`. Used to suppress
    /// `didChangeScreenParametersNotification` auto-hide when the
    /// user clicks an inactive screen's menubar (active menu bar
    /// change posts that notification, racing with the show).
    private var lastShowTimestamp: Date?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Fold: lets the content fold back into the chevron before the panel
    /// hides. The generation cancels a pending hide when the drawer reopens.
    private static let foldLog = DiagLog(category: "FoldHover")
    private weak var shownScreen: NSScreen?
    private let foldMorph = FoldMorph()
    private var foldCloseGeneration = 0
    private var foldHoverTask: Task<Void, Never>?
    private var foldPointerOutsideSince: Date?

    /// Liquid Glass follows the window's appearance, not SwiftUI's colour
    /// scheme, so Fold's Light/Dark choice has to be set on the panel.
    private func applyFoldAppearance() {
        switch UserDefaults.standard.string(forKey: FoldKey.appearance) ?? "dark" {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }
    }

    /// With "Open on hover", close once the pointer has left the drawer, the
    /// chevron and the strip between them for a moment.
    private func startFoldHoverWatch() {
        foldHoverTask?.cancel()
        foldPointerOutsideSince = nil
        // A shortcut-opened drawer stays put wherever the pointer is.
        let closesOnLeave = appState?.settings.general.showOnHover == true && !foldMorph.keyboardActive
        foldHoverTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                updateFoldPassThrough()
                if closesOnLeave { checkFoldHover() }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Fold's menu-bar icon on the screen the drawer is on (or would be on).
    private func foldChevronFrame(on screen: NSScreen?) -> CGRect? {
        guard let screen = screen ?? shownScreen ?? self.screen else { return nil }
        return FoldChevron.frame(of: appState?.menuBarManager.controlItem(withName: .visible)?.window, on: screen)
    }

    /// Samples the screen under the bar (below this window) so translucent
    /// looks can choose an icon colour that contrasts with it.
    private func sampleFoldBackdrop(on screen: NSScreen) {
        let windowID = CGWindowID(windowNumber)
        let displayID = screen.displayID
        Task { @MainActor [weak self] in
            // Let the panel settle at its final frame first.
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, isVisible, windowNumber > 0 else { return }
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            // The bar's rect in top-left global coordinates, below the menu bar.
            let top = max(primaryHeight - frame.maxY, primaryHeight - screen.frame.maxY + menuBarHeight)
            let bottom = primaryHeight - frame.minY
            let bounds = CGRect(x: frame.minX, y: top, width: frame.width, height: max(4, bottom - top))
            guard
                let image = try? await ScreenCapture.captureScreenBelowWindow(
                    excludingWindowID: windowID, screenBounds: bounds, displayID: displayID
                ),
                let brightness = FoldBackdrop.brightness(of: image)
            else { return }
            let isBright = brightness > 0.55
            Self.foldLog.notice("Fold backdrop brightness \(String(format: "%.2f", brightness)) → \(isBright ? "dark" : "light") icons")
            if foldMorph.backdropIsBright != isBright {
                foldMorph.backdropIsBright = isBright
            }
        }
    }

    /// The liquid pour makes the panel reach up over the menu bar, covering the
    /// chevron. While the pointer is in that strip, let clicks fall through so
    /// the chevron still gets its left and right clicks.
    /// The bar itself in screen coordinates: the window minus its shadow
    /// margins and the strip over the menu bar.
    private func foldBarRect(on screen: NSScreen) -> NSRect {
        let menuBarBottom = screen.frame.maxY - screen.getMenuBarHeightEstimate()
        let top = min(frame.maxY, menuBarBottom)
        let bottom = frame.minY + FoldWidth.bottomMargin
        return NSRect(
            x: frame.minX + FoldWidth.sideMargin, y: bottom,
            width: frame.width - FoldWidth.sideMargin * 2, height: max(0, top - bottom)
        )
    }

    private func updateFoldPassThrough() {
        guard let screen = shownScreen ?? screen else { return }
        // Only the bar takes clicks. The strip over the menu bar and the
        // shadow margins let them fall through to whatever is underneath.
        let offBar = !foldBarRect(on: screen).insetBy(dx: -2, dy: -2).contains(FoldPointer.location)
        if ignoresMouseEvents != offBar, foldMorph.isOpen {
            ignoresMouseEvents = offBar
        }
    }

    private func checkFoldHover() {
        guard isVisible, foldMorph.isOpen, let screen = shownScreen ?? screen else { return }
        // Still hovering while over the drawer, the chevron, or the strip of
        // menu bar straight above the drawer that connects the two.
        let bar = foldBarRect(on: screen)
        let drawerColumn = NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: screen.frame.maxY - bar.minY)
        let chevron = foldChevronFrame(on: screen) ?? .zero
        let pointer = FoldPointer.location
        if drawerColumn.insetBy(dx: -8, dy: -8).contains(pointer) || chevron.insetBy(dx: -4, dy: -4).contains(pointer) {
            foldPointerOutsideSince = nil
        } else if let since = foldPointerOutsideSince {
            if Date.now.timeIntervalSince(since) > 0.25 {
                Self.foldLog.notice("Fold hover-away: closing, pointer=\(pointer.debugDescription) frame=\(self.frame.debugDescription)")
                hide()
            }
        } else {
            foldPointerOutsideSince = .now
        }
    }

    override var canBecomeKey: Bool {
        // Takes the keyboard only when opened with the shortcut (see show()).
        Constants.bundleIdentifier == "com.samdeherdt.fold" ? true : super.canBecomeKey
    }

    private var foldTypeBuffer = ""
    private var foldTypeBufferDate = Date.distantPast

    private func foldMoveSelection(by delta: Int) {
        let items = foldMorph.keyItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == foldMorph.selectedWindowID }
        let next = current.map { min(max($0 + delta, 0), items.count - 1) } ?? (delta < 0 ? items.count - 1 : 0)
        foldMorph.selectedWindowID = items[next].id
    }

    override func keyDown(with event: NSEvent) {
        guard Constants.bundleIdentifier == "com.samdeherdt.fold", foldMorph.isOpen else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53: // Escape
            hide()
        case 123, 126: // Left, Up
            foldMoveSelection(by: -1)
        case 124, 125: // Right, Down
            foldMoveSelection(by: 1)
        case 36, 76, 49: // Return, Enter, Space
            if foldMorph.selectedWindowID != nil { foldMorph.activateRequest += 1 }
        default:
            // Type a few letters to jump to an app by name.
            guard let typed = event.charactersIgnoringModifiers?.lowercased(), !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
            else { return }
            if Date.now.timeIntervalSince(foldTypeBufferDate) > 0.8 { foldTypeBuffer = "" }
            foldTypeBuffer += typed
            foldTypeBufferDate = .now
            if let match = foldMorph.keyItems.first(where: { $0.name.lowercased().hasPrefix(foldTypeBuffer) })
                ?? foldMorph.keyItems.first(where: { $0.name.lowercased().contains(foldTypeBuffer) })
            {
                foldMorph.selectedWindowID = match.id
            }
        }
    }

    /// A vertical wheel can't scroll a horizontal strip; turn it sideways.
    override func sendEvent(_ event: NSEvent) {
        // A click on the strip over the menu-bar icon belongs to the icon.
        // Click-through normally hands it over, but if this window still
        // gets it (the pointer arrived between checks), act on it here.
        if Constants.bundleIdentifier == "com.samdeherdt.fold",
           [.leftMouseDown, .rightMouseDown, .rightMouseUp].contains(event.type),
           let chevron = appState?.menuBarManager.controlItem(withName: .visible),
           let chevronFrame = foldChevronFrame(on: nil),
           chevronFrame.insetBy(dx: -3, dy: -3).contains(FoldPointer.location)
        {
            switch event.type {
            case .rightMouseUp: chevron.foldHandleForwardedClick(isRightClick: true)
            case .leftMouseDown: chevron.foldHandleForwardedClick(isRightClick: false)
            default: break
            }
            return
        }
        guard
            event.type == .scrollWheel,
            event.phase.isEmpty, event.momentumPhase.isEmpty,
            abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
            let cgEvent = event.cgEvent?.copy()
        else {
            super.sendEvent(event)
            return
        }
        let pairs: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for (vertical, horizontal) in pairs {
            let value = cgEvent.getDoubleValueField(vertical)
            cgEvent.setDoubleValueField(horizontal, value: value)
            cgEvent.setDoubleValueField(vertical, value: 0)
        }
        super.sendEvent(NSEvent(cgEvent: cgEvent) ?? event)
    }

    /// Creates a new Thaw Bar panel with Liquid Glass support.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "\(Constants.displayName) Bar")
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        // Liquid Glass: transparent window with shadow
        self.backgroundColor = .clear
        self.isOpaque = false
        // Fold draws its own shadow under the bar: the window server's shadow
        // is traced from a cached snapshot of the window's shape, which goes
        // stale and ragged as the drawer animates.
        self.hasShadow = Constants.bundleIdentifier != "com.samdeherdt.fold"
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide the panel when the active space or screen parameters change.
        // Guard against didChangeScreenParametersNotification racing with
        // show(): clicking an inactive screen's menubar activates it, which
        // posts this notification. Without the guard, the notification would
        // hide the panel immediately after show() opened it.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard
                let self,
                let ts = self.lastShowTimestamp,
                Date().timeIntervalSince(ts) >= 1
            else {
                return
            }
            self.hide()
        }
        .store(in: &c)

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen = shownScreen ?? screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for iceBarLocation: IceBarLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let isRow = appState.settings.displaySettings.configuration(for: screen.displayID).iceBarLayout == .horizontal
            let pourInset = Constants.bundleIdentifier == "com.samdeherdt.fold"
                ? FoldMotion.current.effective(inRow: isRow).pourInset(menuBarHeight: menuBarHeight) : 0
            let defaultOriginY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height + pourInset

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: defaultOriginY)
            }

            if hotkeyLocationOverride, let location = MouseHelpers.locationAppKit {
                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width
                let lowerBoundY = screen.frame.minY
                let upperBoundY = screen.frame.maxY - frame.height

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... (upperBoundX > lowerBoundX ? upperBoundX : lowerBoundX))
                let y = (location.y - frame.height / 2).clamped(to: lowerBoundY ... (upperBoundY > lowerBoundY ? upperBoundY : lowerBoundY))

                return CGPoint(x: x, y: y)
            }

            switch iceBarLocation {
            case .dynamic:
                if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .iceIcon)
            case .mousePointer:
                guard let location = MouseHelpers.locationAppKit else {
                    return getOrigin(for: .iceIcon)
                }

                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width

                guard lowerBoundX <= upperBoundX else {
                    return originForRightOfScreen
                }

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... upperBoundX)

                return CGPoint(x: x, y: defaultOriginY)
            case .iceIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                    // Bridging API is more reliable than controlItem.frame in some
                    // cases (like if the item is offscreen).
                    let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
                else {
                    return originForRightOfScreen
                }

                // Fold: the icon's copy on this screen, not the real window's
                // position on whichever display hosts it.
                let midX = Constants.bundleIdentifier == "com.samdeherdt.fold"
                    ? (foldChevronFrame(on: screen)?.midX ?? itemBounds.midX) : itemBounds.midX
                return CGPoint(x: (midX - frame.width / 2).clamped(to: lowerBound ... upperBound), y: defaultOriginY)
            case .leftAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.minX + 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            case .rightAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.maxX - frame.width - 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            }
        }

        let location = appState.settings.displaySettings.iceBarLocation(for: screen.displayID)
        setFrameOrigin(getOrigin(for: location))
        if let chevron = foldChevronFrame(on: screen) {
            let anchor = chevron.midX - frame.minX
            if foldMorph.anchorWindowX != anchor { foldMorph.anchorWindowX = anchor }
        }
    }

    /// Shows the panel on the given screen, displaying the given
    /// menu bar section.
    func show(
        section: MenuBarSection.Name,
        on screen: NSScreen,
        triggeredByHotkey: Bool = false
    ) {
        guard let appState else {
            return
        }
        shownScreen = screen

        let menuBarHeight = screen.getMenuBarHeightEstimate()
        diagLog.notice("""
        show: screen=\(screen.displayID) \
        backingScaleFactor=\(Double(screen.backingScaleFactor)) \
        hasNotch=\(screen.hasNotch) \
        menuBarHeight=\(Double(menuBarHeight)) \
        frame=\(screen.frame.debugDescription) \
        visibleFrame=\(screen.visibleFrame.debugDescription)
        """)

        hotkeyLocationOverride = triggeredByHotkey && appState.settings.general.iceBarLocationOnHotkey

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        foldCloseGeneration += 1
        ignoresMouseEvents = false
        foldMorph.keyboardActive = triggeredByHotkey
        foldMorph.selectedWindowID = nil
        foldMorph.isOpen = true
        if Constants.bundleIdentifier == "com.samdeherdt.fold" {
            applyFoldAppearance()
            startFoldHoverWatch()
            // Pass clicks through to the icon from the first frame, not the
            // first watch tick, so a quick right-click never hits the drawer.
            updateFoldPassThrough()
        }
        defer {
            // Opened with the shortcut: take the keyboard (without activating
            // Fold) so arrows, Return and Esc drive the drawer.
            if Constants.bundleIdentifier == "com.samdeherdt.fold", triggeredByHotkey {
                makeKey()
            }
            // Only translucent looks need to know what's behind the bar.
            let look = FoldLook.current
            let glass = UserDefaults.standard.string(forKey: FoldKey.glass) ?? "system"
            let ownsItsTone = look.forcesLightIcons || look.forcesDarkIcons || look == .solid || (look == .glass && glass == "tinted")
            if Constants.bundleIdentifier == "com.samdeherdt.fold", !ownsItsTone {
                sampleFoldBackdrop(on: screen)
            }
        }
        appState.navigationState.isIceBarPresented = true
        currentSection = section
        lastShowTimestamp = Date()

        // Show the panel immediately with whatever cached data we have.
        // The SwiftUI view observes itemManager and imageCache, so it
        // will re-render automatically as the background updates land.
        contentView = IceBarHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section,
            morph: foldMorph
        )

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        // Rehide temporarily shown items and refresh caches in the
        // background. Ordering is preserved: rehide moves items back
        // to their correct sections before the cache is rebuilt.
        // The task is cancelled in close() to avoid holding appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            await appState.itemManager.rehideTemporarilyShownItems(force: true)
            guard !Task.isCancelled else { return }
            // Settle delay: when the IceBar just opened on a screen that
            // was previously inactive, the menu bar has moved screens and
            // NSStatusItem windows (control item chevrons) are still
            // positioning. Without this delay, cacheItemsIfNeeded can
            // recache with stale/zero control item bounds, causing
            // findSection() to misclassify all items as .visible and
            // leave the hidden section cache empty ("No items…").
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.updateCache()
        }
    }

    /// Hides the panel.
    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        foldCloseGeneration += 1
        foldHoverTask?.cancel()
        foldHoverTask = nil
        let closeDelay = FoldMotion.current.closeDelay
        guard
            Constants.bundleIdentifier == "com.samdeherdt.fold",
            foldMorph.isOpen,
            isVisible,
            contentView != nil,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            closeDelay > 0
        else {
            foldMorph.isOpen = false
            finishClose()
            return
        }
        foldMorph.isOpen = false
        appState?.navigationState.isIceBarPresented = false
        ignoresMouseEvents = true
        let generation = foldCloseGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay) { [weak self] in
            guard let self, foldCloseGeneration == generation else { return }
            finishClose()
        }
    }

    private func finishClose() {
        ignoresMouseEvents = false
        CustomTooltipPanel.shared.dismiss()
        cacheTask?.cancel()
        cacheTask = nil
        contentView = nil
        orderOut(nil)
        super.close()
        currentSection = nil
        appState?.navigationState.isIceBarPresented = false
    }

    /// Resizes the panel to match the hosting view's intrinsic content size.
    func resizeToContent() {
        // Re-anchor on the screen the drawer opened on. `self.screen` can name
        // a neighbouring display when the drawer touches the top edge (as the
        // liquid pour does), which would fling the drawer onto that display.
        guard let contentView, let screen = shownScreen ?? screen else { return }
        let ideal = contentView.intrinsicContentSize
        guard ideal != .zero, ideal != frame.size else { return }
        // Grow from the top edge. Keeping the bottom edge would push a fresh
        // (zero-height) drawer up past the top of the screen and onto a
        // display above it, which AppKit then treats as the drawer's screen.
        let topAnchored = NSPoint(x: frame.minX, y: frame.maxY - ideal.height)
        setFrame(NSRect(origin: topAnchored, size: ideal), display: true, animate: false)
        updateOrigin(for: screen)
    }
}

// MARK: - IceBarHostingView

private final class IceBarHostingView: NSHostingView<IceBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override func layout() {
        super.layout()
        (window as? IceBarPanel)?.resizeToContent()
    }

    init(
        appState: AppState,
        colorManager: IceBarColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name,
        morph: FoldMorph
    ) {
        let rootView = IceBarContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section,
            morph: morph
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: IceBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - IceBarContentView

private struct IceBarContentView: View {
    let appState: AppState
    let colorManager: IceBarColorManager
    let itemManager: MenuBarItemManager
    let imageCache: MenuBarItemImageCache
    let menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var cacheGracePeriodActive = true
    @State private var loadingTimedOut = false
    @AppStorage(FoldKey.appearance) private var foldAppearance = "dark"
    @AppStorage(FoldKey.maxWidth) private var foldMaxWidth = 0.0
    @AppStorage(FoldKey.look) private var foldLook = FoldLook.glass.rawValue
    @AppStorage(FoldKey.glass) private var foldGlass = "system"
    @AppStorage(FoldKey.motion) private var foldMotion = FoldMotion.liquid.rawValue
    @AppStorage(FoldKey.iconSpacing) private var foldIconSpacing = 0.0
    @AppStorage(FoldKey.iconScale) private var foldIconScale = 1.0
    @AppStorage(FoldKey.maxRows) private var foldMaxRows = 8
    @AppStorage(FoldKey.columnNames) private var foldColumnNames = false
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var morphProgress: CGFloat = 0

    private var foldColorScheme: ColorScheme {
        foldAppearance == "light" ? .light : foldAppearance == "dark" ? .dark : systemColorScheme
    }

    let screen: NSScreen
    let section: MenuBarSection.Name
    let morph: FoldMorph

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var displaySettings: DisplaySettingsManager {
        appState.settings.displaySettings
    }

    private var layout: IceBarLayout {
        displaySettings.configuration(for: screen.displayID).iceBarLayout
    }

    private var gridColumns: Int {
        displaySettings.configuration(for: screen.displayID).gridColumns
    }

    private var itemSpacing: CGFloat {
        if Constants.bundleIdentifier == "com.samdeherdt.fold" {
            return CGFloat(foldIconSpacing)
        }
        let offset = displaySettings.configuration(for: screen.displayID).itemSpacingOffset
        return max(0, CGFloat(offset).rounded())
    }

    private var horizontalPadding: CGFloat {
        // A column hugs its icons: about as wide as a row bar is tall.
        layout == .vertical ? 3 : 8
    }

    /// Size the drawer to its icons so every hidden item is reachable. It only
    /// scrolls once the icons outgrow the screen; a fixed cap here clipped the
    /// leading items, which a vertical mouse wheel cannot scroll back into view.
    private var compactWidth: CGFloat {
        // The Length setting measures the bar; the window adds its margins.
        min(maxDrawerWidth + FoldWidth.sideMargin * 2, naturalWidth)
    }

    private var maxDrawerWidth: CGFloat {
        FoldWidth.cap(stored: foldMaxWidth, screenWidth: screen.frame.width)
    }

    /// Where the menu-bar icon sits, in the drawer window's coordinates, so
    /// the drawer grows out of it (set by the panel when it positions itself).
    private var morphAnchorX: CGFloat? {
        morph.anchorWindowX
    }

    /// White icons where the bar is dark. Opaque and tinted looks set their
    /// own darkness; translucent ones (glass, frosted, outline, minimal) take
    /// on whatever is behind them, so their icons follow the sampled backdrop.
    private var foldUsesLightIcons: Bool {
        let look = FoldLook(rawValue: foldLook) ?? .glass
        if look.forcesLightIcons { return true }
        if look.forcesDarkIcons { return false }
        let ownsItsTone = look == .solid || (look == .glass && foldGlass == "tinted")
        if !ownsItsTone, let bright = morph.backdropIsBright {
            return !bright
        }
        return foldColorScheme == .dark
    }

    private var motion: FoldMotion {
        (FoldMotion(rawValue: foldMotion) ?? .liquid).effective(inRow: layout == .horizontal)
    }

    /// Hands the icon order to the panel for arrow keys and type-to-jump, and
    /// starts the selection on the icon nearest the menu-bar icon.
    private func publishKeyItems() {
        let keyItems = items.map { FoldKeyItem(id: $0.windowID, name: $0.displayName) }
        if morph.keyItems != keyItems { morph.keyItems = keyItems }
        if morph.keyboardActive, morph.selectedWindowID == nil {
            morph.selectedWindowID = keyItems.last?.id
        }
    }

    /// Transparent strip over the menu bar that the liquid pour starts in.
    private var pourInset: CGFloat {
        layout == .horizontal ? motion.pourInset(menuBarHeight: screen.getMenuBarHeightEstimate()) : 0
    }

    /// The menu-bar button's vertical centre, measured from the bar's top edge.
    private var pourCenterY: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        return (menuBarHeight / 2 - 1) - (pourInset + 2)
    }

    private func setMorph(open: Bool) {
        let animation = open ? motion.openAnimation : motion.closeAnimation
        guard !reduceMotion, let animation else {
            morphProgress = open ? 1 : 0
            return
        }
        withAnimation(animation) { morphProgress = open ? 1 : 0 }
    }

    private var naturalWidth: CGFloat {
        let iconsWidth = items.reduce(CGFloat.zero) { total, item in
            guard let image = imageCache.images[item.tag]?.nsImage,
                  image.size.height > 0 else { return total + 24 }
            let height = itemMaxHeight ?? image.size.height
            return total + image.size.width * height / image.size.height
        }
        let spacing = CGFloat(max(0, items.count - 1)) * itemSpacing
        let width = items.isEmpty ? 220 : iconsWidth + spacing + horizontalPadding * 2 + FoldWidth.sideMargin * 2
        return max(44, width)
    }

    private var verticalPadding: CGFloat {
        2
    }

    /// Fold's icon-size setting; the bar grows with its icons.
    private var foldScale: CGFloat {
        Constants.bundleIdentifier == "com.samdeherdt.fold" ? CGFloat(min(max(foldIconScale, 0.7), 1.4)) : 1
    }

    private var contentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate() * foldScale
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var itemMaxHeight: CGFloat? {
        // Use the raw menu bar height so icons match their native size,
        // regardless of any inset or padding applied to the bar shape.
        // The clip shape trims any overflow.
        let menuBarHeight = screen.getMenuBarHeightEstimate() * foldScale
        return menuBarHeight > 0 ? menuBarHeight : nil
    }

    /// Per-column maximum widths for the grid layout.
    private var columnWidths: [CGFloat] {
        // Zero-width placeholders (not []) during transient zero-height
        // states: the grid body subscripts columnWidths[colIndex] whenever
        // rows.count > 1, and an empty array would crash there.
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else {
            return Array(repeating: 0, count: gridColumns)
        }
        let allItems = items
        let rows = allItems.chunks(ofCount: gridColumns).map(Array.init)
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                guard let cachedImage = imageCache.images[row[col].tag] else { return nil }
                let image = cachedImage.nsImage
                guard image.size.height > 0 else { return image.size.width }
                let scale = maxHeight / image.size.height
                return image.size.width * scale
            }.max() ?? 0
        }
    }

    /// Maximum content height for vertical and grid layouts so the panel
    /// does not extend below the visible screen area.
    private var maxContentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        let available = (screen.frame.maxY - menuBarHeight) - screen.visibleFrame.minY
        let totalPadding: CGFloat = 10 + verticalPadding * 2
        let screenLimit = max(available - totalPadding, contentHeight)
        guard Constants.bundleIdentifier == "com.samdeherdt.fold" else { return screenLimit }
        // Fold: show at most this many rows, then scroll.
        return min(screenLimit, CGFloat(max(1, foldMaxRows)) * contentHeight)
    }

    /// Total intrinsic height of all items/rows for the current layout.
    private var totalContentHeight: CGFloat {
        switch layout {
        case .horizontal:
            return contentHeight
        case .vertical:
            return CGFloat(items.count) * contentHeight
        case .grid:
            let rowCount = Int(ceil(Double(items.count) / Double(gridColumns)))
            return CGFloat(rowCount) * contentHeight
        }
    }

    private var clipShape: some InsettableShape {
        Capsule()
    }

    var body: some View {
        ZStack {
            Group {
                if layout == .horizontal {
                    content.frame(height: contentHeight)
                } else {
                    content.frame(height: min(totalContentHeight, maxContentHeight))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foldUsesLightIcons ? .white : .black)
            .shadow(color: foldLook == FoldLook.minimal.rawValue ? .black.opacity(0.45) : .clear, radius: 2)
            .modifier(FoldMorphReveal(progress: morphProgress, anchorX: morphAnchorX, motion: motion, pourCenterY: pourCenterY, slotCount: items.count, anchorInWindow: true, cornerRadius: layout == .horizontal ? nil : 18))

            if configuration.current.borderOnThawBar {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        // Room for the bar's shadow to fade out, and for Pop/Elastic to
        // overshoot, without the window's edge cutting them off.
        .padding(.horizontal, FoldWidth.sideMargin)
        .padding(.bottom, FoldWidth.bottomMargin)
        .padding(.top, 2 + pourInset)
        .frame(width: layout == .horizontal ? compactWidth : nil)
        .frame(maxWidth: screen.frame.width)
        .fixedSize(horizontal: true, vertical: layout == .horizontal)
        .environment(\.colorScheme, foldColorScheme)
        .onAppear {
            Self.diagLog.notice("""
            IceBarContentView appeared: \
            displayID=\(screen.displayID) \
            backingScaleFactor=\(Double(screen.backingScaleFactor)) \
            hasNotch=\(screen.hasNotch) \
            contentHeight=\(Double(contentHeight)) \
            itemMaxHeight=\(Double(itemMaxHeight ?? 0)) \
            menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) \
            layout=\(String(describing: layout)) \
            items=\(items.count) \
            section=\(section.logString)
            """)
        }
        .onFrameChange(update: $frame)
        .environment(morph)
        .onAppear {
            setMorph(open: true)
            publishKeyItems()
            morph.showsNames = layout == .vertical && foldColumnNames
            morph.motion = motion
        }
        .onChange(of: motion) { _, motion in morph.motion = motion }
        .onChange(of: layout == .vertical && foldColumnNames) { _, shows in morph.showsNames = shows }
        .onChange(of: items.map(\.windowID)) { publishKeyItems() }
        .onChange(of: morph.isOpen) { _, isOpen in setMorph(open: isOpen) }
        .task(id: section) {
            cacheGracePeriodActive = true
            loadingTimedOut = false
            try? await Task.sleep(for: .milliseconds(600))
            cacheGracePeriodActive = false
            try? await Task.sleep(for: .seconds(2))
            loadingTimedOut = true
        }
    }

    private static let diagLog = DiagLog(category: "IceBar.Content")

    /// Opens the permissions settings pane, hiding the current section first.
    private func openPermissionsSettings() {
        menuBarManager.section(withName: section)?.hide()
        appState.navigationState.settingsNavigationIdentifier = .advanced
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    @ViewBuilder
    private var content: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            HStack {
                Text("The \(Constants.displayName) Bar requires screen recording permissions.")

                Button {
                    openPermissionsSettings()
                } label: {
                    Text("Open \(Constants.displayName) Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'requires screen recording permissions' — cachedCheckPermissions() returned false")
            }
        } else if section == .alwaysHidden || section == .hidden, items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                } else if !loadingTimedOut {
                    Text("No items in this section")
                } else {
                    Text("No items in this section")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: cacheGracePeriodActive) {
                Self.diagLog.debug("IceBar content: grace period changed to \(self.cacheGracePeriodActive) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onChange(of: loadingTimedOut) {
                Self.diagLog.debug("IceBar content: loading timeout changed to \(self.loadingTimedOut) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onAppear {
                Self.diagLog.debug("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "No items")' for section \(self.section.logString) (grace period active: \(self.cacheGracePeriodActive))")
            }
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                if loadingTimedOut {
                    Text("Unable to load menu bar items")
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: loading timeout changed to \(self.loadingTimedOut) — itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'Loading menu bar items…' — itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else if imageCache.cacheFailed(for: section) {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                } else if loadingTimedOut {
                    // Final state: no further automatic retry.
                    Text("Unable to display menu bar items")
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: cacheFailed timeout changed to \(self.loadingTimedOut) for section \(self.section.logString)")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "Unable to display")' for section \(self.section.logString) — imageCache.cacheFailed=true (grace period active: \(self.cacheGracePeriodActive), loadingTimedOut: \(self.loadingTimedOut), cached images count: \(self.imageCache.images.count), items in section: \(self.itemManager.itemCache[self.section].count))")
            }
        } else {
            let isLightBackground = !foldUsesLightIcons
            switch layout {
            case .horizontal:
                ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            IceBarItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
                            )
                        }
                    }
                    .frame(height: contentHeight)
                }
                .environment(\.isScrollEnabled, true)
                .defaultScrollAnchor(.trailing)
                .onChange(of: morph.selectedWindowID) { _, selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(selected, anchor: .center) }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }
                }

            case .vertical:
                ScrollView(.vertical) {
                    VStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            IceBarItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
                            )
                        }
                    }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }

            case .grid:
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        let rows = items.chunks(ofCount: gridColumns).map(Array.init)
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowItems in
                            HStack(spacing: itemSpacing) {
                                ForEach(Array(rowItems.enumerated()), id: \.element.windowID) { colIndex, item in
                                    let itemView = IceBarItemView(
                                        imageCache: imageCache,
                                        itemManager: itemManager,
                                        menuBarManager: menuBarManager,
                                        item: item,
                                        section: section,
                                        displayID: screen.displayID,
                                        maxHeight: itemMaxHeight,
                                        tooltipDelay: appState.settings.advanced.tooltipDelay,
                                        isLightBackground: isLightBackground
                                    )
                                    if rows.count > 1 {
                                        itemView
                                            .frame(width: columnWidths[colIndex], alignment: .center)
                                    } else {
                                        itemView
                                    }
                                }
                                // Only pad the last row when there are multiple rows,
                                // so partial rows align with the columns above.
                                if rows.count > 1, rowIndex == rows.count - 1, rowItems.count < gridColumns {
                                    ForEach(rowItems.count ..< gridColumns, id: \.self) { colIndex in
                                        Color.clear
                                            .frame(width: columnWidths[colIndex], height: contentHeight)
                                    }
                                }
                            }
                            .frame(height: contentHeight)
                        }
                    }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }
            }
        }
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    private static let diagLog = DiagLog(category: "IceBar.ItemView")

    let imageCache: MenuBarItemImageCache
    let itemManager: MenuBarItemManager
    let menuBarManager: MenuBarManager

    @State private var isHovered = false
    @Environment(FoldMorph.self) private var foldMorph: FoldMorph?

    /// Cascade: this icon has popped in.
    @State private var cascadeIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cascades: Bool {
        foldMorph?.motion == .cascade && !reduceMotion
    }

    /// Pops this icon in after its neighbours nearer the menu-bar icon,
    /// 30 ms apart.
    private func startCascade() {
        guard cascades, !cascadeIn, let items = foldMorph?.keyItems, !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == item.windowID } ?? 0
        let rank = items.count - 1 - index
        withAnimation(.spring(duration: 0.32, bounce: 0.35).delay(0.05 + Double(rank) * 0.03)) {
            cascadeIn = true
        }
    }

    private var isKeySelected: Bool {
        foldMorph?.keyboardActive == true && foldMorph?.selectedWindowID == item.windowID
    }

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let tooltipDelay: TimeInterval
    let isLightBackground: Bool

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            IceBarItemView.diagLog.debug("leftClick: user clicked \(item.logString)")
            let panel = menuBarManager.iceBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                // Wait until the IceBar panel is fully closed before checking
                // item visibility. Uses KVO on isVisible so we resume as soon
                // as the panel hides rather than busy-polling.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: .left)
                        let duration = Date.now.timeIntervalSince(clickStartTime)
                        IceBarItemView.diagLog.debug("leftClick: ✓ completed in \(Int(duration * 1000))ms (on-screen path)")
                    } catch {
                        // Surfacing this matters: a swallowed error here is a
                        // user click that silently does nothing.
                        IceBarItemView.diagLog.error("leftClick: failed for \(item.logString): \(error)")
                    }
                } else {
                    // temporarilyShow handles move, click, and fallback click
                    // internally so that shownInterfaceWindow is always captured
                    // regardless of which click attempt succeeds.
                    let result = await itemManager.temporarilyShow(item: item, clickingWith: .left, on: displayID, fastPath: true)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("leftClick: completed in \(Int(duration * 1000))ms (temp-show path, result=\(result))")
                }
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let panel = menuBarManager.iceBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: .right)
                    } catch {
                        // Surfacing this matters: a swallowed error here is a
                        // user click that silently does nothing.
                        IceBarItemView.diagLog.error("rightClick: failed for \(item.logString): \(error)")
                    }
                } else {
                    let result = await itemManager.temporarilyShow(item: item, clickingWith: .right, on: displayID, fastPath: true)
                    IceBarItemView.diagLog.debug("rightClick: temp-show result=\(result)")
                }
            }
        }
    }

    /// Re-fetches on-screen items and returns the live `MenuBarItem` whose
    /// tag+PID matches `item`, or `nil` if the item is not currently on-screen.
    ///
    /// Matching by tag+PID rather than the cached `windowID` guards against
    /// CGWindowID recycling after a long system sleep, which would otherwise
    /// cause `isWindowOnScreen` to return a false positive for an unrelated window.
    private func liveOnScreenItem(matching item: MenuBarItem, on displayID: CGDirectDisplayID) async -> MenuBarItem? {
        let liveItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        guard let liveItem = liveItems.first(matchingTag: item.tag, pid: item.sourcePID ?? item.ownerPID) else { return nil }
        return Bridging.isWindowOnScreen(liveItem.windowID) ? liveItem : nil
    }

    private var image: NSImage? {
        guard let cachedImage = imageCache.images[item.tag] else {
            return nil
        }
        return cachedImage.nsImage
    }

    private func targetSize(for image: NSImage) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
        }

        // Scale to fill the available height exactly. This handles both
        // directions: shrinking oversized captures (e.g. multi-monitor with
        // different scale factors) and growing undersized ones (e.g. 16"
        // MacBook Pro where the captured item height can be smaller than the
        // IceBar's content height derived from the full notch-area menu bar).
        let scale = maxHeight / intrinsic.height
        return CGSize(width: intrinsic.width * scale, height: maxHeight)
    }

    /// Column with names: a fixed-width row of icon + app name.
    private static let namedRowWidth: CGFloat = 190

    @ViewBuilder
    private func iconAndName(_ image: NSImage, size: CGSize) -> some View {
        let icon = Image(nsImage: image)
            .renderingMode(.template)
            .interpolation(.high)
            .antialiased(true)
            .resizable()
            .frame(width: size.width, height: size.height)
        if foldMorph?.showsNames == true {
            HStack(spacing: 6) {
                icon.frame(width: max(size.width, size.height), alignment: .center)
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: Self.namedRowWidth, height: size.height, alignment: .leading)
        } else {
            icon
        }
    }

    var body: some View {
        if let image {
            let size = targetSize(for: image)
            iconAndName(image, size: size)
                .foregroundStyle(isLightBackground ? .black : .white)
                .background {
                    FoldBarShape(radius: foldMorph?.showsNames == true ? 9 : nil)
                        .fill((isLightBackground ? Color.black : Color.white).opacity(isKeySelected ? 0.28 : isHovered ? 0.15 : 0))
                        .padding(.vertical, 3)
                }
                .contentShape(Rectangle())
                .overlay {
                    IceBarItemClickView(
                        item: item,
                        tooltipDelay: tooltipDelay,
                        leftClickAction: leftClickAction,
                        rightClickAction: rightClickAction,
                        onHover: { hovering in
                            isHovered = hovering
                        }
                    )
                }
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .animation(.easeOut(duration: 0.12), value: isKeySelected)
                .scaleEffect(cascades && !cascadeIn ? 0.6 : 1)
                .opacity(cascades && !cascadeIn ? 0 : 1)
                .onAppear { startCascade() }
                .onChange(of: foldMorph?.keyItems.count) { startCascade() }
                .onChange(of: foldMorph?.activateRequest) {
                    if isKeySelected { leftClickAction() }
                }
                .accessibilityLabel(item.displayName)
                .accessibilityAction(named: "left click", leftClickAction)
                .accessibilityAction(named: "right click", rightClickAction)
        }
    }
}

// MARK: - IceBarItemClickView

private struct IceBarItemClickView: NSViewRepresentable {
    final class Represented: NSView {
        var item: MenuBarItem
        var tooltipDelay: TimeInterval

        var leftClickAction: () -> Void
        var rightClickAction: () -> Void
        var onHover: (Bool) -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
        private var tooltipTrackingArea: NSTrackingArea?

        init(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            super.init(frame: .zero)
        }

        func update(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            tooltipController.text = item.displayName
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tooltipTrackingArea {
                removeTrackingArea(tooltipTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tooltipTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            tooltipController.scheduleShow(delay: tooltipDelay)
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            tooltipController.cancel()
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            tooltipController.cancel()
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            tooltipController.cancel()
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem
    let tooltipDelay: TimeInterval

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> Represented {
        Represented(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }

    func updateNSView(_ nsView: Represented, context _: Context) {
        // Keep the backing `NSView` in sync with SwiftUI updates; tooltip text,
        // tooltip timing, and click handlers can all change after creation.
        nsView.update(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }
}
