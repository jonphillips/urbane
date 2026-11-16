import SwiftUI
import UrbaneSchema

@main
struct UrbaneApp: App {
  init() {
    do {
      try UrbaneStorage.prepareLiveDatabase()
    } catch {
      fatalError("Urbane database bootstrap failed: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      MapHomeView()
    }
  }
}
