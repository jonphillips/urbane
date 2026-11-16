import SQLiteData

public enum UrbaneDatabaseMigrations {
  public static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create M1 search graph") { db in
      for statement in statements {
        try db.execute(sql: statement)
      }
    }
    return migrator
  }

  private static let statements = [
    """
    CREATE TABLE "searches" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "title" TEXT NOT NULL DEFAULT '', "moveInTargetDate" TEXT
    ) STRICT
    """,
    """
    CREATE TABLE "people" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "searchID" TEXT NOT NULL REFERENCES "searches"("id") ON DELETE CASCADE,
      "displayName" TEXT NOT NULL DEFAULT '', "iCloudUserRecordName" TEXT
    ) STRICT
    """,
    "CREATE INDEX index_people_on_searchID ON people(searchID)",
    """
    CREATE TABLE "neighborhoods" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "searchID" TEXT NOT NULL REFERENCES "searches"("id") ON DELETE CASCADE,
      "name" TEXT NOT NULL DEFAULT '', "chapter" TEXT NOT NULL DEFAULT '',
      "centerLatitude" REAL NOT NULL DEFAULT 0, "centerLongitude" REAL NOT NULL DEFAULT 0,
      "latitudeSpan" REAL NOT NULL DEFAULT 0, "longitudeSpan" REAL NOT NULL DEFAULT 0,
      "sortOrder" INTEGER NOT NULL DEFAULT 0
    ) STRICT
    """,
    "CREATE INDEX index_neighborhoods_on_searchID ON neighborhoods(searchID)",
    """
    CREATE TABLE "neighborhoodRents" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "neighborhoodID" TEXT NOT NULL REFERENCES "neighborhoods"("id") ON DELETE CASCADE,
      "month" TEXT NOT NULL DEFAULT '', "median2BRRent" REAL NOT NULL DEFAULT 0,
      "sourceLabel" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """,
    "CREATE INDEX index_neighborhoodRents_on_neighborhoodID ON neighborhoodRents(neighborhoodID)",
    """
    CREATE TABLE "buildings" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "neighborhoodID" TEXT NOT NULL REFERENCES "neighborhoods"("id") ON DELETE CASCADE,
      "name" TEXT NOT NULL DEFAULT '', "address" TEXT NOT NULL DEFAULT '',
      "latitude" REAL NOT NULL DEFAULT 0, "longitude" REAL NOT NULL DEFAULT 0,
      "summary" TEXT NOT NULL DEFAULT '', "status" INTEGER NOT NULL DEFAULT 0,
      "rejectionReason" TEXT, "streetEasyURL" TEXT, "websiteURL" TEXT, "heroImage" BLOB
    ) STRICT
    """,
    "CREATE INDEX index_buildings_on_neighborhoodID ON buildings(neighborhoodID)",
    """
    CREATE TABLE "neighborhoodVignettes" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "neighborhoodID" TEXT NOT NULL REFERENCES "neighborhoods"("id") ON DELETE CASCADE,
      "placeName" TEXT NOT NULL DEFAULT '', "latitude" REAL NOT NULL DEFAULT 0,
      "longitude" REAL NOT NULL DEFAULT 0, "mapItemIdentifier" TEXT,
      "caption" TEXT NOT NULL DEFAULT '', "sortOrder" INTEGER NOT NULL DEFAULT 0
    ) STRICT
    """,
    "CREATE INDEX index_neighborhoodVignettes_on_neighborhoodID ON neighborhoodVignettes(neighborhoodID)",
    """
    CREATE TABLE "buildingVignettes" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "buildingID" TEXT NOT NULL REFERENCES "buildings"("id") ON DELETE CASCADE,
      "placeName" TEXT NOT NULL DEFAULT '', "latitude" REAL NOT NULL DEFAULT 0,
      "longitude" REAL NOT NULL DEFAULT 0, "mapItemIdentifier" TEXT,
      "caption" TEXT NOT NULL DEFAULT '', "sortOrder" INTEGER NOT NULL DEFAULT 0,
      "tuesdayPart" INTEGER
    ) STRICT
    """,
    "CREATE INDEX index_buildingVignettes_on_buildingID ON buildingVignettes(buildingID)",
    """
    CREATE TABLE "commutes" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "buildingID" TEXT NOT NULL REFERENCES "buildings"("id") ON DELETE CASCADE,
      "destination" INTEGER NOT NULL, "transitSeconds" INTEGER NOT NULL DEFAULT 0,
      "computedAt" TEXT NOT NULL
    ) STRICT
    """,
    "CREATE INDEX index_commutes_on_buildingID ON commutes(buildingID)",
    """
    CREATE TABLE "rentObservations" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "buildingID" TEXT NOT NULL REFERENCES "buildings"("id") ON DELETE CASCADE,
      "rent" INTEGER NOT NULL DEFAULT 0, "unit" TEXT, "squareFeet" REAL,
      "dateSeen" TEXT NOT NULL, "sourceURL" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """,
    "CREATE INDEX index_rentObservations_on_buildingID ON rentObservations(buildingID)",
    """
    CREATE TABLE "reactions" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "buildingID" TEXT NOT NULL REFERENCES "buildings"("id") ON DELETE CASCADE,
      "personID" TEXT NOT NULL, "rating" INTEGER, "isFavorite" INTEGER NOT NULL DEFAULT 0,
      "note" TEXT NOT NULL DEFAULT ''
    ) STRICT
    """,
    "CREATE INDEX index_reactions_on_buildingID ON reactions(buildingID)",
    """
    CREATE TABLE "photos" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "buildingID" TEXT NOT NULL REFERENCES "buildings"("id") ON DELETE CASCADE,
      "personID" TEXT NOT NULL, "image" BLOB NOT NULL, "caption" TEXT NOT NULL DEFAULT '',
      "dateTaken" TEXT NOT NULL
    ) STRICT
    """,
    "CREATE INDEX index_photos_on_buildingID ON photos(buildingID)",
  ]
}
