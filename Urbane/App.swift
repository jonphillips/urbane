import CloudKit
import Dependencies
import UIKit
import SwiftUI
import SQLiteData
import UrbaneSchema

@main
struct UrbaneApp: App {
  @UIApplicationDelegateAdaptor(UrbaneAppDelegate.self) private var appDelegate

  init() {
    do {
      try UrbaneStorage.prepareLiveDatabase()
    } catch {
      fatalError("Urbane database bootstrap failed: \(error)")
    }
    UrbaneCloudSync.persistManualEnablementFromLaunchEnvironment()
    Task { _ = await UrbaneCloudSync.startIfManuallyEnabled() }
  }

  var body: some Scene {
    WindowGroup {
      MapHomeView()
    }
  }
}

final class UrbaneAppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = UrbaneSceneDelegate.self
    return configuration
  }
}

final class UrbaneSceneDelegate: UIResponder, UIWindowSceneDelegate {
  @Dependency(\.defaultDatabase) private var database

  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    accept(metadata)
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
  }

  private func accept(_ metadata: CKShare.Metadata) {
    Task {
      do {
        try await UrbaneCloudSync.acceptShare(metadata)
        UrbaneCloudSync.setManuallyEnabled(true)
        _ = await UrbaneCloudSync.startIfManuallyEnabled()
        for _ in 0..<40 {
          if try await UrbaneCloudSync.reconcileAcceptedShare(in: database) { return }
          try await Task.sleep(for: .milliseconds(250))
        }
        UserDefaults.standard.set("The invitation was accepted. The shared search is still loading.", forKey: "urbane.shareAcceptanceMessage")
      } catch LocalSearchCleanupError.localSearchContainsData {
        UserDefaults.standard.set(true, forKey: "urbane.shareAcceptanceBlocked")
        UserDefaults.standard.set(
          "The shared search was accepted, but this device already has apartment data. Export it before replacing this local search.",
          forKey: "urbane.shareAcceptanceMessage"
        )
      } catch {
        UserDefaults.standard.set("Couldn’t finish accepting the shared search: \(error.localizedDescription)", forKey: "urbane.shareAcceptanceMessage")
      }
    }
  }
}
