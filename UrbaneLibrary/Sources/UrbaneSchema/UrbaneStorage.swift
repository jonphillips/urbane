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
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        do {
          try db.attachMetadatabase(containerIdentifier: UrbaneCloudSync.configuration.containerIdentifier)
        } catch {
          reportIssue("Sync metadata unavailable; running local-only: \(error)")
        }
      }
      let database = try SQLiteData.defaultDatabase(
        path: liveDatabasePath(), configuration: configuration
      )
      try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
      $0.defaultDatabase = database
      do {
        $0.defaultSyncEngine = try UrbaneCloudSync.makeSyncEngine(for: database, startImmediately: false)
        $0.syncEngineAvailable = true
      } catch {
        reportIssue("CloudKit sync unavailable; running local-only: \(error)")
        $0.syncEngineAvailable = false
      }
    }
  }

  public static func migrateRestoreCandidate(at url: URL) throws {
    let database = try SQLiteData.defaultDatabase(path: url.path)
    try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
    try database.close()
  }
}

extension DependencyValues {
  public mutating func bootstrapUrbaneDatabase() throws {
    let database = try SQLiteData.defaultDatabase(path: UrbaneStorage.liveDatabasePath())
    try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
    defaultDatabase = database
  }

  public var syncEngineAvailable: Bool {
    get { self[SyncEngineAvailableKey.self] }
    set { self[SyncEngineAvailableKey.self] = newValue }
  }
}

private enum SyncEngineAvailableKey: DependencyKey {
  static let liveValue = false
  static let testValue = true
}
