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
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.maxWidth) private var maxWidth = 0.0
    @AppStorage(FoldKey.motion) private var motion = FoldMotion.liquid.rawValue
    @AppStorage(FoldKey.hoverDelay) private var hoverDelay = 0.18
    @AppStorage(FoldKey.iconSpacing) private var iconSpacing = 0.0
    @AppStorage(FoldKey.iconScale) private var iconScale = 1.0
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
        "\(motion)|\(look)|\(glass)|\(appearance)|\(maxWidth)|\(iconSpacing)|\(iconScale)|\(general.iceIcon.name.rawValue)"
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
                }.pickerStyle(.segmented)
            }
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
        }
        Section {
            LabeledContent("Length") {
                Slider(value: lengthBinding, in: Double(FoldWidth.minimum) ... Double(screenCap))
                    .frame(width: 240)
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
            Text(maxWidth > 0 ? "Up to \(Int(lengthBinding.wrappedValue)) pt. More icons scroll." : "As wide as your icons need, up to the screen edge.")
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
    }

    @ViewBuilder
    private var iconTab: some View {
        Section("Menu bar icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(icons, id: \.name) { set in
                    FoldIconChoice(
                        image: set.hidden.nsImage(for: appState),
                        title: set.name.rawValue,
                        isSelected: general.iceIcon.name == set.name
                    ) {
                        general.iceIcon = set
                    }
                }
            }
            .padding(.vertical, 2)
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

    private static let aurora: [Color] = [
        Color(red: 0.36, green: 0.29, blue: 0.86),
        Color(red: 0.76, green: 0.28, blue: 0.62),
        Color(red: 0.16, green: 0.62, blue: 0.72),
    ]

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
            .foregroundStyle(Color.white)
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
            Capsule().fill(Color.accentColor)
        case .neon:
            Capsule().fill(Color(white: 0.06))
                .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.2).shadow(color: .accentColor, radius: 3))
        case .aurora:
            Capsule().fill(LinearGradient(colors: Self.aurora, startPoint: .leading, endPoint: .trailing))
        }
    }
}

private struct FoldIconChoice: View {
    let image: NSImage?
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(nsImage: image).renderingMode(.template)
                } else {
                    Image(systemName: "questionmark")
                }
            }
            .frame(width: 44, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
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
    let replay: Int
    let onReplay: () -> Void
    @AppStorage(FoldKey.appearance) private var appearance = "dark"
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.motion) private var motionRaw = FoldMotion.liquid.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

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
        scheme == .dark || lookValue.forcesLightIcons ? .white : .black
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

    /// Bar length in real points, then shrunk to fit the preview canvas.
    private var realWidth: CGFloat { min(cap, naturalWidth) }
    private var scale: CGFloat { min(1, (Self.canvas.width - 40) / realWidth) }

    private var visibleCount: Int {
        var used = Self.padding * 2
        var count = 0
        for image in images.reversed() {
            let next = used + width(of: image) + (count > 0 ? itemSpacing : 0)
            if next > realWidth { break }
            used = next
            count += 1
        }
        return count
    }

    var body: some View {
        let barWidth: CGFloat = realWidth * scale
        let chevronX: CGFloat = Self.canvas.width * 0.7
        let barX: CGFloat = min(max(chevronX - barWidth / 2, 12), Self.canvas.width - barWidth - 12)
        let barY: CGFloat = Self.menuBarHeight + 6
        let scaledBarHeight: CGFloat = barHeight * scale
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
                    .position(x: chevronX, y: Self.menuBarHeight / 2)
            }
            bar(anchorX: (chevronX - barX) / scale, pourCenterY: (Self.menuBarHeight / 2 - barY) / scale)
                .frame(width: realWidth, height: barHeight)
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
            guard !reduceMotion else { return }
            progress = 0
            let motion = FoldMotion(rawValue: motionRaw) ?? .liquid
            if let animation = motion.openAnimation {
                withAnimation(animation.delay(0.1)) { progress = 1 }
            } else {
                progress = 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the Fold drawer")
    }

    private func bar(anchorX: CGFloat, pourCenterY: CGFloat) -> some View {
        HStack(spacing: itemSpacing) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: width(of: image), height: iconHeight)
            }
        }
        .foregroundStyle(iconColor)
        .padding(.horizontal, Self.padding)
        .frame(width: realWidth, height: barHeight, alignment: .trailing)
        .clipped()
        .shadow(color: lookValue == .minimal ? .black.opacity(0.45) : .clear, radius: 2)
        .modifier(FoldMorphReveal(
            progress: progress,
            anchorX: anchorX,
            motion: FoldMotion(rawValue: motionRaw) ?? .liquid,
            pourCenterY: pourCenterY,
            slotCount: images.count
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
