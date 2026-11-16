import Dependencies
import Foundation
import SQLiteData

public enum UrbaneStorage {
  private static let appGroupInfoKey = "UrbaneAppGroupID"

  public enum StorageError: Error {
    case appGroupIdentifierUnavailable
    case appGroupUnavailable
  }

  public static func liveDatabasePath() throws -> String {
    guard let appGroupID = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
          !appGroupID.isEmpty
    else {
      throw StorageError.appGroupIdentifierUnavailable
    }
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID
    ) else {
      throw StorageError.appGroupUnavailable
    }
    return container.appending(path: "urbane.sqlite").path(percentEncoded: false)
  }

  public static func prepareLiveDatabase() throws {
    try prepareDependencies {
      try $0.bootstrapUrbaneDatabase()
    }
  }
}

extension DependencyValues {
  public mutating func bootstrapUrbaneDatabase() throws {
    let database = try SQLiteData.defaultDatabase(path: UrbaneStorage.liveDatabasePath())
    try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
    defaultDatabase = database
  }
}
