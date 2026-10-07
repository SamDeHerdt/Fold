//
//  FoldSettingsView.swift
//  Fold
//
//  Licensed under the GNU GPLv3
//

import LaunchAtLogin
import SwiftUI

/// Fold's compact settings: a live preview, then look, length, icon and behaviour.
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
    @State private var isArranging = false
    @State private var window: NSWindow?
    @State private var replay = 0

    private static let compactSize = NSSize(width: 560, height: 820)
    private static let arrangeSize = NSSize(width: 680, height: 490)

    private var screenWidth: CGFloat {
        NSScreen.main?.frame.width ?? 1512
    }

    private var screenCap: CGFloat {
        FoldWidth.screenCap(for: screenWidth)
    }

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
                Form {
                    Section {
                        FoldPreview(
                            appState: appState,
                            icon: general.iceIcon,
                            cap: FoldWidth.cap(stored: maxWidth, screenWidth: screenWidth),
                            replay: replay
                        )
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        HStack {
                            Spacer()
                            Button("Replay", systemImage: "play.fill") { replay += 1 }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                    }

                    Section("Motion") {
                        Picker("Open", selection: $motion) {
                            ForEach(FoldMotion.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: motion) { replay += 1 }
                    }

                    Section("Look") {
                        Picker("Style", selection: $look) {
                            ForEach(FoldLook.allCases) { Text($0.title).tag($0.rawValue) }
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
                        Slider(value: lengthBinding, in: Double(FoldWidth.minimum) ... Double(screenCap)) {
                            Text("Length")
                        } minimumValueLabel: {
                            Image(systemName: "rectangle.compress.vertical").rotationEffect(.degrees(90))
                        } maximumValueLabel: {
                            Image(systemName: "rectangle.expand.vertical").rotationEffect(.degrees(90))
                        }
                    } header: {
                        Text("Length")
                    } footer: {
                        Text(maxWidth > 0 ? "Up to \(Int(lengthBinding.wrappedValue)) pt. More icons scroll." : "As wide as your icons need, up to the screen edge.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Menu bar icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
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

                    Section("Position") {
                        Picker("Drawer", selection: positionBinding) {
                            Text("Under the icon").tag(IceBarLocation.iceIcon)
                            Text("Under the pointer").tag(IceBarLocation.mousePointer)
                            Text("Left edge").tag(IceBarLocation.leftAligned)
                            Text("Right edge").tag(IceBarLocation.rightAligned)
                        }
                        LabeledContent("Icon spacing") {
                            Slider(value: $iconSpacing, in: 0 ... 16, step: 1)
                                .frame(width: 220)
                        }
                    }

                    Section {
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
                        Picker("Close", selection: closeBinding) {
                            Text("When I click elsewhere").tag(FoldClose.elsewhere)
                            Text("After 5 seconds").tag(FoldClose.after(5))
                            Text("After 10 seconds").tag(FoldClose.after(10))
                            Text("After 30 seconds").tag(FoldClose.after(30))
                            Text("Only when I close it").tag(FoldClose.never)
                        }
                        LaunchAtLogin.Toggle { Text("Open at login") }
                    } header: {
                        Text("Behaviour")
                    } footer: {
                        Text(general.showOnHover
                            ? "Rest on the menu-bar icon to open; move away to close."
                            : "Click the menu-bar icon to open.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Shortcuts") {
                        if let open = appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection) {
                            HotkeyRecorder(hotkey: open) { Text("Open Fold") }
                        }
                        if let search = appState.settings.hotkeys.hotkey(withAction: .searchMenuBarItems) {
                            HotkeyRecorder(hotkey: search) { Text("Search icons") }
                        }
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Button("Arrange icons…") { isArranging = true }
                    Button("Search icons…") {
                        HotkeyAction.searchMenuBarItems.perform(appState: appState)
                    }
                    Spacer()
                    Button("Open Fold") { appState.menuBarManager.section(withName: .hidden)?.show() }
                }.padding(16)
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

/// A scaled stand-in for the menu bar and the drawer hanging from the chosen
/// icon, using the real hidden icons, current look and length.
private struct FoldPreview: View {
    let appState: AppState
    let icon: ControlItemImageSet
    let cap: CGFloat
    let replay: Int
    @AppStorage(FoldKey.appearance) private var appearance = "dark"
    @AppStorage(FoldKey.look) private var look = FoldLook.glass.rawValue
    @AppStorage(FoldKey.motion) private var motionRaw = FoldMotion.liquid.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    private static let iconHeight: CGFloat = 22
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 13
    private static let barHeight: CGFloat = 30
    private static let canvas = CGSize(width: 480, height: 150)
    private static let menuBarHeight: CGFloat = 24

    private var scheme: ColorScheme {
        appearance == "light" ? .light : appearance == "dark" ? .dark : systemScheme
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

    private func width(of image: NSImage) -> CGFloat {
        guard image.size.height > 0 else { return Self.iconHeight }
        return image.size.width * Self.iconHeight / image.size.height
    }

    private var naturalWidth: CGFloat {
        let icons = images.reduce(0) { $0 + width(of: $1) }
        return icons + CGFloat(max(0, images.count - 1)) * Self.spacing + Self.padding * 2
    }

    /// Bar length in real points, then shrunk to fit the preview canvas.
    private var realWidth: CGFloat { min(cap, naturalWidth) }
    private var scale: CGFloat { min(1, (Self.canvas.width - 32) / realWidth) }

    private var visibleCount: Int {
        var used = Self.padding * 2
        var count = 0
        for image in images.reversed() {
            let next = used + width(of: image) + (count > 0 ? Self.spacing : 0)
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
        let barY: CGFloat = Self.menuBarHeight + 4
        let scaledBarHeight: CGFloat = Self.barHeight * scale
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
                .frame(width: realWidth, height: Self.barHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: barWidth, height: scaledBarHeight, alignment: .topLeading)
                .offset(x: barX, y: barY)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 2)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, scheme)
        .foregroundStyle(scheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onChange(of: replay) {
            guard !reduceMotion else { return }
            progress = 0
            let motion = FoldMotion(rawValue: motionRaw) ?? .liquid
            if let animation = motion.openAnimation {
                withAnimation(animation.delay(0.15)) { progress = 1 }
            } else {
                progress = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the Fold drawer")
    }

    private func bar(anchorX: CGFloat, pourCenterY: CGFloat) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: width(of: image), height: Self.iconHeight)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(width: realWidth, height: Self.barHeight, alignment: .trailing)
        .clipped()
        .shadow(color: look == FoldLook.minimal.rawValue ? .black.opacity(0.45) : .clear, radius: 2)
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
