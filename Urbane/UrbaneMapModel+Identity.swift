import Dependencies
import Foundation
import SQLiteData
import UrbaneSchema

extension UrbaneMapModel {
  var activeSearch: Search? {
    let preferredID = UUID(uuidString: UserDefaults.standard.string(forKey: "urbane.activeSearchID") ?? "")
    return SearchPeopleOperations.activeSearch(in: searches, sharedSearch: nil, preferredID: preferredID)
  }

  func bindCurrentPerson(id: UUID?) {
    guard let id else { return }
    UserDefaults.standard.set(id.uuidString, forKey: "urbane.thisIsMe")
    Task {
      guard let recordName = try? await UrbaneCloudSync.currentUserRecordName() else { return }
      withErrorReporting {
        try database.write { db in
          guard let person = try Person.find(id).fetchOne(db) else { return }
          guard person.iCloudUserRecordName == nil || person.iCloudUserRecordName == recordName else {
            message = "That person is already linked to a different iCloud account."
            return
          }
          try Person.find(id).update { $0.iCloudUserRecordName = #bind(recordName) }.execute(db)
        }
      }
    }
  }

  func bindToCurrentICloudPersonIfKnown() async {
    guard let recordName = try? await UrbaneCloudSync.currentUserRecordName() else { return }
    guard let person = people.first(where: { $0.iCloudUserRecordName == recordName }) else { return }
    let selectedID = UUID(uuidString: UserDefaults.standard.string(forKey: "urbane.thisIsMe") ?? "")
    if selectedID == nil || !people.contains(where: { $0.id == selectedID }) {
      UserDefaults.standard.set(person.id.uuidString, forKey: "urbane.thisIsMe")
    }
  }

  func reconcileAcceptedShare() async {
    do {
      if try await UrbaneCloudSync.reconcileAcceptedShare(in: database) {
        shareAcceptanceBlocked = false
        message = nil
      }
    } catch LocalSearchCleanupError.localSearchContainsData {
      shareAcceptanceBlocked = true
      UserDefaults.standard.set(true, forKey: "urbane.shareAcceptanceBlocked")
      message = "The shared search is active, but this device already has apartment data. Export it before replacing this local search."
    } catch {
      message = "Couldn’t finish setting up the shared search: \(error.localizedDescription)"
    }
  }
}
