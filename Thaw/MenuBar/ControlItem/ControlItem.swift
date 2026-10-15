//
//  ControlItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import Observation

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem {
    /// An identifier for a control item.
    nonisolated enum Identifier: String, CaseIterable {
        /// The identifier for the control item for the visible section.
        case visible = "Thaw.ControlItem.Visible"
        /// The identifier for the control item for the hidden section.
        case hidden = "Thaw.ControlItem.Hidden"
        /// The identifier for the control item for the always-hidden section.
        case alwaysHidden = "Thaw.ControlItem.AlwaysHidden"

        /// A tag for the control item with this identifier.
        var tag: MenuBarItemTag {
            switch self {
            case .visible: .visibleControlItem
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }

        /// Returns the length associated with this identifier and
        /// the given hiding state.
        func length(for state: HidingState) -> CGFloat {
            switch self {
            case .visible:
                Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .showSection: Lengths.standard
                case .hideSection: Lengths.expanded
                }
            }
        }
    }

    /// A hiding state for a control item.
    enum HidingState {
        case showSection
        case hideSection
    }

    /// A namespace for control item lengths.
    private nonisolated enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10000
    }

    /// Storage for a control item's underlying status item.
    private final class StatusItemStorage {
        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Set once `dispose()` has run, so `deinit` doesn't remove the
        /// status item a second time.
        private var isDisposed = false

        /// Creates a new storage instance.
        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem.identifier)

            self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
            self.statusItem.autosaveName = controlItem.identifier.rawValue

            if let button = statusItem.button {
                if let contentView = button.window?.contentView {
                    let constraints = contentView.constraintsAffectingLayout(for: .horizontal)
                    if let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button)) {
                        assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                        self.constraint = constraint
                    } else {
                        self.constraint = nil
                    }

                    NSLayoutConstraint.activate([
                        button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    ])
                } else {
                    self.constraint = nil
                }

                button.target = controlItem
                button.action = #selector(controlItem.performAction)
                button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            } else {
                self.constraint = nil
            }
        }

        @MainActor
        deinit {
            guard !isDisposed else {
                return
            }
            removeStatusItem()
        }

        /// Explicitly tears down the status item, ahead of (and instead of)
        /// relying on `deinit`. Used by `ControlItem.recreateStatusItem()`
        /// so the old status item is fully removed — and its position
        /// cached to the shared `autosaveName` slot — before a new
        /// `StatusItemStorage` is constructed at that same autosave name.
        /// Without this, the new `NSStatusItem` would briefly exist
        /// alongside the old one under the same autosaveName, and the old
        /// one's later, deinit-driven removal would overwrite the autosave
        /// slot with its own (possibly stale/garbage, in the #754 failure
        /// state) position, clobbering what the new item just restored.
        @MainActor
        func dispose() {
            guard !isDisposed else {
                return
            }
            isDisposed = true
            removeStatusItem()
        }

        /// Removes the status item from the status bar.
        private func removeStatusItem() {
            // Removing the status item has the unwanted side effect of
            // deleting the preferred position. Cache and restore it.
            //
            // Dividers are restored too, for the reason in
            // hideIceIconCompletely: the exclusion only made sense while the
            // subscript refused divider writes outright, and leaving it in
            // place would let a recreate silently discard the position
            // preflightSetup had just seeded (#890).
            let autosaveName = statusItem.autosaveName as String
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                autosaveName,
                to: cached
            )
        }
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideSection

    /// The control item's window (`@Published`).
    @Published private(set) var window: NSWindow?

    /// The control item's frame (`@Published`).
    @Published private(set) var frame: CGRect?

    /// The control item's screen (`@Published`).
    @Published private(set) var screen: NSScreen?

    /// The control item's frame, if it is onscreen (`@Published`).
    @Published private(set) var onScreenFrame: CGRect?

    /// Whether the menu bar accepted this control item but is not rendering
    /// it — most often because macOS parked it in the notch dead zone
    /// (`@Published`).
    ///
    /// Derived from `NSWindow.occlusionState`, so unlike the image cache it
    /// needs no Screen Recording grant. See ``ControlItemOcclusion`` for why
    /// the underlying signal is debounced before it reaches this property.
    @Published private(set) var isOccluded = false

    /// The control item's identifier.
    let identifier: Identifier

    /// Lazy storage for the control item's underlying status item.
    private lazy var storage = StatusItemStorage(controlItem: self)

    /// Spacer items used to extend hidden/always-hidden width on ultra-wide displays.
    private var spacerItems = [NSStatusItem]()

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The control item's diagnostic logger.
    private nonisolated let diagLog = DiagLog(category: "ControlItem")

    /// Debounces the raw `occlusionState` readings behind ``isOccluded``.
    private var occlusionEvaluator = ControlItemOcclusion.Evaluator()

    /// When the displays were last reconfigured, used to discard the occlusion
    /// readings taken while the new layout is still settling.
    private var lastDisplayChange: Date?

    /// Tasks backing settings-observation reactions in `configureCancellables()`
    /// and `configureStatusItemCancellables()`. `GeneralSettings` and
    /// `AdvancedSettings` are `@Observable` (not Combine `ObservableObject`s),
    /// so their property changes are observed via the `Observations` async
    /// sequence instead of `$property` publishers.
    private var showIceIconObservationTask: Task<Void, Never>?
    private var iceIconObservationTask: Task<Void, Never>?
    private var sectionDividerStyleObservationTask: Task<Void, Never>?
    private var alwaysHiddenSectionObservationTask: Task<Void, Never>?

    /// Task observing `appState.isDraggingMenuBarItem` (wave 4), which is
    /// `@Observable` rather than a Combine `ObservableObject`, replacing the
    /// old `$isDraggingMenuBarItem.removeDuplicates().sink`.
    private var isDraggingMenuBarItemObservationTask: Task<Void, Never>?

    /// Fold: whether the drawer, or an item it revealed in the menu bar, is
    /// open. While true the chevron keeps the native menu-bar highlight and
    /// points up, so it reads as one shape with the revealed item's pill.
    private var isFoldEngaged = false
    private var latestFoldEngaged = false
    private var foldEngagedObservationTask: Task<Void, Never>?

    /// Fold: opens the drawer when the pointer rests on the chevron, whichever
    /// app is active. Re-arms only after the pointer leaves the chevron.
    private var foldHoverTask: Task<Void, Never>?
    private var foldHoverSince: Date?
    /// Where the pointer was when the current dwell started; moving away from it
    /// restarts the dwell, so sweeping past the icon never opens the drawer.
    private var foldHoverAnchor: NSPoint?
    private var foldHoverArmed = true
    private var foldHoverSuppressedUntil = Date.distantPast

    /// Fold: a hidden icon changed while the drawer was closed, so the
    /// menu-bar icon carries a dot until the drawer is next opened.
    private var foldHasAttention = false
    private var foldAttentionTask: Task<Void, Never>?
    private var foldAttentionPollTask: Task<Void, Never>?
    private var foldLoggedPoll = false
    private var foldSeenImages = [MenuBarItemTag: MenuBarItemImageCache.CapturedImage]()
    private var foldChangeTimes = [MenuBarItemTag: [Date]]()
    private var foldMutedTags = Set<MenuBarItemTag>()

    deinit {
        foldAttentionTask?.cancel()
        foldAttentionPollTask?.cancel()
        foldHoverTask?.cancel()
        foldEngagedObservationTask?.cancel()
        showIceIconObservationTask?.cancel()
        iceIconObservationTask?.cancel()
        sectionDividerStyleObservationTask?.cancel()
        alwaysHiddenSectionObservationTask?.cancel()
        isDraggingMenuBarItemObservationTask?.cancel()
    }

    /// Storage for observers whose subscriptions are bound to the specific
    /// `NSStatusItem` instance backing `storage`. Combine's KVO publishers
    /// latch onto object identity at subscription time, so these must be
    /// re-created (via `configureStatusItemCancellables()`) whenever
    /// `storage` — and therefore `statusItem` — is replaced by
    /// `recreateStatusItem()`. Kept separate from `cancellables` so a
    /// rebuild only tears down and re-subscribes this subset.
    private var statusItemCancellables = Set<AnyCancellable>()

    /// The control item's underlying status item.
    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    /// A horizontal constraint for the control item's content view.
    private var constraint: NSLayoutConstraint? {
        storage.constraint
    }

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        self.identifier = identifier
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            // Deduplicated: a same-value reassignment must not rewrite the
            // button and commit a status-item scene update — on macOS 26
            // every scene commit costs Core Animation fence ports (#933).
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &c)

        $window.removeNil()
            .map { $0.publisher(for: \.frame) }
            .switchToLatest()
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frame = frame
            }
            .store(in: &c)

        $window.removeNil()
            .map { $0.publisher(for: \.screen) }
            .switchToLatest()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        $screen.removeNil()
            .map { $0.publisher(for: \.frame) }
            .switchToLatest()
            .combineLatest($frame.removeNil())
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screenFrame, frame in
                guard let self else {
                    return
                }
                if screenFrame.intersects(frame) {
                    onScreenFrame = frame
                } else {
                    onScreenFrame = nil
                }
            }
            .store(in: &c)

        if let appState {
            // `appState` is now `@Observable` (wave 4), so it no longer has
            // an `$isDraggingMenuBarItem` publisher.
            isDraggingMenuBarItemObservationTask?.cancel()
            isDraggingMenuBarItemObservationTask = Task { [weak self, weak appState] in
                var previous: Bool?
                let changes = Observations { appState?.isDraggingMenuBarItem }
                for await isDragging in changes {
                    guard let self else { return }
                    guard let isDragging, isDragging != previous else { continue }
                    previous = isDragging
                    if isDragging {
                        updateStatusItem()
                    }
                }
            }

            if identifier == .visible {
                let generalSettings = appState.settings.general
                showIceIconObservationTask?.cancel()
                showIceIconObservationTask = Task { [weak self] in
                    let changes = Observations { generalSettings.showIceIcon }
                    for await shouldShow in changes {
                        guard let self else { return }
                        setIceIconDisplayed(shouldShow)
                    }
                }

                iceIconObservationTask?.cancel()
                iceIconObservationTask = Task { [weak self] in
                    let changes = Observations { (generalSettings.iceIcon, generalSettings.customIceIconIsTemplate) }
                    for await _ in changes {
                        guard let self else { return }
                        updateStatusItem()
                    }
                }
            }

            if isSectionDivider {
                let advancedSettings = appState.settings.advanced
                sectionDividerStyleObservationTask?.cancel()
                sectionDividerStyleObservationTask = Task { [weak self] in
                    let changes = Observations { advancedSettings.sectionDividerStyle }
                    for await _ in changes {
                        guard let self else { return }
                        updateStatusItem()
                    }
                }
            }
        }

        cancellables = c

        if let appState { configureFoldEngagedObservation(appState: appState) }

        configureStatusItemCancellables()
    }

    /// Configures the observers whose subscriptions are bound to the
    /// specific `NSStatusItem` instance currently backing `storage`. Called
    /// once from `configureCancellables()` at setup, and again from
    /// `recreateStatusItem()` after the underlying status item is rebuilt,
    /// since Combine's KVO publishers latch onto the object identity of the
    /// status item they were created from and would otherwise keep
    /// observing the now-detached old one.
    private func configureStatusItemCancellables() {
        var c = Set<AnyCancellable>()

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let menuBarManager = appState?.menuBarManager,
                    let section = menuBarManager.section(withName: sectionName),
                    let hotkey = section.hotkey
                else {
                    return
                }
                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &c)

        statusItem.publisher(for: \.button).removeNil()
            .map { $0.publisher(for: \.window) }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        if identifier == .alwaysHidden, let appState {
            let advancedSettings = appState.settings.advanced
            let reactToAlwaysHiddenSectionState: () -> Void = { [weak self] in
                guard let self else { return }
                if advancedSettings.enableAlwaysHiddenSection {
                    addToMenuBar()
                } else {
                    removeFromMenuBar()
                }
            }

            // Re-derive add/remove whenever isVisible changes (statusItem
            // KVO, still Combine) — mirrors the previous combineLatest's
            // re-trigger on the second element, even though only the first
            // (shouldEnable) was ever read from the emitted pair.
            statusItem.publisher(for: \.isVisible)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { _ in reactToAlwaysHiddenSectionState() }
                .store(in: &c)

            alwaysHiddenSectionObservationTask?.cancel()
            alwaysHiddenSectionObservationTask = Task {
                let changes = Observations { advancedSettings.enableAlwaysHiddenSection }
                for await _ in changes {
                    reactToAlwaysHiddenSectionState()
                }
            }
        }

        configureOcclusionObservers(storingIn: &c)

        statusItemCancellables = c
    }

    /// Wires up the permission-free occlusion signal behind ``isOccluded``.
    ///
    /// Subscriptions live alongside the rest of `statusItemCancellables`
    /// because they are bound to the current `NSStatusItem` — both the
    /// visibility publisher and the window whose occlusion is sampled belong
    /// to it, so `recreateStatusItem()` must re-subscribe them.
    private func configureOcclusionObservers(storingIn c: inout Set<AnyCancellable>) {
        let displayChanges = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .replace(with: ())

        // Record the reconfiguration first, so the samples that the same
        // notification triggers below are already inside the grace window.
        displayChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                lastDisplayChange = .now
                occlusionEvaluator.reset()
            }
            .store(in: &c)

        // A window that is already occluded posts nothing further once the new
        // layout settles, so the delayed leg re-samples after the grace window
        // closes rather than waiting for an event that may never arrive.
        let settledAfterDisplayChange = displayChanges
            .delay(
                for: .seconds(ControlItemOcclusion.displayChangeGrace + 0.1),
                scheduler: DispatchQueue.main
            )
            .eraseToAnyPublisher()

        let occlusionChanges = NotificationCenter.default
            .publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .compactMap { $0.object as? NSWindow }
            .filter { [weak self] window in
                window === self?.window
            }
            .replace(with: ())
            .eraseToAnyPublisher()

        let visibilityChanges = statusItem.publisher(for: \.isVisible)
            .removeDuplicates()
            .replace(with: ())
            .eraseToAnyPublisher()

        Publishers.MergeMany(occlusionChanges, visibilityChanges, settledAfterDisplayChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.sampleOcclusion()
            }
            .store(in: &c)
    }

    /// Takes one occlusion reading and publishes the verdict if it changed.
    private func sampleOcclusion() {
        guard let window else {
            // No window to read. Leave the last verdict alone unless it
            // claimed occlusion, which can no longer be substantiated.
            occlusionEvaluator.reset()
            if isOccluded {
                isOccluded = false
            }
            return
        }

        let sample = ControlItemOcclusion.Sample(
            isOccluded: !window.occlusionState.contains(.visible),
            isInMenuBar: statusItem.isVisible,
            secondsSinceDisplayChange: lastDisplayChange
                .map { Date.now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        )

        guard let verdict = occlusionEvaluator.evaluate(sample) else {
            return
        }

        isOccluded = verdict
        if verdict {
            diagLog.warning(
                "\(identifier.rawValue) is occluded — the menu bar accepted the status item but is not rendering it"
            )
        } else {
            diagLog.notice("\(identifier.rawValue) is no longer occluded")
        }
    }

    /// Rebuilds the control item's underlying `NSStatusItem` from scratch.
    ///
    /// Used as a bounded recovery step when `ControlItemPair` lookup keeps
    /// failing across multiple independently triggered cache cycles (#754),
    /// or when a confirmed collapsed divider must discard its stale position.
    /// a state that means the existing status item's `windowNumber` no
    /// longer matches any enumerated CG window ID, which is otherwise
    /// terminal since `storage` is normally created once and never
    /// recreated.
    ///
    /// `storage.dispose()` removes the old status item — and caches its
    /// `autosaveName` position — *before* a fresh `StatusItemStorage` is
    /// constructed at that same `autosaveName`, so AppKit restores the
    /// position the old item cached. This ordering matters: if the new
    /// storage were created first, the two `NSStatusItem`s would briefly
    /// share one autosaveName, and the old item's removal (deferred to its
    /// `deinit`) would run after the new item already restored its
    /// position, overwriting the autosave slot with the old item's own
    /// possibly-stale position and clobbering what the new item just set.
    /// The `window`-chain and other status-item-bound observers are
    /// re-subscribed against the new instance since Combine's KVO
    /// publishers don't follow object identity changes on their own.
    @MainActor
    func recreateStatusItem(preferredPosition: CGFloat? = nil) {
        storage.dispose()
        if let preferredPosition {
            ControlItemDefaults.setIgnoringSectionDividerGuard(
                .preferredPosition,
                identifier.rawValue,
                to: preferredPosition
            )
        }
        storage = StatusItemStorage(controlItem: self)
        configureStatusItemCancellables()
        updateStatusItem()
    }

    /// Fold: tracks the drawer and temporarily revealed items so the chevron
    /// stays visually joined to whatever it opened.
    private func configureFoldEngagedObservation(appState: AppState) {
        guard identifier == .visible, Constants.bundleIdentifier == "com.samdeherdt.fold" else { return }
        foldHoverTask?.cancel()
        foldHoverTask = Task { @MainActor [weak self] in
            var ticks = 0
            let started = Date.now
            while !Task.isCancelled {
                guard let self else { return }
                ticks += 1
                if ticks == 100 {
                    let average = Date.now.timeIntervalSince(started) / 100 * 1000
                    diagLog.notice("Fold hover watch: average tick \(Int(average)) ms (target 80)")
                }
                checkFoldChevronHover()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        diagLog.notice("Fold chevron hover watch started")

        foldAttentionTask?.cancel()
        foldAttentionTask = Task { @MainActor [weak self, imageCache = appState.imageCache] in
            let changes = Observations { imageCache.images }
            for await images in changes {
                guard let self else { return }
                noteHiddenImages(images)
            }
        }
        // Thaw only captures icons while something shows them. Fold looks at
        // the hidden ones every few seconds so a change can raise the dot.
        foldAttentionPollTask?.cancel()
        foldAttentionPollTask = Task { @MainActor [weak self, imageCache = appState.imageCache] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard let self else { return }
                guard FoldKey.attentionDotEnabled else {
                    setFoldBadgeTags([])
                    continue
                }
                // Apps with a Dock badge (unread count) among the hidden icons.
                let badged = await Task.detached { FoldDockBadges.badgedAppURLs() }.value
                if !foldLoggedPoll {
                    diagLog.notice("Fold attention: \(badged.count) app(s) have a Dock badge: \(badged.map(\.lastPathComponent).sorted().joined(separator: ", "))")
                }
                var badgeTags = Set<MenuBarItemTag>()
                if !badged.isEmpty {
                    for item in appState.itemManager.itemCache.managedItems(for: .hidden) {
                        guard let url = NSRunningApplication(processIdentifier: item.sourcePID ?? item.ownerPID)?.bundleURL else { continue }
                        if badged.contains(url.standardizedFileURL) { badgeTags.insert(item.tag) }
                    }
                }
                setFoldBadgeTags(badgeTags)
                guard !isFoldEngaged, !appState.itemManager.lastMoveOperationOccurred(within: .seconds(3)) else { continue }
                await imageCache.foldRefreshHiddenImages()
                if !foldLoggedPoll {
                    foldLoggedPoll = true
                    let tags = appState.itemManager.itemCache.managedItems(for: .hidden).map(\.tag)
                    let cached = tags.filter { imageCache.images[$0] != nil }.count
                    diagLog.notice("Fold attention: background check running, \(cached) of \(tags.count) hidden icons captured")
                }
            }
        }

        foldEngagedObservationTask?.cancel()
        foldEngagedObservationTask = Task { @MainActor [weak self, navigationState = appState.navigationState, itemManager = appState.itemManager] in
            let changes = Observations {
                navigationState.isIceBarPresented || !itemManager.temporarilyShownItemContexts.isEmpty
            }
            for await engaged in changes {
                guard let self else { return }
                latestFoldEngaged = engaged
                if engaged {
                    setFoldEngaged(true)
                } else {
                    // The drawer closes just before a clicked item is
                    // revealed; wait so the highlight doesn't flicker off.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self, !latestFoldEngaged else { return }
                        setFoldEngaged(false)
                    }
                }
            }
        }
    }

    /// Fold's right-click menu: open/search first, quick Motion and Look
    /// switches, then Arrange, Settings and Quit.
    private func createFoldMenu(with appState: AppState) -> NSMenu {
        let menu = NSMenu(title: "Fold")

        func item(_ title: String, _ symbol: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }
        func shortcut(_ item: NSMenuItem, for action: HotkeyAction) {
            if let combination = appState.settings.hotkeys.hotkey(withAction: action)?.keyCombination {
                item.keyEquivalent = combination.key.keyEquivalent
                item.keyEquivalentModifierMask = combination.modifiers.nsEventFlags
            }
        }

        let open = item("Open Fold", "chevron.down.circle", #selector(foldOpenDrawer))
        shortcut(open, for: .toggleHiddenSection)
        menu.addItem(open)
        let search = item("Search Icons…", "magnifyingglass", #selector(foldSearchIcons))
        shortcut(search, for: .searchMenuBarItems)
        menu.addItem(search)
        menu.addItem(.separator())

        let currentMotion = FoldMotion.current
        let motionMenu = NSMenu(title: "Motion")
        for motion in FoldMotion.allCases {
            let entry = item(motion.title, motion.symbol, #selector(foldSetMotion(_:)))
            entry.representedObject = motion.rawValue
            entry.state = motion == currentMotion ? .on : .off
            motionMenu.addItem(entry)
        }
        let motionItem = NSMenuItem(title: "Motion", action: nil, keyEquivalent: "")
        motionItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        motionItem.submenu = motionMenu
        menu.addItem(motionItem)

        let currentLook = FoldLook.current
        let lookMenu = NSMenu(title: "Look")
        for look in FoldLook.allCases {
            let entry = NSMenuItem(title: look.title, action: #selector(foldSetLook(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = look.rawValue
            entry.state = look == currentLook ? .on : .off
            lookMenu.addItem(entry)
        }
        let lookItem = NSMenuItem(title: "Look", action: nil, keyEquivalent: "")
        lookItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        lookItem.submenu = lookMenu
        menu.addItem(lookItem)

        let hover = item("Open on Hover", "cursorarrow.motionlines", #selector(foldToggleHover))
        hover.state = appState.settings.general.showOnHover ? .on : .off
        menu.addItem(hover)
        menu.addItem(.separator())

        menu.addItem(item("Arrange Icons…", "square.grid.3x1.below.line.grid.1x2", #selector(foldArrange)))
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(UpdatesManager.checkForUpdates), keyEquivalent: "")
        updates.target = appState.updatesManager
        updates.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(updates)
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettingsWindow), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Fold", action: #selector(NSApp.terminate), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// A click that landed on the drawer's strip over this icon instead of on
    /// the icon itself. The drawer forwards it here so it always works.
    func foldHandleForwardedClick(isRightClick: Bool) {
        if isRightClick {
            foldHoverArmed = false
            foldHoverSuppressedUntil = .now.addingTimeInterval(1)
            showMenu()
        } else {
            foldHoverArmed = false
            appState?.menuBarManager.iceBarPanel.hide()
        }
    }

    @objc private func foldOpenDrawer() {
        appState?.menuBarManager.section(withName: .hidden)?.show()
    }

    @objc private func foldSetMotion(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: FoldKey.motion)
    }

    @objc private func foldSetLook(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: FoldKey.look)
    }

    @objc private func foldToggleHover() {
        guard let general = appState?.settings.general else { return }
        general.showOnHover.toggle()
    }

    @objc private func foldArrange() {
        UserDefaults.standard.set(true, forKey: "FoldOpenArrangeOnce")
        NotificationCenter.default.post(name: .foldShowArrange, object: nil)
        NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: self)
    }

    @objc private func foldSearchIcons() {
        guard let appState else { return }
        HotkeyAction.searchMenuBarItems.perform(appState: appState)
    }

    private func setFoldBadgeTags(_ tags: Set<MenuBarItemTag>) {
        guard FoldAttention.shared.badgeTags != tags else { return }
        FoldAttention.shared.badgeTags = tags
        diagLog.notice("Fold attention: \(tags.count) hidden icon(s) have a Dock badge")
        updateStatusItem()
    }

    /// Compares the hidden icons' images with the last ones seen and raises
    /// the attention dot when one of them really changed.
    private func noteHiddenImages(_ images: [MenuBarItemTag: MenuBarItemImageCache.CapturedImage]) {
        guard let appState else { return }
        let hidden = appState.itemManager.itemCache.managedItems(for: .hidden).map(\.tag)
        var changed = [MenuBarItemTag]()
        for tag in hidden {
            guard let image = images[tag] else { continue }
            if let seen = foldSeenImages[tag], !MenuBarItemImageCache.CapturedImage.isVisuallyEqual(seen, image) {
                changed.append(tag)
            }
            foldSeenImages[tag] = image
        }
        guard !changed.isEmpty else { return }
        // Most icons changing together is the menu bar restyling (light/dark,
        // wallpaper), not an app asking for attention.
        guard changed.count * 2 <= max(hidden.count, 2) else { return }

        let now = Date.now
        var attention = false
        for tag in changed where !foldMutedTags.contains(tag) {
            let recent = (foldChangeTimes[tag] ?? []).filter { now.timeIntervalSince($0) < 120 } + [now]
            foldChangeTimes[tag] = recent
            if recent.count >= 3 {
                // An icon that keeps changing (a meter, a clock) isn't news.
                foldMutedTags.insert(tag)
                diagLog.notice("Fold attention: muting \(tag.description), it changes constantly")
            } else {
                attention = true
                if !isFoldEngaged { FoldAttention.shared.tags.insert(tag) }
            }
        }
        guard attention, FoldKey.attentionDotEnabled, !isFoldEngaged, !foldHasAttention else { return }
        foldHasAttention = true
        diagLog.notice("Fold attention: a hidden icon changed")
        updateStatusItem()
    }

    /// The icon with a small dot at its top-right corner, in the icon's own
    /// (template) colour.
    private func foldImageWithDot(_ image: NSImage) -> NSImage {
        let dot: CGFloat = 5
        let size = NSSize(width: image.size.width + dot, height: image.size.height)
        let result = NSImage(size: size, flipped: false) { _ in
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width - dot, y: size.height - dot - 0.5, width: dot, height: dot)).fill()
            return true
        }
        result.isTemplate = true
        return result
    }

    private func checkFoldChevronHover() {
        let pointer = FoldPointer.location
        guard
            let appState,
            appState.settings.general.showOnHover,
            let frame = window?.frame,
            let section = appState.menuBarManager.section(withName: .hidden)
        else {
            foldHoverSince = nil
            return
        }
        // The icon also appears in other displays' menu bars; hovering any
        // copy opens the drawer (on that display). Only the icon itself counts:
        // the status-item window spans the full menu-bar height, so a pointer
        // pushed against the top of the screen or sliding along the bar was
        // "on the icon" — trim the edges off.
        let hotArea = { (rect: CGRect) in rect.insetBy(dx: 3, dy: min(4, rect.height * 0.18)) }
        let overIcon = hotArea(frame).contains(pointer) || NSScreen.screens.contains { screen in
            FoldChevron.frame(of: window, on: screen).map(hotArea)?.contains(pointer) == true
        }
        guard overIcon else {
            foldHoverArmed = true
            foldHoverSince = nil
            foldHoverAnchor = nil
            return
        }
        guard foldHoverArmed, !isFoldEngaged, NSEvent.pressedMouseButtons == 0, Date.now > foldHoverSuppressedUntil else {
            foldHoverSince = nil
            return
        }
        // The pointer has to rest: any move of more than 3 pt restarts the wait.
        if let anchor = foldHoverAnchor, hypot(pointer.x - anchor.x, pointer.y - anchor.y) > 3 {
            foldHoverSince = .now
            foldHoverAnchor = pointer
            return
        }
        if let since = foldHoverSince {
            if Date.now.timeIntervalSince(since) > FoldKey.hoverDelaySeconds {
                foldHoverAnchor = nil
                foldHoverArmed = false
                foldHoverSince = nil
                diagLog.notice("Fold hover over chevron: opening drawer")
                section.show()
            }
        } else {
            foldHoverSince = .now
            foldHoverAnchor = pointer
        }
    }

    private func setFoldEngaged(_ engaged: Bool) {
        if engaged {
            // Opened by click or hover: wait for the pointer to leave before
            // hover may open it again, so closing it doesn't bounce back open.
            foldHoverArmed = false
            // Opening the drawer is how you see what changed.
            foldHasAttention = false
        }
        guard engaged != isFoldEngaged else { return }
        isFoldEngaged = engaged
        // The per-icon dots stay while the drawer is open and go when it closes.
        if !engaged { FoldAttention.shared.tags.removeAll() }
        updateStatusItem()
        statusItem.button?.highlight(engaged)
        guard engaged else { return }
        // AppKit clears a status button's highlight when its own click
        // tracking ends, which can land after this change. Reassert it once
        // the click has finished.
        for delay in [0.15, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, isFoldEngaged else { return }
                statusItem.button?.highlight(true)
            }
        }
    }

    /// Updates the appearance of the status item using the current hiding state.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        button.title = ""
        button.image = nil

        switch identifier {
        case .visible:
            if !appState.settings.general.showIceIcon {
                hideIceIconCompletely()
                return
            }
            updateStatusItemVisibility(true)
            button.appearsDisabled = false

            let icon = appState.settings.general.iceIcon

            // We can usually just create the image directly from the icon.
            var image = switch (state, isFoldEngaged) {
            case (.showSection, _), (_, true): icon.visible.nsImage(for: appState)
            case (.hideSection, false): icon.hidden.nsImage(for: appState)
            }

            if
                case .custom = icon.name,
                let originalImage = image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                image = originalImage.resized(to: newSize)
            }

            button.image = (foldHasAttention || !FoldAttention.shared.badgeTags.isEmpty) && !isFoldEngaged ? image.map(foldImageWithDot) : image
            if isFoldEngaged {
                button.highlight(true)
            }
        case .hidden, .alwaysHidden:
            switch state {
            case .showSection:
                button.isEnabled = true
                button.alphaValue = 1
                switch appState.settings.advanced.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false)
                    button.appearsDisabled = true
                    button.isHighlighted = false

                    if appState.isDraggingMenuBarItem, appState.settings.advanced.showAllSectionsOnUserDrag {
                        // We still want a subtle marker between sections.
                        button.title = "|"
                    }
                case .chevron:
                    updateStatusItemVisibility(true)
                    button.appearsDisabled = false

                    if identifier != .visible {
                        button.image = ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                    }
                }
            case .hideSection:
                updateStatusItemVisibility(true)
                button.appearsDisabled = true
                button.isHighlighted = false
                // Match the spacer item pattern: invisible and non-interactive.
                // The constraint stays active so items are pushed off-screen.
                button.isEnabled = false
                button.alphaValue = 0
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden control items must always be present in
    /// the menu bar, as we use their positions to determine the items in each
    /// section. Setting `statusItem.isVisible` to `false` completely removes
    /// the item. Instead, we toggle the width constraint on the item's content
    /// view, update the item's length, then adjust the content size of the
    /// item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        if isVisible {
            constraint?.isActive = true
            statusItem.length = identifier.length(for: state)

            let shouldUseSpacers = (identifier == .hidden || identifier == .alwaysHidden) && state == .hideSection
            updateSpacerItems(forHiddenState: shouldUseSpacers)
        } else {
            updateSpacerItems(forHiddenState: false)
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            constraint?.isActive = false
            statusItem.length = shouldShow ? 3 : 0

            if let window {
                let size = withMutableCopy(of: window.frame.size) { $0.width = shouldShow ? 3 : 1 }
                window.setContentSize(size)
            }
        }
    }

    /// Adds or removes spacer items to extend the hidden/always-hidden section width.
    private func updateSpacerItems(forHiddenState isHiddenState: Bool) {
        guard identifier != .visible else {
            removeSpacerItems()
            return
        }

        guard isHiddenState else {
            removeSpacerItems()
            return
        }

        let needed = requiredSpacerCount()

        if spacerItems.count != needed {
            removeSpacerItems()

            spacerItems = (0 ..< needed).map { index in
                let item = NSStatusBar.system.statusItem(withLength: 0)
                item.autosaveName = "\(identifier.rawValue).Spacer.\(index)"

                if let button = item.button {
                    button.title = ""
                    button.image = nil
                    button.isEnabled = false
                    button.appearsDisabled = true
                    button.alphaValue = 0
                }

                return item
            }
        }

        spacerItems.forEach { $0.length = Lengths.expanded }
    }

    /// Removes spacer items from the status bar.
    private func removeSpacerItems() {
        for item in spacerItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        spacerItems.removeAll()
    }

    /// Calculates how many spacer items are needed to push hidden items off ultra-wide displays.
    private func requiredSpacerCount() -> Int {
        let maxScreenWidth = NSScreen.screens.map(\.frame.width).max() ?? 6000
        guard maxScreenWidth > 5120 else { return 0 }

        let desiredWidth = maxScreenWidth * 3
        let remaining = desiredWidth - Lengths.expanded
        guard remaining > 0 else { return 0 }
        return Int(ceil(remaining / Lengths.expanded))
    }

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // Setting `statusItem.isVisible` to `false` has the unwanted side
        // effect of deleting the preferred position. Cache and restore it.
        //
        // Dividers used to be excluded here, which was consistent while the
        // subscript refused to write them anyway. Now that seeding has a path
        // through that guard, skipping the restore would undo it: hiding the
        // icon would delete the position seeding had just established and
        // leave the divider free to be placed on top of the other one (#890).
        let autosaveName = statusItem.autosaveName as String
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults.setIgnoringSectionDividerGuard(
            .preferredPosition,
            autosaveName,
            to: cached
        )
    }

    /// Updates the status item's visibility without clearing its preferred position.
    private func setIceIconDisplayed(_ shouldShow: Bool) {
        statusItem.isVisible = true
        if shouldShow {
            updateStatusItem()
            return
        }

        hideIceIconCompletely()
    }

    /// Hides the Ice icon without removing the status item or losing autosave data.
    private func hideIceIconCompletely() {
        constraint?.isActive = false
        statusItem.length = 0

        if let window {
            let size = withMutableCopy(of: window.frame.size) { $0.width = 1 }
            window.setContentSize(size)
        }
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard
            let appState,
            let event = NSApp.currentEvent
        else {
            return
        }
        let menuBarManager = appState.menuBarManager

        switch event.type {
        case .leftMouseDown:
            // Suppress phantom left clicks delivered to the status item
            // button while no menu bar items are rendered on-screen for the
            // active space. This catches fast top-of-screen clicks during
            // the menu bar reveal sequence under a fullscreen app, which
            // would otherwise expand the hidden section offscreen.
            // NSApp.currentSystemPresentationOptions is per-app and does
            // not reflect another app's fullscreen state, so the items-list
            // signal is used directly. Scoped to left clicks so the
            // right-click menu below keeps working when the menu bar
            // transiently has no item windows on the active space (#1012).
            let screenForCheck = window?.screen ?? NSScreen.main
            if let screen = screenForCheck, !screen.isSystemMenuBarVisible() {
                diagLog.notice("Control action ignored: system menu bar not visible")
                return
            }

            // Capture modifier flags from the event to ensure we have the state
            // at the time of the click, not when the Task executes.
            let modifierFlags = event.modifierFlags

            // Running this from a Task seems to improve the visual
            // responsiveness of the status item's button.
            Task { [appState] in
                if
                    appState.settings.advanced.useDoubleClickToShowAlwaysHiddenSection,
                    event.clickCount > 1,
                    identifier == .visible,
                    let alwaysHidden = menuBarManager.section(withName: .alwaysHidden),
                    alwaysHidden.isEnabled
                {
                    alwaysHidden.show()
                    return
                }

                if modifierFlags.contains(.control) {
                    showMenu()
                    return
                }

                if modifierFlags.contains(.option) {
                    // Option-click: only toggle always-hidden if enabled.
                    if
                        appState.settings.advanced.useOptionClickToShowAlwaysHiddenSection,
                        let section = menuBarManager.section(withName: .alwaysHidden),
                        section.isEnabled
                    {
                        section.toggle()
                    }
                    return
                }

                if
                    let section = menuBarManager.section(withName: sectionName),
                    section.isEnabled
                {
                    diagLog.notice("Control action: toggle \(sectionName), hidden=\(section.isHidden)")
                    section.toggle()
                } else {
                    diagLog.notice("Control action ignored: section unavailable or disabled")
                }
            }
        case .rightMouseUp:
            // Don't let hover pop the drawer open around a right-click.
            foldHoverArmed = false
            foldHoverSuppressedUntil = .now.addingTimeInterval(1)
            showMenu()
        default:
            return
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: Bundle.main.displayName)

        if Constants.bundleIdentifier == "com.samdeherdt.fold" {
            return createFoldMenu(with: appState)
        }

        let settingsItem = NSMenuItem(
            title: String(localized: "\(Constants.displayName) Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: String(localized: "Search Menu Bar Items"),
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        searchItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        // Add items to toggle the hidden and always-hidden sections.
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.isEnabled
            else {
                continue
            }
            let sectionTitle: String
            let iconName: String
            switch (section.isHidden, name) {
            case (true, .hidden):
                sectionTitle = String(localized: "Show Hidden Section")
                iconName = "eye"
            case (false, .hidden):
                sectionTitle = String(localized: "Hide Hidden Section")
                iconName = "eye.slash"
            case (true, .alwaysHidden):
                sectionTitle = String(localized: "Show Always-Hidden Section")
                iconName = "eye"
            case (false, .alwaysHidden):
                sectionTitle = String(localized: "Hide Always-Hidden Section")
                iconName = "eye.slash"
            default:
                sectionTitle = String(localized: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Section")
                iconName = section.isHidden ? "eye" : "eye.slash"
            }
            let item = NSMenuItem(
                title: sectionTitle,
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: sectionTitle)
            if
                let hotkey = section.hotkey,
                let keyCombination = hotkey.keyCombination
            {
                item.keyEquivalent = keyCombination.key.keyEquivalent
                item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
            }
            item.target = self
            item.representedObject = section
            menu.addItem(item)
        }

        // Profiles submenu.
        let profileManager = appState.profileManager
        if !profileManager.profiles.isEmpty {
            menu.addItem(.separator())

            let profilesItem = NSMenuItem(
                title: String(localized: "Profiles"),
                action: nil,
                keyEquivalent: ""
            )
            profilesItem.image = NSImage(
                systemSymbolName: "person.crop.rectangle.stack",
                accessibilityDescription: "Profiles"
            )
            let profilesMenu = NSMenu()
            for meta in profileManager.profiles {
                let item = NSMenuItem(
                    title: meta.name,
                    action: #selector(applyProfileFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = meta.id
                if meta.id == profileManager.activeProfileID {
                    item.state = .on
                }
                profilesMenu.addItem(item)
            }
            profilesItem.submenu = profilesMenu
            menu.addItem(profilesItem)
        }

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        let supportItem = NSMenuItem(
            title: String(localized: "Support \(Constants.displayName)…"),
            action: #selector(openDonateURL),
            keyEquivalent: ""
        )
        supportItem.image = NSImage(systemSymbolName: "heart.circle.fill", accessibilityDescription: "Support")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit \(Constants.displayName)"),
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)

        let restartItem = NSMenuItem(
            title: String(localized: "Restart \(Constants.displayName)"),
            action: #selector(restartFromMenu),
            keyEquivalent: "q"
        )
        restartItem.keyEquivalentModifierMask = [.command, .option]
        restartItem.isAlternate = true
        restartItem.target = self
        restartItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart")
        menu.addItem(restartItem)

        return menu
    }

    @objc private func restartFromMenu() {
        appState?.restartSelf()
    }

    /// Shows the control item's menu.
    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    /// Opens the menu bar search panel.
    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    /// Applies the profile selected from the context menu.
    @objc private func applyProfileFromMenu(_ menuItem: NSMenuItem) {
        guard
            let profileID = menuItem.representedObject as? UUID,
            let appState,
            appState.profileManager.layoutTask == nil,
            profileID != appState.profileManager.activeProfileID
        else { return }
        let profileManager = appState.profileManager
        Task {
            guard let profile = try? profileManager.loadProfile(id: profileID) else { return }
            let previousID = profileManager.activeProfileID
            profileManager.activeProfileID = profileID
            profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
        }
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }

    /// Opens the donate URL.
    @objc private func openDonateURL() {
        NSWorkspace.shared.open(Constants.donateURL)
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
nonisolated enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return Defaults.store.object(forKey: stringKey) as? Value
        }
        set {
            // Prevent saving preferred position for section divider chevrons
            if key.isPreferredPosition, isSectionDivider(autosaveName: autosaveName) {
                return
            }
            let stringKey = key.stringKey(for: autosaveName)
            return Defaults.store.set(newValue, forKey: stringKey)
        }
    }

    /// Writes a value without the section-divider guard above.
    ///
    /// The guard was added to stop a user from breaking their menu bar by
    /// dragging a chevron (`ff7517f7`, "Prevents users from breaking menu bar
    /// by moving chevrons"). It cannot do that: AppKit writes
    /// `NSStatusItem Preferred Position <autosaveName>` itself when it places
    /// an item, and that write never passes through this type. So the guard
    /// only ever blocked Thaw's own writes — including the seeding that
    /// `preflightSetup(for:)` and `resetChevronPositions()` exist to perform,
    /// which the same commit introduced and silently disabled (#890).
    ///
    /// With no stored position, both dividers can be placed at the same X,
    /// which collapses the span between them to zero width.
    ///
    /// Kept separate from the subscript rather than deleting the guard, so
    /// only these two deliberate seeding paths bypass it and any future
    /// caller still gets the original, conservative behavior.
    static func setIgnoringSectionDividerGuard<Value>(
        _ key: Key<Value>,
        _ autosaveName: String,
        to newValue: Value?
    ) {
        Defaults.store.set(newValue, forKey: key.stringKey(for: autosaveName))
    }

    /// Returns whether the given autosave name belongs to a section divider.
    static func isSectionDivider(autosaveName: String) -> Bool {
        autosaveName == ControlItem.Identifier.hidden.rawValue ||
            autosaveName == ControlItem.Identifier.alwaysHidden.rawValue
    }

    /// Migrates the given control item defaults key from an old
    /// autosave name to a new autosave name.
    static func migrate(key: Key<some Any>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Performs some initial required setup work before the
    /// creation of a control item.
    static func preflightSetup(for identifier: ControlItem.Identifier) {
        let autosaveName = identifier.rawValue

        // Visible and hidden control items should be added before
        // existing items in the status bar.
        //
        // Seed only when nothing is stored. A second block used to follow
        // this one and re-stamp the hidden divider to 1 on every call,
        // regardless of where the user had it. That was inert from ff7517f7
        // until a1e566d4 routed divider seeding around the subscript guard
        // (#890), which woke it up: `StatusItemStorage.init` runs preflight
        // on every launch and every `recreateStatusItem()`, so a populated
        // bar had the hidden divider yanked back beside the visible one and
        // the following save persisted the collapsed span (#895).
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults.setIgnoringSectionDividerGuard(.preferredPosition, autosaveName, to: 1)
            case .alwaysHidden:
                break
            }
        }

        // The control item should be visible by default. We change
        // this after finishing setup, if needed.
        if ControlItemDefaults[.visible, autosaveName] == nil {
            ControlItemDefaults[.visible, autosaveName] = true
        }
        if ControlItemDefaults[.visibleCC, autosaveName] == nil {
            ControlItemDefaults[.visibleCC, autosaveName] = true
        }
    }

    /// Resets chevron section divider positions to their defaults.
    static func resetChevronPositions() {
        ControlItemDefaults.setIgnoringSectionDividerGuard(
            .preferredPosition,
            ControlItem.Identifier.hidden.rawValue,
            to: 1
        )
        // Always-hidden position is handled dynamically
    }
}

// MARK: - ControlItemDefaults.Key

nonisolated extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        /// The raw value of the key.
        let rawValue: String

        /// Whether this key represents a preferred position.
        var isPreferredPosition: Bool {
            rawValue == "Preferred Position"
        }

        /// Returns the full string key for the given autosave name.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>

nonisolated extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>

nonisolated extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
