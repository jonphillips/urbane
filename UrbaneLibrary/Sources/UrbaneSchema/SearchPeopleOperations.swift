import SQLiteData

public enum SearchPeopleOperations {
  public static func activeSearch(
    in searches: [Search], sharedSearch: Search?, preferredID: Search.ID?
  ) -> Search? {
    sharedSearch ?? preferredID.flatMap { id in searches.first { $0.id == id } } ?? searches.first
  }

  /// Seeds the two household members once under the search's existing root.
  public static func seedDefaults(
    searchID: Search.ID,
    jonID: Person.ID,
    wendyID: Person.ID,
    in db: Database
  ) throws {
    let people = try Person.fetchAll(db).filter { $0.searchID == searchID }
    if !people.contains(where: { $0.displayName == "Jon" }) {
      try Person.insert { Person(id: jonID, searchID: searchID, displayName: "Jon") }.execute(db)
    }
    if !people.contains(where: { $0.displayName == "Wendy" }) {
      try Person.insert { Person(id: wendyID, searchID: searchID, displayName: "Wendy") }.execute(db)
    }
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

public enum LocalSearchCleanupError: Error, Equatable {
  case localSearchContainsData
}
