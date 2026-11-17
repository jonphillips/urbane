import Foundation
import SQLiteData

public enum ReactionOperations {
  /// Keeps one stable row for each building/person pair and updates it in place.
  @discardableResult
  public static func upsert(
    buildingID: Building.ID,
    personID: Person.ID,
    id: UUID,
    rating: Int?,
    isFavorite: Bool,
    note: String,
    in db: Database
  ) throws -> Reaction {
    let matches = try Reaction.fetchAll(db)
      .filter { $0.buildingID == buildingID && $0.personID == personID }
      .sorted { $0.id.uuidString < $1.id.uuidString }
    let row = Reaction(
      id: matches.first?.id ?? id,
      buildingID: buildingID,
      personID: personID,
      rating: rating,
      isFavorite: isFavorite,
      note: note
    )
    if let survivor = matches.first {
      try Reaction.find(survivor.id).update {
        $0.rating = #bind(rating)
        $0.isFavorite = #bind(isFavorite)
        $0.note = #bind(note)
      }.execute(db)
      for duplicate in matches.dropFirst() {
        try Reaction.find(duplicate.id).delete().execute(db)
      }
    } else {
      try Reaction.insert { row }.execute(db)
    }
    return row
  }
}

public enum BuildingStatusError: Error, Equatable {
  case rejectionReasonRequired
}

public enum BuildingStatusOperations {
  public static func set(
    buildingID: Building.ID,
    status: BuildingStatus,
    rejectionReason: String,
    in db: Database
  ) throws {
    let trimmedReason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard status != .rejected || !trimmedReason.isEmpty else {
      throw BuildingStatusError.rejectionReasonRequired
    }
    try Building.find(buildingID).update {
      $0.status = #bind(status)
      $0.rejectionReason = #bind(status == .rejected ? trimmedReason : nil)
    }.execute(db)
  }
}
