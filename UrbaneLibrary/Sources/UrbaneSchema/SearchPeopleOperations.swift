import SQLiteData

public enum SearchPeopleOperations {
  public static func activeSearch(
    in searches: [Search], foreignOwnedRootIDs: Set<Search.ID>
  ) -> Search? {
    searches.first { foreignOwnedRootIDs.contains($0.id) } ?? searches.first
  }

  /// Seeds the two household members once under the search's existing root.
  @discardableResult
  public static func seedDefaults(
    searchID: Search.ID,
    jonID: Person.ID,
    wendyID: Person.ID,
    foreignOwnedRootIDs: Set<Search.ID> = [],
    in db: Database
  ) throws -> Bool {
    guard !foreignOwnedRootIDs.contains(searchID) else { return false }
    let people = try Person.fetchAll(db).filter { $0.searchID == searchID }
    if !people.contains(where: { $0.displayName == "Jon" }) {
      try Person.insert { Person(id: jonID, searchID: searchID, displayName: "Jon") }.execute(db)
    }
    if !people.contains(where: { $0.displayName == "Wendy" }) {
      try Person.insert { Person(id: wendyID, searchID: searchID, displayName: "Wendy") }.execute(db)
    }
    return true
  }

  /// Removes only a pristine, device-local root after this device accepts the shared root.
  /// A populated local graph needs an explicit recovery decision and is never merged here.
  public static func removeEmptyLocalRoots(keeping sharedSearchID: Search.ID, in db: Database) throws {
    for search in try Search.fetchAll(db) where search.id != sharedSearchID {
      let neighborhoodCount = try Neighborhood.where { $0.searchID.eq(search.id) }.fetchCount(db)
      let buildingCount = try Building
        .where { $0.neighborhoodID.in(Neighborhood.where { $0.searchID.eq(search.id) }.select(\.id)) }
        .fetchCount(db)
      guard neighborhoodCount == 0, buildingCount == 0 else {
        throw LocalSearchCleanupError.localSearchContainsData
      }
      try Search.delete().where { $0.id.eq(search.id) }.execute(db)
    }
  }
}

public enum PersonIdentityClaimResult: Equatable, Sendable {
  case claimed
  case alreadyClaimed
  case syncDisabled
  case personNotFound
  case claimedByAnotherAccount
  case accountAlreadyClaimsAnotherPerson
}

public enum PersonIdentityOperations {
  @discardableResult
  public static func claim(
    personID: Person.ID,
    accountRecordName: String,
    syncEnabled: Bool,
    in db: Database
  ) throws -> PersonIdentityClaimResult {
    guard syncEnabled else { return .syncDisabled }
    guard let person = try Person.find(personID).fetchOne(db) else { return .personNotFound }
    if person.iCloudUserRecordName == accountRecordName { return .alreadyClaimed }
    if person.iCloudUserRecordName != nil { return .claimedByAnotherAccount }

    let people = try Person.fetchAll(db).filter { $0.searchID == person.searchID }
    if people.contains(where: { $0.id != personID && $0.iCloudUserRecordName == accountRecordName }) {
      return .accountAlreadyClaimsAnotherPerson
    }
    try Person.find(personID).update { $0.iCloudUserRecordName = #bind(accountRecordName) }.execute(db)
    return .claimed
  }
}

public enum LocalSearchCleanupError: Error, Equatable {
  case localSearchContainsData
}
