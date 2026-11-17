import SQLiteData

public enum SearchPeopleOperations {
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
}
