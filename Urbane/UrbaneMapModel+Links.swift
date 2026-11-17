import SQLiteData
import UrbaneCore
import UrbaneSchema

@MainActor extension UrbaneMapModel {
  func updateBuildingLinks(_ building: Building, websiteURL: String?, streetEasyURL: String?) {
    withErrorReporting {
      try database.write { db in
        try Building.find(building.id).update {
          $0.websiteURL = #bind(websiteURL)
          $0.streetEasyURL = #bind(streetEasyURL)
        }.execute(db)
      }
    }
  }
}
