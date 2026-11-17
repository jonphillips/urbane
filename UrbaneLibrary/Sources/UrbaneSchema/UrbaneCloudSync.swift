import CloudKit
import CloudSyncKit
import Dependencies
import SQLiteData
import Foundation

/// Urbane's app-specific binding of the shared sync controls.
public enum UrbaneCloudSync {
  public static let configuration = CloudSyncConfiguration(
    containerIdentifier: "iCloud.com.jonphillips.urbane",
    enabledDefaultsKey: "UrbaneCloudKitSyncEnabled",
    enabledEnvironmentKey: "URBANE_CLOUDKIT_SYNC_ENABLED",
    enabledLaunchArgument: "-UrbaneCloudKitSyncEnabled",
    restoreRequiresManualEnablementDefaultsKey: "UrbaneCloudKitSyncRestoreRequiresManualEnablement"
  )

  #if DEBUG
  private static let backupDisplayName = "Urbane Dev"
  private static let backupFilenamePrefix = "Urbane-Dev-Backup-"
  private static let backupVariant: DatabaseBackupVariant = .development
  #else
  private static let backupDisplayName = "Urbane"
  private static let backupFilenamePrefix = "Urbane-Backup-"
  private static let backupVariant: DatabaseBackupVariant = .production
  #endif

  public static let databaseBackupConfiguration = DatabaseBackupConfiguration(
    displayName: backupDisplayName,
    backupFilenamePrefix: backupFilenamePrefix,
    preRestoreFilenamePrefix: "Urbane-PreRestore-",
    restoreStagingFilenamePrefix: "Urbane-Restore-",
    identifyingTableNames: ["searches", "buildings"],
    declaredSchemaVersion: UrbaneDatabaseMigrations.schemaVersion,
    lastPreRestoreDefaultsKey: "UrbaneDatabaseBackupLastPreRestorePath",
    cloudSync: configuration,
    variant: backupVariant,
    liveStoreURL: { URL(fileURLWithPath: try UrbaneStorage.liveDatabasePath()) },
    migrate: { try UrbaneStorage.migrateRestoreCandidate(at: $0) }
  )

  public static let syncedTables = SyncedTables(
    Search.self, Person.self, Neighborhood.self, NeighborhoodRent.self, Building.self,
    NeighborhoodVignette.self, BuildingVignette.self, Commute.self, RentObservation.self,
    Reaction.self, Photo.self, BuildingReview.self
  )

  public static func makeSyncEngine(
    for database: any DatabaseWriter, startImmediately: Bool
  ) throws -> SyncEngine {
    try SyncEngine(
      for: database,
      tables: Search.self, Person.self, Neighborhood.self, NeighborhoodRent.self, Building.self,
      NeighborhoodVignette.self, BuildingVignette.self, Commute.self, RentObservation.self,
      Reaction.self, Photo.self, BuildingReview.self,
      containerIdentifier: configuration.containerIdentifier,
      startImmediately: startImmediately
    )
  }

  public static func persistManualEnablementFromLaunchEnvironment() {
    CloudSync.persistManualEnablementFromLaunchEnvironment(configuration: configuration)
  }

  public static func isManuallyEnabled() -> Bool {
    CloudSync.isManuallyEnabled(configuration: configuration)
  }

  public static func setManuallyEnabled(_ enabled: Bool) {
    CloudSync.setManuallyEnabled(enabled, configuration: configuration)
  }

  public static func startIfManuallyEnabled() async -> CloudSync.StartResult {
    @Dependency(\.syncEngineAvailable) var available
    guard available else { return .failed("Sync engine unavailable until next launch") }
    @Dependency(\.defaultSyncEngine) var engine
    return await CloudSync.startIfManuallyEnabled(configuration: configuration, startSyncEngine: {
      try await engine.start()
    })
  }

  public static func acceptShare(_ metadata: CKShare.Metadata) async throws {
    @Dependency(\.defaultSyncEngine) var engine
    try await engine.acceptShare(metadata: metadata)
  }

  public static func currentUserRecordName() async throws -> String {
    try await CKContainer(identifier: configuration.containerIdentifier).userRecordID().recordName
  }

  public static func sharedSearch(in db: Database) throws -> Search? {
    for search in try Search.fetchAll(db) {
      let share = try SyncMetadata.find(search.syncMetadataID).select(\.share).fetchOne(db) ?? nil
      if share != nil {
        return search
      }
    }
    return nil
  }

  @discardableResult
  public static func reconcileAcceptedShare(in database: any DatabaseWriter) async throws -> Bool {
    guard let sharedSearch = try await database.read({ try sharedSearch(in: $0) }) else { return false }
    try await database.write { db in
      try SearchPeopleOperations.removeEmptyLocalRoots(keeping: sharedSearch.id, in: db)
    }
    UserDefaults.standard.set(sharedSearch.id.uuidString, forKey: "urbane.activeSearchID")
    UserDefaults.standard.removeObject(forKey: "urbane.shareAcceptanceBlocked")
    return true
  }
}
