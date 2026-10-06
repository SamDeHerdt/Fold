//
//  SettingsWindow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        IceWindow(id: .settings) {
            SettingsView(appState: appState, navigationState: appState.navigationState)
                .sheet(isPresented: $appState.isUpdateConsentPresented) {
                    UpdateConsentSheet { autoDownload in
                        appState.isUpdateConsentPresented = false
                        Defaults.set(true, forKey: .hasSeenUpdateConsent)
                        appState.updatesManager.automaticallyChecksForUpdates = true
                        appState.updatesManager.automaticallyDownloadsUpdates = autoDownload
                        appState.startUpdaterIfNeeded()
                        appState.presentOnboardingIfNeeded()
                    } onDisable: {
                        appState.isUpdateConsentPresented = false
                        Defaults.set(true, forKey: .hasSeenUpdateConsent)
                        appState.updatesManager.automaticallyChecksForUpdates = false
                        appState.presentOnboardingIfNeeded()
                    }
                }
                .sheet(isPresented: $appState.isOnboardingPresented) {
                    ThawOnboardingView {
                        Defaults.set(true, forKey: .hasSeenOnboarding)
                        appState.isOnboardingPresented = false
                    }
                    .environment(appState.permissions)
                    .frame(width: ThawOnboardingWindowMetrics.width, height: ThawOnboardingWindowMetrics.height)
                }
                .frame(minWidth: Constants.bundleIdentifier == "com.samdeherdt.fold" ? 440 : 850,
                       minHeight: Constants.bundleIdentifier == "com.samdeherdt.fold" ? 340 : 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: Constants.bundleIdentifier == "com.samdeherdt.fold" ? 440 : 950,
                     height: Constants.bundleIdentifier == "com.samdeherdt.fold" ? 340 : 650)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .environment(appState)
    }
}
