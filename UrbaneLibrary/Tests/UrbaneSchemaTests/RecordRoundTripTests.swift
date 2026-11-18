import Foundation
import SQLiteData
import Testing
import UrbaneSchema

@Test
func m1RecordsRoundTripThroughTheirTables() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)

  let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
  let search = Search(id: UUID(), title: "NYC rental", moveInTargetDate: timestamp)
  let person = Person(id: UUID(), searchID: search.id, displayName: "Jon", iCloudUserRecordName: "record")
  let neighborhood = Neighborhood(
    id: UUID(), searchID: search.id, name: "Williamsburg", chapter: "A chapter",
    centerLatitude: 40.713, centerLongitude: -73.961, latitudeSpan: 0.02, longitudeSpan: 0.03,
    sortOrder: 1
  )
  let neighborhoodRent = NeighborhoodRent(
    id: UUID(), neighborhoodID: neighborhood.id, month: "2026-11", median2BRRent: 5_400,
    sourceLabel: "StreetEasy"
  )
  let building = Building(
    id: UUID(), neighborhoodID: neighborhood.id, name: "The Oosten", address: "429 Kent Avenue",
    latitude: 40.711, longitude: -73.968, mapItemIdentifier: "building-map-item-id",
    summary: "A courtyard building.", status: .watching,
    rejectionReason: nil, streetEasyURL: "https://example.com/listings", websiteURL: "https://example.com",
    heroImage: Data([0x01, 0x02])
  )
  let neighborhoodVignette = NeighborhoodVignette(
    id: UUID(), neighborhoodID: neighborhood.id, placeName: "Domino Park", latitude: 40.714,
    longitude: -73.967, mapItemIdentifier: "park-id", caption: "Along the river.", sortOrder: 0
  )
  let buildingVignette = BuildingVignette(
    id: UUID(), buildingID: building.id, placeName: "Front door", latitude: 40.711,
    longitude: -73.968, mapItemIdentifier: "building-id", caption: "At the entrance.",
    sortOrder: 0, tuesdayPart: .dinner
  )
  let commute = Commute(
    id: UUID(), buildingID: building.id, destination: .midtown, transitSeconds: 1_200,
    computedAt: timestamp
  )
  let rentObservation = RentObservation(
    id: UUID(), buildingID: building.id, rent: 5_400, unit: "2B", squareFeet: 900,
    dateSeen: timestamp, sourceURL: "https://example.com/rent"
  )
  let reaction = Reaction(
    id: UUID(), buildingID: building.id, personID: person.id, rating: 5, isFavorite: true,
    note: "Bright and calm."
  )
  let photo = Photo(
    id: UUID(), buildingID: building.id, personID: person.id, image: Data([0xCA, 0xFE]),
    caption: "Visit photo", dateTaken: timestamp
  )
  let buildingReview = BuildingReview(
    id: UUID(), buildingID: building.id, source: "Openigloo", subject: .landlord,
    sourceURL: "https://example.com/reviews", rating: 4.2, ratingScale: 5,
    reviewCount: 19, newestReviewMonth: "2026-09", summary: "Responsive repairs.",
    gatheredAt: timestamp
  )

  try database.write { db in
    try Search.insert { Search.Draft(search) }.execute(db)
    try Person.insert { Person.Draft(person) }.execute(db)
    try Neighborhood.insert { Neighborhood.Draft(neighborhood) }.execute(db)
    try NeighborhoodRent.insert { NeighborhoodRent.Draft(neighborhoodRent) }.execute(db)
    try Building.insert { Building.Draft(building) }.execute(db)
    try NeighborhoodVignette.insert { NeighborhoodVignette.Draft(neighborhoodVignette) }.execute(db)
    try BuildingVignette.insert { BuildingVignette.Draft(buildingVignette) }.execute(db)
    try Commute.insert { Commute.Draft(commute) }.execute(db)
    try RentObservation.insert { RentObservation.Draft(rentObservation) }.execute(db)
    try Reaction.insert { Reaction.Draft(reaction) }.execute(db)
    try Photo.insert { Photo.Draft(photo) }.execute(db)
    try BuildingReview.insert { BuildingReview.Draft(buildingReview) }.execute(db)
  }

  try database.read { db in
    let savedSearch = try Search.find(search.id).fetchOne(db)
    let savedPerson = try Person.find(person.id).fetchOne(db)
    let savedNeighborhood = try Neighborhood.find(neighborhood.id).fetchOne(db)
    let savedNeighborhoodRent = try NeighborhoodRent.find(neighborhoodRent.id).fetchOne(db)
    let savedBuilding = try Building.find(building.id).fetchOne(db)
    let savedNeighborhoodVignette = try NeighborhoodVignette.find(neighborhoodVignette.id).fetchOne(db)
    let savedBuildingVignette = try BuildingVignette.find(buildingVignette.id).fetchOne(db)
    let savedCommute = try Commute.find(commute.id).fetchOne(db)
    let savedRentObservation = try RentObservation.find(rentObservation.id).fetchOne(db)
    let savedReaction = try Reaction.find(reaction.id).fetchOne(db)
    let savedPhoto = try Photo.find(photo.id).fetchOne(db)
    let savedBuildingReview = try BuildingReview.find(buildingReview.id).fetchOne(db)

    #expect(savedSearch == search)
    #expect(savedPerson == person)
    #expect(savedNeighborhood == neighborhood)
    #expect(savedNeighborhoodRent == neighborhoodRent)
    #expect(savedBuilding == building)
    #expect(savedNeighborhoodVignette == neighborhoodVignette)
    #expect(savedBuildingVignette == buildingVignette)
    #expect(savedCommute == commute)
    #expect(savedRentObservation == rentObservation)
    #expect(savedReaction == reaction)
    #expect(savedPhoto == photo)
    #expect(savedBuildingReview == buildingReview)
  }
}

@Test
func reactionUpsertUpdatesTheExistingBuildingPersonRow() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let search = Search(id: UUID())
  let person = Person(id: UUID(), searchID: search.id, displayName: "Jon")
  let neighborhood = Neighborhood(id: UUID(), searchID: search.id, name: "Williamsburg")
  let building = Building(id: UUID(), neighborhoodID: neighborhood.id, name: "The Oosten")
  try database.write { db in
    try Search.insert { search }.execute(db)
    try Person.insert { person }.execute(db)
    try Neighborhood.insert { neighborhood }.execute(db)
    try Building.insert { building }.execute(db)
    _ = try ReactionOperations.upsert(
      buildingID: building.id, personID: person.id, id: UUID(), rating: 4,
      isFavorite: true, note: "Good light", in: db
    )
  }
  let original = try database.read { db in try Reaction.fetchAll(db).first }
  #expect(original != nil)

  _ = try database.write { db in
    try ReactionOperations.upsert(
      buildingID: building.id, personID: person.id, id: UUID(), rating: 5,
      isFavorite: false, note: "Even better", in: db
    )
  }

  let rows = try database.read { db in try Reaction.fetchAll(db) }
  #expect(rows.count == 1)
  #expect(rows.first?.id == original?.id)
  #expect(rows.first?.rating == 5)
  #expect(rows.first?.isFavorite == false)
  #expect(rows.first?.note == "Even better")
}

@Test
func rejectedStatusRequiresAReasonAndLeavingRejectedClearsIt() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let search = Search(id: UUID())
  let neighborhood = Neighborhood(id: UUID(), searchID: search.id)
  let building = Building(id: UUID(), neighborhoodID: neighborhood.id)
  try database.write { db in
    try Search.insert { search }.execute(db)
    try Neighborhood.insert { neighborhood }.execute(db)
    try Building.insert { building }.execute(db)
  }

  #expect(throws: BuildingStatusError.rejectionReasonRequired) {
    try database.write { db in
      try BuildingStatusOperations.set(
        buildingID: building.id, status: .rejected, rejectionReason: "  ", in: db
      )
    }
  }
  try database.write { db in
    try BuildingStatusOperations.set(
      buildingID: building.id, status: .rejected, rejectionReason: "Too noisy", in: db
    )
  }
  try database.write { db in
    try BuildingStatusOperations.set(
      buildingID: building.id, status: .watching, rejectionReason: "ignored", in: db
    )
  }
  let updated = try database.read { db in try Building.find(building.id).fetchOne(db) }
  #expect(updated?.status == .watching)
  #expect(updated?.rejectionReason == nil)
}

@Test
func defaultPeopleAreSeededOnceForTheSearch() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let search = Search(id: UUID())
  try database.write { db in
    try Search.insert { search }.execute(db)
    try SearchPeopleOperations.seedDefaults(
      searchID: search.id, jonID: UUID(), wendyID: UUID(), in: db
    )
    try SearchPeopleOperations.seedDefaults(
      searchID: search.id, jonID: UUID(), wendyID: UUID(), in: db
    )
  }
  let people = try database.read { db in try Person.fetchAll(db) }
  #expect(Set(people.map(\.displayName)) == ["Jon", "Wendy"])
  #expect(people.count == 2)
}

@Test
func foreignRootIsActiveAndNeverGetsDefaultPeopleSeeded() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let local = Search(id: UUID(), title: "Local")
  let foreign = Search(id: UUID(), title: "Jon’s shared search")
  let foreignIDs: Set<Search.ID> = [foreign.id]
  try database.write { db in
    try Search.insert { Search.Draft(local) }.execute(db)
    try Search.insert { Search.Draft(foreign) }.execute(db)
    #expect(SearchPeopleOperations.activeSearch(in: [local, foreign], foreignOwnedRootIDs: foreignIDs) == foreign)
    let seededForeignRoot = try SearchPeopleOperations.seedDefaults(
      searchID: foreign.id, jonID: UUID(), wendyID: UUID(), foreignOwnedRootIDs: foreignIDs, in: db
    )
    #expect(seededForeignRoot == false)
    let seededLocalRoot = try SearchPeopleOperations.seedDefaults(
      searchID: local.id, jonID: UUID(), wendyID: UUID(), foreignOwnedRootIDs: foreignIDs, in: db
    )
    #expect(seededLocalRoot)
  }
  let people = try database.read { db in try Person.fetchAll(db) }
  #expect(people.count == 2)
  #expect(people.allSatisfy { $0.searchID == local.id })
}

@Test
func anICloudAccountCannotClaimTwoPeopleAndClaimsRequireSync() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let search = Search(id: UUID())
  let jon = Person(id: UUID(), searchID: search.id, displayName: "Jon")
  let wendy = Person(id: UUID(), searchID: search.id, displayName: "Wendy")
  try database.write { db in
    try Search.insert { Search.Draft(search) }.execute(db)
    try Person.insert { Person.Draft(jon) }.execute(db)
    try Person.insert { Person.Draft(wendy) }.execute(db)
  }

  try database.write { db in
    let disabledClaim = try PersonIdentityOperations.claim(
      personID: jon.id, accountRecordName: "jon-account", syncEnabled: false, in: db
    )
    let firstClaim = try PersonIdentityOperations.claim(
      personID: jon.id, accountRecordName: "jon-account", syncEnabled: true, in: db
    )
    let duplicateClaim = try PersonIdentityOperations.claim(
      personID: wendy.id, accountRecordName: "jon-account", syncEnabled: true, in: db
    )
    #expect(disabledClaim == .syncDisabled)
    #expect(firstClaim == .claimed)
    #expect(duplicateClaim == .accountAlreadyClaimsAnotherPerson)
  }
  let people = try database.read { db in try Person.fetchAll(db) }
  #expect(people.first(where: { $0.id == jon.id })?.iCloudUserRecordName == "jon-account")
  #expect(people.first(where: { $0.id == wendy.id })?.iCloudUserRecordName == nil)
}

@Test
func acceptingSharedSearchRemovesOnlyAnEmptyLocalRoot() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let shared = Search(id: UUID(), title: "Shared")
  let local = Search(id: UUID(), title: "Local")
  try database.write { db in
    try Search.insert { Search.Draft(shared) }.execute(db)
    try Search.insert { Search.Draft(local) }.execute(db)
    try SearchPeopleOperations.seedDefaults(searchID: local.id, jonID: UUID(), wendyID: UUID(), in: db)
    try SearchPeopleOperations.removeEmptyLocalRoots(keeping: shared.id, in: db)
  }
  let searches = try database.read { db in try Search.fetchAll(db) }
  #expect(searches == [shared])
  #expect(try database.read { db in try Person.fetchAll(db) }.isEmpty)
}

@Test
func acceptingSharedSearchRefusesToDeleteALocalSearchWithNeighborhoods() throws {
  let database = try DatabaseQueue()
  try UrbaneDatabaseMigrations.makeMigrator().migrate(database)
  let shared = Search(id: UUID(), title: "Shared")
  let local = Search(id: UUID(), title: "Local")
  let neighborhood = Neighborhood(id: UUID(), searchID: local.id, name: "Williamsburg")
  try database.write { db in
    try Search.insert { Search.Draft(shared) }.execute(db)
    try Search.insert { Search.Draft(local) }.execute(db)
    try Neighborhood.insert { Neighborhood.Draft(neighborhood) }.execute(db)
  }
  #expect(throws: LocalSearchCleanupError.localSearchContainsData) {
    try database.write { db in
      try SearchPeopleOperations.removeEmptyLocalRoots(keeping: shared.id, in: db)
    }
  }
  #expect(try database.read { db in try Search.find(local.id).fetchOne(db) } == local)
}
