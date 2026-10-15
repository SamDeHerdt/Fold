//
//  FoldSettingsView.swift
//  Fold
//
//  Licensed under the GNU GPLv3
//

import LaunchAtLogin
import SwiftUI

extension Notification.Name {
    /// Posted by the menu-bar right-click menu to open settings on Arrange.
    static let foldShowArrange = Notification.Name("FoldShowArrange")
}

/// The settings window's sections, shown as tabs under the pinned preview.
enum FoldSettingsTab: String, CaseIterable, Identifiable {
    case look, motion, icon, behaviour, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .look: "Look"
        case .motion: "Motion"
        case .icon: "Icon"
        case .behaviour: "Behaviour"
        case .shortcuts: "Shortcuts"
        }
    }
}

/// Fold's settings: a live preview pinned on top that replays on every change,
/// then one compact tab per topic.
struct FoldSettingsContent: View {
    let appState: AppState
    @Bindable var general: GeneralSettings
    @AppStorage(FoldKey.appearance) private var appearance = "dark"
    @AppStorage(FoldKey.glass) private var glass = "system"
    @AppStorage(FoldKey.tint) private var tint = ""
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.maxWidth) private var maxWidth = 0.0
    @AppStorage(FoldKey.motion) private var motion = FoldMotion.liquid.rawValue
    @AppStorage(FoldKey.hoverDelay) private var hoverDelay = 0.4
    @AppStorage(FoldKey.liveIcons) private var liveIcons = true
    @AppStorage(FoldKey.iconSpacing) private var iconSpacing = 0.0
    @AppStorage(FoldKey.iconScale) private var iconScale = 1.0
    @AppStorage(FoldKey.attentionDot) private var attentionDot = true
    @AppStorage(FoldKey.maxRows) private var maxRows = 8
    @AppStorage(FoldKey.motionSpeed) private var motionSpeed = 1.0
    @AppStorage(FoldKey.columnNames) private var columnNames = false
    @AppStorage("FoldSettingsTabV1") private var tab = FoldSettingsTab.look
    @State private var isArranging = false
    @State private var window: NSWindow?
    @State private var replay = 0

    private static let compactSize = NSSize(width: 560, height: 660)
    private static let arrangeSize = NSSize(width: 680, height: 490)

    private var screenWidth: CGFloat {
        NSScreen.main?.frame.width ?? 1512
    }

    private var screenCap: CGFloat {
        FoldWidth.screenCap(for: screenWidth)
    }

    /// Anything that changes how the drawer looks or moves replays the preview.
    private var previewSignature: String {
        "\(motion)|\(look)|\(glass)|\(tint)|\(appearance)|\(maxWidth)|\(iconSpacing)|\(iconScale)|\(arrangementBinding.wrappedValue.rawValue)|\(gridColumnsBinding.wrappedValue)|\(maxRows)|\(columnNames)|\(positionBinding.wrappedValue.rawValue)|\(attentionDot)|\((motionSpeed * 10).rounded())|\(general.iceIcon.name.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isArranging {
                MenuBarLayoutSettingsPane(itemManager: appState.itemManager, advancedSettings: appState.settings.advanced)
                    .frame(width: Self.arrangeSize.width, height: Self.arrangeSize.height - 60)
                HStack {
                    Button("Back") { isArranging = false }
                    Spacer()
                }.padding(16)
            } else {
                FoldPreview(
                    appState: appState,
                    icon: general.iceIcon,
                    cap: FoldWidth.cap(stored: maxWidth, screenWidth: screenWidth),
                    spacing: iconSpacing,
                    iconScale: iconScale,
                    arrangement: arrangementBinding.wrappedValue,
                    columns: gridColumnsBinding.wrappedValue,
                    maxRows: maxRows,
                    showsNames: columnNames,
                    position: positionBinding.wrappedValue,
                    showsDot: attentionDot,
                    replay: replay
                ) {
                    replay += 1
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Picker("Section", selection: $tab) {
                    ForEach(FoldSettingsTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Form {
                    switch tab {
                    case .look: lookTab
                    case .motion: motionTab
                    case .icon: iconTab
                    case .behaviour: behaviourTab
                    case .shortcuts: shortcutsTab
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

                HStack {
                    Button("Arrange icons…") { isArranging = true }
                    Button("Search icons…") {
                        HotkeyAction.searchMenuBarItems.perform(appState: appState)
                    }
                    Spacer()
                    Button("Open Fold") { appState.menuBarManager.section(withName: .hidden)?.show() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .frame(
            width: isArranging ? Self.arrangeSize.width : Self.compactSize.width,
            height: isArranging ? Self.arrangeSize.height : Self.compactSize.height
        )
        .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
        .navigationTitle("Fold")
        .onWindowChange(update: $window)
        .onChange(of: window) {
            // A restored window keeps its old saved size; match the content.
            Task { @MainActor in
                window?.setContentSize(isArranging ? Self.arrangeSize : Self.compactSize)
            }
        }
        .onChange(of: isArranging) {
            // Resize the host as well as the SwiftUI content. Otherwise the
            // arrangement rows can remain clipped by the compact window.
            Task { @MainActor in
                window?.setContentSize(isArranging ? Self.arrangeSize : Self.compactSize)
            }
        }
        .onChange(of: previewSignature) { replay += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .foldShowArrange)) { _ in
            isArranging = true
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "FoldOpenArrangeOnce") {
                UserDefaults.standard.set(false, forKey: "FoldOpenArrangeOnce")
                isArranging = true
            }
        }
    }

    /// Colour for the Accent look and coloured glass: presets, any colour
    /// from the system picker, or the system accent.
    private var tintRow: some View {
        LabeledContent("Colour") {
            HStack(spacing: 7) {
                Button {
                    tint = ""
                } label: {
                    Text("Auto")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.accentColor.opacity(tint.isEmpty ? 0.9 : 0.25), in: Capsule())
                        .foregroundStyle(tint.isEmpty ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help("Follow the system accent colour")
                ForEach(FoldTint.presets, id: \.self) { hex in
                    Button {
                        tint = hex
                    } label: {
                        Circle()
                            .fill(FoldTint.color(hex))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(tint == hex ? 0.9 : 0.15), lineWidth: tint == hex ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
                ColorPicker("Custom colour", selection: Binding(
                    get: { FoldTint.color(tint) },
                    set: { tint = FoldTint.hex($0) }
                ), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private var lookTab: some View {
        Section("Style") {
            FoldChoiceGrid(
                options: FoldLook.allCases,
                selection: $look,
                columns: 4,
                title: \.title,
                tag: \.rawValue
            ) { option in
                FoldLookSwatch(look: option)
            }
            if look == FoldLook.glass.rawValue {
                Picker("Glass", selection: $glass) {
                    Text("System").tag("system")
                    Text("Clear").tag("clear")
                    Text("Tinted").tag("tinted")
                    Text("Colour").tag("color")
                }.pickerStyle(.segmented)
            }
            if look == FoldLook.accent.rawValue || (look == FoldLook.glass.rawValue && glass == "color") {
                tintRow
            }
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
        }
        Section {
            Picker("Arrangement", selection: arrangementBinding) {
                Text("Row").tag(IceBarLayout.horizontal)
                Text("Grid").tag(IceBarLayout.grid)
                Text("Column").tag(IceBarLayout.vertical)
            }.pickerStyle(.segmented)
            if arrangementBinding.wrappedValue == .grid {
                Stepper(value: gridColumnsBinding, in: 2 ... 12) {
                    LabeledContent("Icons per row") {
                        Text("\(gridColumnsBinding.wrappedValue)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $maxRows, in: 1 ... 12) {
                    LabeledContent("Rows shown") {
                        Text("\(maxRows)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if arrangementBinding.wrappedValue == .vertical {
                Toggle("Show names", isOn: $columnNames)
                Stepper(value: $maxRows, in: 2 ... 20) {
                    LabeledContent("Icons shown") {
                        Text("\(maxRows)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if arrangementBinding.wrappedValue == .horizontal {
            LabeledContent("Length") {
                Slider(value: lengthBinding, in: Double(FoldWidth.minimum) ... Double(screenCap))
                    .frame(width: 240)
            }
            }
            LabeledContent("Icon size") {
                HStack {
                    Slider(value: $iconScale, in: 0.7 ... 1.4, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int((iconScale * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            LabeledContent("Icon spacing") {
                Slider(value: $iconSpacing, in: 0 ... 16, step: 1)
                    .frame(width: 240)
            }
            Picker("Position", selection: positionBinding) {
                Text("Under the icon").tag(IceBarLocation.iceIcon)
                Text("Under the pointer").tag(IceBarLocation.mousePointer)
                Text("Left edge").tag(IceBarLocation.leftAligned)
                Text("Right edge").tag(IceBarLocation.rightAligned)
            }
        } header: {
            Text("Layout")
        } footer: {
            Text(layoutFootnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var motionTab: some View {
        Section {
            FoldChoiceGrid(
                options: FoldMotion.allCases,
                selection: $motion,
                columns: 3,
                title: \.title,
                tag: \.rawValue
            ) { option in
                Image(systemName: option.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 26)
            }
        } header: {
            Text("Open with")
        } footer: {
            Text((FoldMotion(rawValue: motion) ?? .liquid).caption)
                .foregroundStyle(.secondary)
        }
        Section {
            Slider(value: $motionSpeed, in: 0.4 ... 2) {
                Text("Speed")
            } minimumValueLabel: {
                Image(systemName: "tortoise")
            } maximumValueLabel: {
                Image(systemName: "hare")
            }
            .disabled(motion == FoldMotion.none.rawValue)
        } footer: {
            Text("Drag to change how quickly Fold opens; the preview replays as you go.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var iconTab: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(icons, id: \.name) { set in
                    FoldIconChoice(
                        closed: set.hidden.nsImage(for: appState),
                        open: set.visible.nsImage(for: appState),
                        title: set.name.rawValue,
                        isSelected: general.iceIcon.name == set.name
                    ) {
                        general.iceIcon = set
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Menu bar icon")
        } footer: {
            Text("Each card shows the icon closed, then open.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Show a dot when a hidden icon changes", isOn: $attentionDot)
        } header: {
            Text("Badge")
        } footer: {
            Text("The dot clears when you open Fold. Icons that change all the time, like meters, are ignored.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var behaviourTab: some View {
        Section("Open") {
            Toggle("Open on hover", isOn: $general.showOnHover)
            if general.showOnHover {
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $hoverDelay, in: 0.05 ... 0.8)
                            .frame(width: 180)
                        Text("\(Int((hoverDelay * 1000).rounded())) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        Section {
            Toggle("Live icons", isOn: $liveIcons)
                .onChange(of: liveIcons) { _, on in
                    if on, !ScreenCapture.cachedCheckPermissions(reset: true) {
                        ScreenCapture.requestPermissions()
                    }
                }
        } header: {
            Text("Icons")
        } footer: {
            Text(liveIcons
                ? "The drawer shows exactly what each icon shows, like a battery level. Needs Screen Recording, and Fold captures the menu bar while it runs."
                : "The drawer shows a grey app icon for each item instead. Fold never looks at your screen, so it doesn't need Screen Recording.")
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Close", selection: closeBinding) {
                Text("When I click elsewhere").tag(FoldClose.elsewhere)
                Text("After 5 seconds").tag(FoldClose.after(5))
                Text("After 10 seconds").tag(FoldClose.after(10))
                Text("After 30 seconds").tag(FoldClose.after(30))
                Text("Only when I close it").tag(FoldClose.never)
            }
            LaunchAtLogin.Toggle { Text("Open at login") }
        } header: {
            Text("Close")
        } footer: {
            Text(general.showOnHover
                ? "Rest on the menu-bar icon to open; move away to close."
                : "Click the menu-bar icon to open. Right-click it for settings.")
                .foregroundStyle(.secondary)
        }
        updatesSection
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    private var updatesSection: some View {
        @Bindable var updates = appState.updatesManager
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
            LabeledContent("Version") {
                HStack {
                    Text(appVersion).foregroundStyle(.secondary).monospacedDigit()
                    Button("Check Now") { appState.updatesManager.checkForUpdates() }
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("New versions come from github.com/SamDeHerdt/Fold and are verified with Fold's signing key before they install.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var shortcutsTab: some View {
        Section {
            if let open = appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection) {
                HotkeyRecorder(hotkey: open) { Text("Open Fold") }
            }
            if let search = appState.settings.hotkeys.hotkey(withAction: .searchMenuBarItems) {
                HotkeyRecorder(hotkey: search) { Text("Search icons") }
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Search finds any menu-bar icon by name, hidden or not, and opens it.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    private var lengthBinding: Binding<Double> {
        Binding(
            get: { maxWidth > 0 ? min(maxWidth, Double(screenCap)) : Double(screenCap) },
            set: { maxWidth = $0 >= Double(screenCap) - 1 ? 0 : $0.rounded() }
        )
    }

    private var layoutFootnote: String {
        switch arrangementBinding.wrappedValue {
        case .horizontal:
            maxWidth > 0 ? "Up to \(Int(lengthBinding.wrappedValue)) pt. More icons scroll." : "As wide as your icons need, up to the screen edge."
        case .grid:
            "Icons wrap into rows; more than \(maxRows) rows scroll. Liquid and Bubbles open as Pop here."
        case .vertical:
            "Icons stack in one column; more than \(maxRows) scroll. Liquid and Bubbles open as Pop here."
        }
    }

    /// Applies a change to the drawer's configuration on every known display.
    private func updateAllDisplays(_ transform: @escaping (DisplayIceBarConfiguration) -> DisplayIceBarConfiguration) {
        let displays = appState.settings.displaySettings
        for display in displays.allDisplays() {
            displays.updateConfiguration(forDisplayUUID: display.id, transform: transform)
        }
    }

    private var arrangementBinding: Binding<IceBarLayout> {
        let displays = appState.settings.displaySettings
        return Binding(
            get: { displays.configurationForActiveDisplay().iceBarLayout },
            set: { layout in updateAllDisplays { $0.withIceBarLayout(layout) } }
        )
    }

    private var gridColumnsBinding: Binding<Int> {
        let displays = appState.settings.displaySettings
        return Binding(
            get: { displays.configurationForActiveDisplay().gridColumns },
            set: { columns in updateAllDisplays { $0.withGridColumns(columns) } }
        )
    }

    /// Where the drawer appears, applied to every display Fold knows about.
    private var positionBinding: Binding<IceBarLocation> {
        let displays = appState.settings.displaySettings
        return Binding(
            get: { displays.configurationForActiveDisplay().iceBarLocation },
            set: { location in
                for display in displays.allDisplays() {
                    displays.updateConfiguration(forDisplayUUID: display.id) { $0.withIceBarLocation(location) }
                }
            }
        )
    }

    private var closeBinding: Binding<FoldClose> {
        Binding(
            get: { FoldClose(general) },
            set: { $0.apply(to: general) }
        )
    }

    private var icons: [ControlItemImageSet] {
        let extra = ControlItemImageSet.userSelectableIceIcons.filter { $0.name != .chevronDown }
        return ControlItemImageSet.foldIcons + extra
    }
}

// MARK: - Choice grid

/// A grid of selectable cards: a small visual over a title.
private struct FoldChoiceGrid<Option: Identifiable, Visual: View>: View {
    let options: [Option]
    @Binding var selection: String
    let columns: Int
    let title: KeyPath<Option, String>
    let tag: KeyPath<Option, String>
    @ViewBuilder let visual: (Option) -> Visual

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(options) { option in
                let isSelected = selection == option[keyPath: tag]
                Button {
                    selection = option[keyPath: tag]
                } label: {
                    VStack(spacing: 6) {
                        visual(option)
                        Text(option[keyPath: title])
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option[keyPath: title])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

/// A miniature drawer drawn in a given look, for the style cards.
private struct FoldLookSwatch: View {
    let look: FoldLook

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.3, blue: 0.45), Color(red: 0.45, green: 0.3, blue: 0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 70, height: 30)
            swatch
                .frame(width: 54, height: 16)
            HStack(spacing: 4) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    Circle().frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(look.forcesDarkIcons ? Color.black.opacity(0.75) : Color.white)
        }
    }

    @ViewBuilder
    private var swatch: some View {
        switch look {
        case .glass:
            Capsule().fill(.regularMaterial)
        case .frosted:
            Capsule().fill(.thinMaterial).overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        case .solid:
            Capsule().fill(Color(white: 0.14))
        case .outline:
            Capsule().fill(.black.opacity(0.25)).overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        case .minimal:
            Color.clear
        case .accent:
            Capsule().fill(FoldTint.color(UserDefaults.standard.string(forKey: FoldKey.tint) ?? ""))
        case .paper:
            Capsule().fill(foldPaperColor)
        case .obsidian:
            Capsule().fill(foldObsidianColor).overlay(Capsule().strokeBorder(foldTopHighlight(0.3), lineWidth: 1))
        }
    }
}

/// A menu-bar icon set, shown as its closed and open states.
private struct FoldIconChoice: View {
    let closed: NSImage?
    let open: NSImage?
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private func glyph(_ image: NSImage?, active: Bool) -> some View {
        Group {
            if let image {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: "questionmark")
            }
        }
        .frame(width: 30, height: 22)
        // The open state carries the menu bar's highlight, as it does live.
        .background(Capsule().fill(Color.primary.opacity(active ? 0.16 : 0)))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    glyph(closed, active: false)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    glyph(open, active: true)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

/// A scaled stand-in for the menu bar and the drawer hanging from the chosen
/// icon, using the real hidden icons, current look, motion, length and spacing.
private struct FoldPreview: View {
    let appState: AppState
    let icon: ControlItemImageSet
    let cap: CGFloat
    let spacing: Double
    let iconScale: Double
    let arrangement: IceBarLayout
    let columns: Int
    let maxRows: Int
    let showsNames: Bool
    let position: IceBarLocation
    let showsDot: Bool
    let replay: Int
    let onReplay: () -> Void
    @AppStorage(FoldKey.appearance) private var appearance = "dark"
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.motion) private var motionRaw = FoldMotion.liquid.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1
    @State private var replayGeneration = 0

    private static let baseIconHeight: CGFloat = 22
    private static let padding: CGFloat = 13
    private static let baseBarHeight: CGFloat = 30

    private var iconHeight: CGFloat { Self.baseIconHeight * CGFloat(iconScale) }
    private var barHeight: CGFloat { Self.baseBarHeight * CGFloat(iconScale) }
    private static let canvas = CGSize(width: 528, height: 150)
    private static let menuBarHeight: CGFloat = 24

    private var scheme: ColorScheme {
        appearance == "light" ? .light : appearance == "dark" ? .dark : systemScheme
    }

    private var lookValue: FoldLook {
        FoldLook(rawValue: look) ?? .glass
    }

    private var iconColor: Color {
        if lookValue.forcesDarkIcons { return .black }
        return scheme == .dark || lookValue.forcesLightIcons ? .white : .black
    }

    private static let darkBackdrop: [Color] = [
        Color(red: 0.16, green: 0.2, blue: 0.3),
        Color(red: 0.32, green: 0.22, blue: 0.36),
    ]
    private static let lightBackdrop: [Color] = [
        Color(red: 0.62, green: 0.76, blue: 0.92),
        Color(red: 0.93, green: 0.78, blue: 0.7),
    ]

    private var backdropColors: [Color] {
        scheme == .dark ? Self.darkBackdrop : Self.lightBackdrop
    }

    private var chevronHighlight: Double {
        progress > 0.5 ? 0.15 : 0
    }

    private var images: [NSImage] {
        let items = appState.itemManager.itemCache.managedItems(for: .hidden)
        let captured = items.compactMap { appState.imageCache.images[$0.tag]?.nsImage }
        if !captured.isEmpty { return captured }
        return ["wifi", "bolt.fill", "cloud.fill", "paperplane.fill", "sparkle", "lock.fill", "music.note"]
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }

    private var itemSpacing: CGFloat {
        4 + CGFloat(spacing)
    }

    private func width(of image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return iconHeight }
        return image.size.width * iconHeight / image.size.height
    }

    private var naturalWidth: CGFloat {
        let icons = images.reduce(0) { $0 + width(of: $1) }
        return icons + CGFloat(max(0, images.count - 1)) * itemSpacing + Self.padding * 2
    }

    private var isRow: Bool { arrangement == .horizontal }

    /// Uniform cell width for the grid and column arrangements.
    private var cellWidth: CGFloat {
        min(max(images.map { width(of: $0) }.max() ?? iconHeight, iconHeight), iconHeight * 1.8)
    }

    /// The icons as rows: one row, wrapped rows, or one icon per row.
    private var rows: [[NSImage]] {
        switch arrangement {
        case .horizontal:
            return [images]
        case .vertical:
            return images.map { [$0] }
        case .grid:
            let perRow = max(1, columns)
            return stride(from: 0, to: images.count, by: perRow).map { Array(images[$0 ..< min($0 + perRow, images.count)]) }
        }
    }

    private var shownRows: [[NSImage]] {
        isRow ? rows : Array(rows.prefix(max(1, maxRows)))
    }

    /// Bar size in real points, before it is shrunk to fit the canvas.
    private var realSize: CGSize {
        switch arrangement {
        case .horizontal:
            return CGSize(width: min(cap, naturalWidth), height: barHeight)
        case .vertical:
            let width: CGFloat = showsNames ? 190 : cellWidth + 6
            return CGSize(width: width, height: CGFloat(shownRows.count) * barHeight)
        case .grid:
            let perRow = CGFloat(max(1, min(columns, images.count)))
            return CGSize(
                width: perRow * cellWidth + (perRow - 1) * itemSpacing + Self.padding * 2,
                height: CGFloat(shownRows.count) * barHeight
            )
        }
    }

    private var scale: CGFloat {
        let roomWidth: CGFloat = Self.canvas.width - 40
        let roomHeight: CGFloat = Self.canvas.height - Self.menuBarHeight - 34
        return min(1, roomWidth / realSize.width, roomHeight / realSize.height)
    }

    private var visibleCount: Int {
        guard isRow else { return shownRows.reduce(0) { $0 + $1.count } }
        var used = Self.padding * 2
        var count = 0
        for image in images.reversed() {
            let next = used + width(of: image) + (count > 0 ? itemSpacing : 0)
            if next > realSize.width { break }
            used = next
            count += 1
        }
        return count
    }

    var body: some View {
        let size = realSize
        let barWidth: CGFloat = size.width * scale
        let chevronX: CGFloat = Self.canvas.width * 0.7
        let underIcon: CGFloat = min(max(chevronX - barWidth / 2, 12), Self.canvas.width - barWidth - 12)
        let barX: CGFloat = switch position {
        case .leftAligned: 12
        case .rightAligned: Self.canvas.width - barWidth - 12
        default: underIcon
        }
        let barY: CGFloat = Self.menuBarHeight + 6
        let scaledBarHeight: CGFloat = size.height * scale
        let caption: String = images.count > visibleCount ? "\(visibleCount) of \(images.count) icons · rest scroll" : "\(images.count) icons"

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: backdropColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: Self.menuBarHeight)
            if let image = (progress > 0.5 ? icon.visible : icon.hidden).nsImage(for: appState) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(chevronHighlight)))
                    .overlay(alignment: .topTrailing) {
                        // The attention dot, as it sits on the real icon.
                        if showsDot {
                            Circle().frame(width: 5, height: 5).offset(x: 1, y: 1)
                        }
                    }
                    .position(x: chevronX, y: Self.menuBarHeight / 2)
            if position == .mousePointer {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 11))
                    .position(x: chevronX + 9, y: Self.menuBarHeight / 2 + 7)
            }
            }
            bar(size: size, anchorX: min(max((chevronX - barX) / scale, 0), size.width), pourCenterY: (Self.menuBarHeight / 2 - barY) / scale)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: barWidth, height: scaledBarHeight, alignment: .topLeading)
                .offset(x: barX, y: barY)
            HStack {
                Button {
                    onReplay()
                } label: {
                    Label("Replay", systemImage: "play.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer()
                Text(caption)
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.85))
            .shadow(radius: 2)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, scheme)
        .foregroundStyle(scheme == .dark ? .white : .black)
        .onChange(of: replay) {
            guard !reduceMotion, let animation = motion.openAnimation else {
                progress = 1
                return
            }
            // Reset first, animate on a later pass: setting 0 and then 1 in
            // the same update can leave the preview stuck folded.
            replayGeneration += 1
            let generation = replayGeneration
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { progress = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard generation == replayGeneration else { return }
                withAnimation(animation) { progress = 1 }
            }
        }
        .onAppear { progress = 1 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the Fold drawer")
    }

    /// The motion as the drawer would play it in this arrangement.
    private var motion: FoldMotion {
        (FoldMotion(rawValue: motionRaw) ?? .liquid).effective(inRow: isRow)
    }

    /// Real app names for the preview's rows, where the drawer knows them.
    private var names: [String] {
        let items = appState.itemManager.itemCache.managedItems(for: .hidden)
        let named = items.filter { appState.imageCache.images[$0.tag] != nil }.map(\.displayName)
        return named.isEmpty ? ["Wi-Fi", "Power", "Cloud", "Messages", "Assistant", "Passwords", "Music"] : named
    }

    /// Cascade in the preview: how far the icon at `rank` has popped in.
    private func cascade(rank: Int) -> CGFloat {
        guard motion == .cascade else { return 1 }
        return min(1, max(0, (progress - 0.08 - CGFloat(rank) * 0.09) / 0.3))
    }

    private func icon(_ image: NSImage, cell: Bool, rank: Int = 0) -> some View {
        let pop = cascade(rank: rank)
        return Image(nsImage: image)
            .renderingMode(.template)
            .resizable()
            .frame(width: width(of: image), height: iconHeight)
            .frame(width: cell ? cellWidth : nil, height: cell ? barHeight : nil)
            .scaleEffect(0.3 + 0.7 * pop)
            .opacity(Double(pop))
    }

    @ViewBuilder
    private var icons: some View {
        if isRow {
            HStack(spacing: itemSpacing) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    icon(image, cell: false, rank: images.count - 1 - index)
                }
            }
        } else if arrangement == .vertical, showsNames {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shownRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 6) {
                        if let image = row.first { icon(image, cell: true) }
                        Text(index < names.count ? names[index] : "")
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: barHeight)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shownRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: itemSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, image in
                            icon(image, cell: true)
                        }
                    }
                }
            }
        }
    }

    private func bar(size: CGSize, anchorX: CGFloat, pourCenterY: CGFloat) -> some View {
        icons
            .foregroundStyle(iconColor)
            .padding(.horizontal, arrangement == .vertical ? (showsNames ? 8 : 3) : Self.padding)
            .frame(width: size.width, height: size.height, alignment: isRow ? .trailing : .topLeading)
            .clipped()
            .shadow(color: lookValue == .minimal ? .black.opacity(0.45) : .clear, radius: 2)
            .modifier(FoldMorphReveal(
                progress: progress,
                anchorX: anchorX,
                motion: motion,
                pourCenterY: pourCenterY,
                slotCount: images.count,
                cornerRadius: isRow ? nil : 18,
                columns: arrangement == .grid ? max(1, columns) : 1
            ))
    }
}

/// Fold's plain-language view of Thaw's rehide settings.
private enum FoldClose: Hashable {
    case elsewhere
    case after(Int)
    case never

    init(_ general: GeneralSettings) {
        if !general.autoRehide {
            self = .never
        } else if general.rehideStrategy == .timed {
            self = .after(Int(general.rehideInterval.rounded()))
        } else {
            self = .elsewhere
        }
    }

    func apply(to general: GeneralSettings) {
        switch self {
        case .elsewhere:
            general.autoRehide = true
            general.rehideStrategy = .smart
        case let .after(seconds):
            general.autoRehide = true
            general.rehideStrategy = .timed
            general.rehideInterval = TimeInterval(seconds)
        case .never:
            general.autoRehide = false
        }
    }
}
