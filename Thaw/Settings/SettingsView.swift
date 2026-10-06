//
//  SettingsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import LaunchAtLogin

// MARK: - SettingsView

struct SettingsView: View {
    let appState: AppState
    let navigationState: AppNavigationState
    @State private var searchModel = SearchModel()

    private var allSections: [SettingsNavigationIdentifier] {
        SettingsNavigationIdentifier.allCases
    }

    private var currentSectionIndex: Int? {
        allSections.firstIndex(of: navigationState.settingsNavigationIdentifier)
    }

    private var isFirstSection: Bool {
        currentSectionIndex == 0
    }

    private var isLastSection: Bool {
        currentSectionIndex == allSections.count - 1
    }

    var body: some View {
        if Constants.bundleIdentifier == "com.samdeherdt.fold" {
            FoldSettingsContent(appState: appState, general: appState.settings.general)
        } else {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsPane
                .id(navigationState.settingsNavigationIdentifier)
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button(action: navigateBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(isFirstSection)

                    Button(action: navigateForward) {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(isLastSection)
                }
                .controlGroupStyle(.navigation)
            }
        }
        }
    }

    private var sidebar: some View {
        // Use a Binding that wraps the navigation state to ensure updates happen
        // on the main thread and avoid view update warnings.
        let selection = Binding<SettingsNavigationIdentifier>(
            get: { navigationState.settingsNavigationIdentifier },
            set: { newValue in
                if navigationState.settingsNavigationIdentifier != newValue {
                    Task { @MainActor in
                        SettingsSearchNavigation.selectSidebarPane(
                            newValue,
                            navigationState: navigationState
                        )
                    }
                }
            }
        )

        return VStack(spacing: 0) {
            SearchField(text: $searchModel.searchText)

            if searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                List(selection: selection) {
                    Section {
                        ForEach(SettingsNavigationIdentifier.allCases) { identifier in
                            Label {
                                Text(identifier.localized)
                            } icon: {
                                identifier.iconResource.view
                            }
                            .tag(identifier)
                        }
                    }
                }
                .listStyle(.sidebar)
            } else if searchModel.displayedGroups.isEmpty {
                SearchEmptyView()
            } else {
                SearchResultsList(groups: searchModel.displayedGroups) { entry in
                    SettingsSearchNavigation.selectSearchResult(
                        entry,
                        navigationState: navigationState,
                        query: &searchModel.searchText
                    )
                }
            }
        }
        .navigationSplitViewColumnWidth(ideal: 180, max: 220)
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(
                settings: appState.settings.general,
                advancedSettings: appState.settings.advanced
            )
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(
                itemManager: appState.itemManager,
                advancedSettings: appState.settings.advanced
            )
        case .displays:
            DisplaySettingsPane(displaySettings: appState.settings.displaySettings)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .profiles:
            ProfileSettingsPane(profileManager: appState.profileManager)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .automation:
            AutomationSettingsPane()
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }

    private func navigateBack() {
        guard let index = currentSectionIndex, index > 0 else { return }
        navigationState.settingsNavigationIdentifier = allSections[index - 1]
    }

    private func navigateForward() {
        guard let index = currentSectionIndex, index < allSections.count - 1 else { return }
        navigationState.settingsNavigationIdentifier = allSections[index + 1]
    }
}

/// The local fork exposes only controls needed for its everyday drawer.
private struct FoldSettingsContent: View {
    let appState: AppState
    @Bindable var general: GeneralSettings
    @AppStorage("FoldAppearanceV1") private var appearance = "dark"
    @AppStorage("FoldGlassV1") private var glass = "system"
    @State private var isArranging = false
    @State private var window: NSWindow?

    private var contentSize: NSSize {
        isArranging ? NSSize(width: 680, height: 490) : NSSize(width: 440, height: 340)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isArranging {
                MenuBarLayoutSettingsPane(itemManager: appState.itemManager, advancedSettings: appState.settings.advanced)
                    .frame(width: 680, height: 430)
                HStack {
                    Button("Back") { isArranging = false }
                    Spacer()
                }.padding(16)
            } else {
                Form {
                    Section("Appearance") {
                        Picker("Appearance", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }.pickerStyle(.segmented)
                        Picker("Liquid Glass", selection: $glass) {
                            Text("System").tag("system")
                            Text("Clear").tag("clear")
                            Text("Tinted").tag("tinted")
                        }.pickerStyle(.segmented)
                    }
                    Section {
                        Toggle("Open on hover", isOn: $general.showOnHover)
                        LaunchAtLogin.Toggle { Text("Open at login") }
                    }
                }.formStyle(.grouped)
                HStack {
                    Button("Arrange icons…") { isArranging = true }
                    Spacer()
                    Button("Open Fold") { appState.menuBarManager.section(withName: .hidden)?.show() }
                }.padding(16)
            }
        }
        .frame(width: isArranging ? 680 : 440, height: isArranging ? 490 : 340)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
        .navigationTitle("Fold")
        .onWindowChange(update: $window)
        .onChange(of: isArranging) {
            // Resize the host as well as the SwiftUI content. Otherwise the
            // arrangement rows can remain clipped by the compact window.
            Task { @MainActor in
                window?.setContentSize(contentSize)
            }
        }
    }
}

/// Native Liquid Glass follows the system setting by default; local choices
/// permit a clearer or tinted surface without changing macOS preferences.
struct FoldGlassSurface: ViewModifier {
    @AppStorage("FoldGlassV1") private var glass = "system"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.93), in: Capsule())
        } else if glass == "clear" {
            content.glassEffect(.clear, in: Capsule())
        } else if glass == "tinted" {
            content.glassEffect(.regular.tint((colorScheme == .dark ? Color.black : Color.white).opacity(0.35)), in: Capsule())
        } else {
            content.glassEffect(.regular, in: Capsule())
        }
    }
}
