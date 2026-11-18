import CloudKit
import CloudSyncKit
import Dependencies
import GRDB
import Observation
import SQLiteData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UrbaneSchema

@MainActor
@Observable
private final class UrbaneSyncStatusModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var engine
  @ObservationIgnored @Dependency(\.syncEngineAvailable) private var engineAvailable
  private(set) var status = "Sync is off on this device."
  private(set) var rowCounts: [(String, Int)] = []
  private(set) var isRefreshing = false

  func setEnabled(_ enabled: Bool) {
    UrbaneCloudSync.setManuallyEnabled(enabled)
    if enabled {
      Task {
        let result = await UrbaneCloudSync.startIfManuallyEnabled()
        switch result {
        case .started: status = "Sync is running."
        case .disabled: status = "Sync is off on this device."
        case let .unavailable(reason): status = "iCloud unavailable: \(reason)"
        case let .failed(reason): status = "Sync couldn’t start: \(reason)"
        }
        await refresh()
      }
    } else {
      engine.stop()
      status = "Sync is off on this device."
    }
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    let enabled = UrbaneCloudSync.isManuallyEnabled()
    let account = try? await CKContainer(identifier: UrbaneCloudSync.configuration.containerIdentifier).accountStatus()
    if !enabled {
      status = "Sync is off on this device."
    } else if account != .available {
      status = "iCloud account unavailable."
    } else if engineAvailable, engine.isRunning {
      status = engine.isSynchronizing ? "Syncing…" : "Sync is running."
    } else {
      status = "Sync is enabled; waiting for the engine."
    }
    do {
      rowCounts = try await database.read { db in
        try [
          ("searches", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM searches") ?? 0),
          ("people", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM people") ?? 0),
          ("neighborhoods", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM neighborhoods") ?? 0),
          ("neighborhoodRents", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM neighborhoodRents") ?? 0),
          ("buildings", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM buildings") ?? 0),
          ("neighborhoodVignettes", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM neighborhoodVignettes") ?? 0),
          ("buildingVignettes", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM buildingVignettes") ?? 0),
          ("commutes", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM commutes") ?? 0),
          ("rentObservations", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rentObservations") ?? 0),
          ("reactions", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reactions") ?? 0),
          ("photos", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") ?? 0),
          ("buildingReviews", Int.fetchOne(db, sql: "SELECT COUNT(*) FROM buildingReviews") ?? 0),
        ]
      }
    } catch {
      status += " Counts couldn’t be read: \(error.localizedDescription)"
    }
  }
}

@MainActor
private final class UrbaneShareModel: ObservableObject {
  @Published var message: String?
  @Published private(set) var canShare = false
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var engine
  @Dependency(\.syncEngineAvailable) private var engineAvailable
  private var sharingDelegate: UrbaneCloudSharingControllerDelegate?

  func refreshOwnership(for search: Search?) async {
    guard engineAvailable, let search else {
      canShare = false
      return
    }
    canShare = (try? await database.read { db in
      try UrbaneCloudSync.isSearchOwnedByCurrentUser(search, in: db)
    }) ?? false
  }

  func share(_ search: Search?) async {
    guard engineAvailable, let search else {
      message = "Sharing is unavailable until iCloud sync is configured."
      return
    }
    do {
      guard try await database.read({ db in
        try UrbaneCloudSync.isSearchOwnedByCurrentUser(search, in: db)
      }) else {
        canShare = false
        message = "Only the person who owns this search can invite someone."
        return
      }
      canShare = true
      let sharedRecord = try await engine.share(record: search) {
        $0[CKShare.SystemFieldKey.title] = "Urbane Apartment Search"
      }
      presentSharingController(for: sharedRecord.share)
    } catch {
      message = "Couldn’t create the share: \(error.localizedDescription)"
    }
  }

  private func presentSharingController(for share: CKShare) {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      let rootViewController = scene.windows.first(where: \.isKeyWindow)?.rootViewController
    else {
      message = "Couldn’t open sharing because no active window was found."
      return
    }

    var presentingViewController = rootViewController
    while let presentedViewController = presentingViewController.presentedViewController {
      presentingViewController = presentedViewController
    }

    let controller = UICloudSharingController(
      share: share,
      container: CKContainer(identifier: UrbaneCloudSync.configuration.containerIdentifier)
    )
    controller.modalPresentationStyle = .formSheet
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presentingViewController.view
      popover.sourceRect = CGRect(
        x: presentingViewController.view.bounds.midX,
        y: presentingViewController.view.bounds.midY,
        width: 0,
        height: 0
      )
    }

    let delegate = UrbaneCloudSharingControllerDelegate(
      onSaveFailure: { [weak self] error in
        self?.message = "Couldn’t save the share: \(error.localizedDescription)"
      },
      onStopSharing: { [engine] in
        Task { try? await engine.fetchChanges() }
      },
      onDismiss: { [weak self] dismissedDelegate in
        guard self?.sharingDelegate === dismissedDelegate else { return }
        self?.sharingDelegate = nil
      }
    )
    sharingDelegate = delegate
    presentingViewController.present(controller, animated: true) { [weak controller] in
      controller?.presentationController?.delegate = delegate
    }
  }
}

@MainActor
private final class UrbaneCloudSharingControllerDelegate: NSObject,
  UICloudSharingControllerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private let onSaveFailure: (any Error) -> Void
  private let onStopSharing: () -> Void
  private let onDismiss: (UrbaneCloudSharingControllerDelegate) -> Void

  init(
    onSaveFailure: @escaping (any Error) -> Void,
    onStopSharing: @escaping () -> Void,
    onDismiss: @escaping (UrbaneCloudSharingControllerDelegate) -> Void
  ) {
    self.onSaveFailure = onSaveFailure
    self.onStopSharing = onStopSharing
    self.onDismiss = onDismiss
  }

  func itemTitle(for csc: UICloudSharingController) -> String? {
    "Urbane Apartment Search"
  }

  func cloudSharingController(
    _ csc: UICloudSharingController,
    failedToSaveShareWithError error: any Error
  ) {
    onSaveFailure(error)
  }

  func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
    onStopSharing()
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    onDismiss(self)
  }
}

struct SyncAndShareSettingsSection: View {
  let mapModel: UrbaneMapModel
  @State private var sync = UrbaneSyncStatusModel()
  @StateObject private var sharing = UrbaneShareModel()
  @State private var backupExport = DatabaseBackupExportModel(configuration: UrbaneCloudSync.databaseBackupConfiguration)
  @State private var backupRestore = DatabaseBackupRestoreModel(configuration: UrbaneCloudSync.databaseBackupConfiguration)
  @State private var backupDocument: UrbaneBackupDocument?
  @State private var exporting = false
  @State private var importing = false
  @State private var confirmingRestore = false
  @State private var message: String?
  @State private var canBackup = true

  var body: some View {
    Section("iCloud sync and sharing") {
      Toggle("Enable iCloud sync", isOn: Binding(
        get: { UrbaneCloudSync.isManuallyEnabled() },
        set: { sync.setEnabled($0) }
      ))
      Text(sync.status).font(.caption).foregroundStyle(.secondary)
      Button("Refresh sync details") { Task { await sync.refresh() } }
        .disabled(sync.isRefreshing)
      if sync.isRefreshing { ProgressView() }
      ForEach(sync.rowCounts, id: \.0) { name, count in
        LabeledContent(name, value: String(count))
      }
      if sharing.canShare {
        Button("Share with Wendy") { Task { await sharing.share(mapModel.activeSearch) } }
        .disabled(!UrbaneCloudSync.isManuallyEnabled())
      }
      Button("Export backup") {
        Task {
          guard let snapshot = await backupExport.prepareBackupForExport() else {
            message = backupExport.errorMessage
            return
          }
          backupDocument = UrbaneBackupDocument(snapshot: snapshot)
          exporting = true
        }
      }
      .disabled(backupExport.isPreparing || !canBackup)
      Button("Restore backup") { importing = true }
        .disabled(backupRestore.isPreparing || backupRestore.isRestoring || !canBackup)
      if !canBackup { Text("The person who owns this shared search manages backups.").font(.caption).foregroundStyle(.secondary) }
      if let error = backupRestore.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
      if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      if let message = sharing.message { Text(message).font(.caption).foregroundStyle(.red) }
    }
    .task {
      await sync.refresh()
      await sharing.refreshOwnership(for: mapModel.activeSearch)
      do { canBackup = try !(await DatabaseBackup.containsForeignOwnedRows(in: currentDatabase)) }
      catch { canBackup = false }
    }
    .onChange(of: mapModel.activeSearch?.id) { _, _ in
      Task { await sharing.refreshOwnership(for: mapModel.activeSearch) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: backupDocument,
      contentType: .data,
      defaultFilename: backupExport.defaultFilename(),
      onCompletion: { result in
        if case let .failure(error) = result { backupExport.recordExportFailure(error) }
        if let snapshot = backupDocument?.snapshot { backupExport.discard(snapshot) }
        backupDocument = nil
      }
    )
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
      switch result {
      case let .success(url):
        Task {
          await backupRestore.prepareRestore(from: url)
          confirmingRestore = backupRestore.isPrepared
        }
      case let .failure(error): backupRestore.recordImportFailure(error)
      }
    }
    .confirmationDialog(
      "Replace this device’s library?",
      isPresented: $confirmingRestore,
      titleVisibility: .visible
    ) {
      Button("Restore and turn sync off", role: .destructive) {
        Task {
          if await backupRestore.restorePreparedBackup() {
            message = "Restore complete. Reopen Urbane before enabling sync."
          } else {
            message = backupRestore.errorMessage
          }
        }
      }
      Button("Cancel", role: .cancel) { backupRestore.discardPreparedRestore() }
    } message: {
      Text("Urbane saves an undo backup first. Sync stays off until you turn it on again.")
    }
  }

  @Dependency(\.defaultDatabase) private var currentDatabase
}

private struct UrbaneBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  let snapshot: DatabaseBackup.Snapshot

  init(snapshot: DatabaseBackup.Snapshot) { self.snapshot = snapshot }

  init(configuration: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnsupportedScheme)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: try Data(contentsOf: snapshot.fileURL))
  }
}
