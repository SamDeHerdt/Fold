//
//  IceApp.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ApplicationServices

/// The process entry point.
///
/// Wraps ``IceApp`` so a command-line invocation can be served and the
/// process exited before AppKit starts. ``IceApp`` cannot do this itself:
/// its `@NSApplicationDelegateAdaptor` builds the `AppDelegate` — and with
/// it the whole `AppState` — as the `App` value is constructed, which is
/// already too late to decline to run.
@main
enum ThawMain {
    static func main() {
        guard !LayoutResetCommand.runIfRequested() else {
            return
        }
        configureFoldIfNeeded()
        IceApp.main()
    }

    /// Import only the old manager's divider positions into our own status items.
    /// This preserves the split without rearranging any third-party icons.
    private static func configureFoldIfNeeded() {
        guard Bundle.main.bundleIdentifier == "com.samdeherdt.fold" else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Defaults.Key.hasSeenUpdateConsent.rawValue)
        if AXIsProcessTrusted() {
            defaults.set(true, forKey: Defaults.Key.hasCompletedFirstLaunch.rawValue)
            defaults.set(true, forKey: Defaults.Key.hasSeenOnboarding.rawValue)
        }
        guard !defaults.bool(forKey: "FoldThawConfiguredV1") else { return }
        let oldSettings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.dwarvesv.minimalbar/Data/Library/Preferences/com.dwarvesv.minimalbar.plist")
        if let data = try? Data(contentsOf: oldSettings),
           let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (old, new) in [
                ("hiddenbar_expandcollapse", "Thaw.ControlItem.Visible"),
                ("hiddenbar_separate", "Thaw.ControlItem.Hidden")
            ] {
                if let position = settings["NSStatusItem Preferred Position \(old)"] as? Double {
                    defaults.set(position, forKey: "NSStatusItem Preferred Position \(new)")
                }
            }
        }
        defaults.set(true, forKey: "FoldThawConfiguredV1")
    }
}

struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
