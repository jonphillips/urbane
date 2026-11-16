import SQLiteData
import Testing
import UrbaneSchema

@Test
func m1MigrationCreatesEveryTable() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)

  let expectedTables = [
    "searches", "people", "neighborhoods", "neighborhoodRents", "buildings",
    "neighborhoodVignettes", "buildingVignettes", "commutes", "rentObservations",
    "reactions", "photos",
  ]
  try database.read { db in
    for table in expectedTables {
      let exists = try db.tableExists(table)
      #expect(exists)
    }
    let buildingColumns = try db.columns(in: "buildings").map(\.name)
    #expect(buildingColumns.contains("summary"))
  }
}
