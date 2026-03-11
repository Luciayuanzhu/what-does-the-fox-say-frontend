//
//  SceneDelegate.swift
//  what does the fox say
//
//  Created by Lucia D on 2026/3/8.
//

import UIKit
import SwiftUI

/// Hosts the SwiftUI application shell inside the UIKit scene lifecycle.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        debugLog(.lifecycle, "scene willConnect")
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: FoxRootView())
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        debugLog(.lifecycle, "scene didDisconnect")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        debugLog(.lifecycle, "scene didBecomeActive")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        debugLog(.lifecycle, "scene willResignActive")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        debugLog(.lifecycle, "scene willEnterForeground")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        debugLog(.lifecycle, "scene didEnterBackground")
    }
}
