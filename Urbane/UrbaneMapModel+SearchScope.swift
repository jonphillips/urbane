import UrbaneSchema

extension UrbaneMapModel {
  var searches: [Search] { allSearches }

  var activeSearch: Search? {
    SearchPeopleOperations.activeSearch(in: allSearches, foreignOwnedRootIDs: foreignOwnedSearchIDs)
  }

  var people: [Person] {
    guard let searchID = activeSearch?.id else { return [] }
    return allPeople.filter { $0.searchID == searchID }
  }

  var neighborhoods: [Neighborhood] {
    guard let searchID = activeSearch?.id else { return [] }
    return allNeighborhoods.filter { $0.searchID == searchID }
  }

  var buildings: [Building] {
    let neighborhoodIDs = Set(neighborhoods.map(\.id))
    return allBuildings.filter { neighborhoodIDs.contains($0.neighborhoodID) }
  }

  var reactions: [Reaction] {
    let buildingIDs = Set(buildings.map(\.id))
    return allReactions.filter { buildingIDs.contains($0.buildingID) }
  }

  var neighborhoodVignettes: [NeighborhoodVignette] {
    let neighborhoodIDs = Set(neighborhoods.map(\.id))
    return allNeighborhoodVignettes.filter { neighborhoodIDs.contains($0.neighborhoodID) }
  }

  var buildingVignettes: [BuildingVignette] {
    let buildingIDs = Set(buildings.map(\.id))
    return allBuildingVignettes.filter { buildingIDs.contains($0.buildingID) }
  }

  var reviews: [BuildingReview] {
    let buildingIDs = Set(buildings.map(\.id))
    return allReviews.filter { buildingIDs.contains($0.buildingID) }
  }

  var neighborhoodRents: [NeighborhoodRent] {
    let neighborhoodIDs = Set(neighborhoods.map(\.id))
    return allNeighborhoodRents.filter { neighborhoodIDs.contains($0.neighborhoodID) }
  }

  var rentObservations: [RentObservation] {
    let buildingIDs = Set(buildings.map(\.id))
    return allRentObservations.filter { buildingIDs.contains($0.buildingID) }
  }

  var commutes: [Commute] {
    let buildingIDs = Set(buildings.map(\.id))
    return allCommutes.filter { buildingIDs.contains($0.buildingID) }
  }

  func refreshSearchOwnership() async {
    foreignOwnedSearchIDs = (try? await database.read { db in
      try UrbaneCloudSync.foreignOwnedSearchIDs(in: db)
    }) ?? []
  }
}
