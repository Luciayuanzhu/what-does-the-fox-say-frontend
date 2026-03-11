//
//  AppDelegate.swift
//  what does the fox say
//
//  Created by Lucia D on 2026/3/8.
//

import UIKit

@main
/// Boots the application, registers Settings.bundle defaults, and persists the first-launch timestamp.
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Initializes process-wide preferences before any scene UI is attached.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        registerSettingsDefaults()
        storeInitialLaunchIfNeeded()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    /// Reads the generated Settings.bundle plist and registers its default values into UserDefaults.
    private func registerSettingsDefaults() {
        guard let settingsURL = Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"),
              let data = try? Data(contentsOf: settingsURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let specifiers = plist["PreferenceSpecifiers"] as? [[String: Any]] else {
            return
        }

        let defaults = specifiers.reduce(into: [String: Any]()) { result, item in
            guard let key = item["Key"] as? String,
                  let defaultValue = item["DefaultValue"] else {
                return
            }
            result[key] = defaultValue
        }
        UserDefaults.standard.register(defaults: defaults)
        debugLog(.lifecycle, "settings defaults registered count=\(defaults.count)")
    }

    /// Stores the first launch date once and mirrors a human-readable string for Settings.bundle display.
    private func storeInitialLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: FoxStorageKeys.initialLaunch) == nil {
            let now = Date()
            defaults.set(now, forKey: FoxStorageKeys.initialLaunch)
            defaults.set(AppDelegate.initialLaunchDisplayFormatter.string(from: now), forKey: FoxStorageKeys.initialLaunchDisplay)
            debugLog(.lifecycle, "initial launch stored date=\(now.formatted(date: .abbreviated, time: .shortened))")
        } else if defaults.string(forKey: FoxStorageKeys.initialLaunchDisplay) == nil,
                  let existingDate = defaults.object(forKey: FoxStorageKeys.initialLaunch) as? Date {
            defaults.set(AppDelegate.initialLaunchDisplayFormatter.string(from: existingDate), forKey: FoxStorageKeys.initialLaunchDisplay)
        }
    }

    private static let initialLaunchDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
