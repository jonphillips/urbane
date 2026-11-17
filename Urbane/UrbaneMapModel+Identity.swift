import Dependencies
import Foundation
import SQLiteData
import UrbaneSchema

extension UrbaneMapModel {
  func bindCurrentPerson(id: UUID?) {
    guard let id else { return }
    UserDefaults.standard.set(id.uuidString, forKey: "urbane.thisIsMe")
    Task {
      guard let recordName = try? await UrbaneCloudSync.currentUserRecordName() else { return }
      do {
        let result = try await database.write { db in
          try PersonIdentityOperations.claim(
            personID: id,
            accountRecordName: recordName,
            syncEnabled: UrbaneCloudSync.isManuallyEnabled(),
            in: db
          )
        }
        switch result {
        case .claimed, .alreadyClaimed, .syncDisabled:
          break
        case .personNotFound:
          message = "That person is no longer in the active search."
        case .claimedByAnotherAccount:
          message = "That person is linked to a different iCloud account. Your choice remains on this device."
        case .accountAlreadyClaimsAnotherPerson:
          message = "This iCloud account already identifies another person in the search. Your choice remains on this device."
        }
      } catch {
        message = "Couldn’t save the iCloud identity: \(error.localizedDescription)"
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
      await refreshSearchOwnership()
      _ = try await UrbaneCloudSync.reconcileAcceptedShare(in: database)
    } catch LocalSearchCleanupError.localSearchContainsData {
      message = "This device has local apartment data. It was kept on this device and was not merged into the shared search. The shared search is active; see People & identity for this notice."
    } catch {
      message = "Couldn’t finish setting up the shared search: \(error.localizedDescription)"
    }
  }
}
