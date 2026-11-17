import Dependencies
import Foundation
import LLMClientKit
import Observation
import SQLiteData
import UrbaneCore
import UrbaneSchema

@MainActor
@Observable
final class UrbaneMapModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) var database
  @ObservationIgnored @Dependency(\.uuid) var uuid
  @ObservationIgnored @Dependency(\.placeSearch) private var placeSearch
  @ObservationIgnored @Dependency(\.date.now) var now
  @ObservationIgnored @Dependency(\.commuteClient) var commuteClient
  @ObservationIgnored @Dependency(\.transitDirectionsClient) var transitDirectionsClient
  @ObservationIgnored @Dependency(\.modelClient) var modelClient
  @ObservationIgnored @FetchAll(Search.all) var searches
  @ObservationIgnored @FetchAll(Neighborhood.order(by: \.name)) var neighborhoods
  @ObservationIgnored @FetchAll(Building.order(by: \.name)) var buildings
  @ObservationIgnored @FetchAll(NeighborhoodVignette.all) var neighborhoodVignettes
  @ObservationIgnored @FetchAll(BuildingVignette.all) var buildingVignettes
  @ObservationIgnored @FetchAll(BuildingReview.all) var reviews
  @ObservationIgnored @FetchAll(NeighborhoodRent.all) var neighborhoodRents
  @ObservationIgnored @FetchAll(RentObservation.all) var rentObservations
  @ObservationIgnored @FetchAll(Commute.all) var commutes

  private var didBootstrap = false
  var message: String?
  var placeSearchWaitingFor: Duration?
  var rentImportMessage: String?
  var rentImportError: String?
  var commuteErrors: [UUID: String] = [:]
  var commuteBuildingsInProgress: Set<UUID> = []
  var currentDate: Date { now }

  func openTransitDirections(for building: Building, to destination: CommuteDestination) {
    Task { await transitDirectionsClient.open(building, destination) }
  }

  func isRentObservationStale(_ observation: RentObservation) -> Bool {
    let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: now) ?? now
    return observation.dateSeen < cutoff
  }

  func bootstrap() {
    guard !didBootstrap else { return }
    didBootstrap = true
    withErrorReporting {
      try database.write { db in
        guard try Search.fetchAll(db).isEmpty else { return }
        try Search.insert { Search(id: uuid(), title: "Search") }.execute(db)
      }
    }
    Task { await refreshMissingCommutes() }
  }

  func search(_ query: String) async throws -> [PlaceMatch] {
    try await placeSearch.search(query) { [weak self] duration in
      await MainActor.run { self?.placeSearchWaitingFor = duration }
    }
  }

  func resolveSearchRow(_ query: String) async throws -> PlaceSearchRowResolution {
    try await PlaceSearchRows.resolve(query: query, using: placeSearch) { [weak self] duration in
      await MainActor.run { self?.placeSearchWaitingFor = duration }
    }
  }

  func addNeighborhood(name: String, match: PlaceMatch, latitudeSpan: Double, longitudeSpan: Double) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let search = searches.first else { return }
    withErrorReporting {
      try database.write { db in
        try Neighborhood.insert {
          Neighborhood(
            id: uuid(), searchID: search.id, name: trimmed,
            centerLatitude: match.latitude, centerLongitude: match.longitude,
            latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan,
            sortOrder: neighborhoods.count
          )
        }.execute(db)
      }
    }
  }

  func addBuilding(
    neighborhoodID: UUID, name: String, address: String, summary: String = "",
    status: BuildingStatus = .exploring, rejectionReason: String? = nil,
    match: PlaceMatch, streetEasyURL: String? = nil, websiteURL: String? = nil
  ) {
    let addedBuilding = Building(
      id: uuid(), neighborhoodID: neighborhoodID, name: name,
      address: address.isEmpty ? match.address : address,
      latitude: match.latitude, longitude: match.longitude,
      mapItemIdentifier: match.mapItemIdentifier,
      summary: summary, status: status, rejectionReason: rejectionReason,
      streetEasyURL: streetEasyURL, websiteURL: websiteURL
    )
    withErrorReporting {
      try database.write { db in
        try Building.insert {
          addedBuilding
        }.execute(db)
      }
    }
    Task { await refreshCommutes(for: addedBuilding, onlyMissing: true) }
  }

  func updateNeighborhoodChapter(_ neighborhood: Neighborhood, chapter: String) {
    withErrorReporting {
      try database.write { db in
        try Neighborhood.find(neighborhood.id).update { $0.chapter = #bind(chapter) }.execute(db)
      }
    }
  }

  func updateNeighborhoodRegion(
    _ neighborhood: Neighborhood, latitude: Double, longitude: Double,
    latitudeSpan: Double, longitudeSpan: Double
  ) {
    withErrorReporting {
      try database.write { db in
        try Neighborhood.find(neighborhood.id).update {
          $0.centerLatitude = #bind(latitude)
          $0.centerLongitude = #bind(longitude)
          $0.latitudeSpan = #bind(latitudeSpan)
          $0.longitudeSpan = #bind(longitudeSpan)
        }.execute(db)
      }
    }
  }

  @discardableResult
  func addBuildingVignette(building: Building, place: PlaceMatch, caption: String) -> UUID {
    let id = uuid()
    withErrorReporting {
      try database.write { db in
        try BuildingVignette.insert {
          BuildingVignette(
            id: id, buildingID: building.id, placeName: place.name,
            latitude: place.latitude, longitude: place.longitude,
            mapItemIdentifier: place.mapItemIdentifier, caption: caption,
            sortOrder: buildingVignettes.filter { $0.buildingID == building.id }.count
          )
        }.execute(db)
      }
    }
    return id
  }

  func updateBuildingVignette(_ vignette: BuildingVignette, place: PlaceMatch, caption: String) {
    withErrorReporting {
      try database.write { db in
        try BuildingVignette.find(vignette.id).update {
          $0.placeName = #bind(place.name)
          $0.latitude = #bind(place.latitude)
          $0.longitude = #bind(place.longitude)
          $0.mapItemIdentifier = #bind(place.mapItemIdentifier)
          $0.caption = #bind(caption)
        }.execute(db)
      }
    }
  }

  func deleteBuildingVignette(_ vignette: BuildingVignette) {
    withErrorReporting {
      try database.write { db in
        try BuildingVignette.find(vignette.id).delete().execute(db)
        let remaining = buildingVignettes
          .filter { $0.buildingID == vignette.buildingID && $0.id != vignette.id }
          .sorted { $0.sortOrder < $1.sortOrder }
        for (index, row) in remaining.enumerated() {
          try BuildingVignette.find(row.id).update { $0.sortOrder = #bind(index) }.execute(db)
        }
      }
    }
  }

  func deleteBuildingReview(_ review: BuildingReview) {
    withErrorReporting {
      try database.write { db in
        try BuildingReview.find(review.id).delete().execute(db)
      }
    }
  }

  func moveBuildingVignettes(buildingID: UUID, from source: IndexSet, to destination: Int) {
    var rows = buildingVignettes.filter { $0.buildingID == buildingID }.sorted { $0.sortOrder < $1.sortOrder }
    let moving = source.map { rows[$0] }
    rows = rows.enumerated().filter { !source.contains($0.offset) }.map(\.element)
    let adjustedDestination = destination - source.filter { $0 < destination }.count
    rows.insert(contentsOf: moving, at: adjustedDestination)
    withErrorReporting {
      try database.write { db in
        for (index, row) in rows.enumerated() {
          try BuildingVignette.find(row.id).update { $0.sortOrder = #bind(index) }.execute(db)
        }
      }
    }
  }

  func updateHeroImage(_ building: Building, image: Data) {
    withErrorReporting {
      try database.write { db in
        try Building.find(building.id).update { $0.heroImage = #bind(image) }.execute(db)
      }
    }
  }

  func fixLocation(_ building: Building, match: PlaceMatch) {
    withErrorReporting {
      try database.write { db in
        try Building.find(building.id).update {
          $0.latitude = #bind(match.latitude)
          $0.longitude = #bind(match.longitude)
          $0.mapItemIdentifier = #bind(match.mapItemIdentifier)
          if !match.address.isEmpty { $0.address = #bind(match.address) }
        }.execute(db)
      }
    }
  }

  // One transaction intentionally scopes neighborhood, building, vignette, and review writes together.
  // swiftlint:disable function_body_length
  func importPaste(
    _ paste: ChatImportPaste,
    resolutions: [String: PlaceMatch],
    skipped: Set<String>,
    replaceChapters: Set<Int>,
    replaceReviews: Set<String>
  ) throws {
    guard let search = searches.first else { throw ChatImportError.invalidPaste("The Search row is not ready yet.") }
    var importedBuildings: [Building] = []
    try database.write { db in
      var neighborhoods = try Neighborhood.fetchAll(db)
      var buildings = try Building.fetchAll(db)
      var reviews = try BuildingReview.fetchAll(db)
      let vignetteRows = try NeighborhoodVignette.fetchAll(db)
      var neighborhoodIDs: [String: UUID] = [:]

      for (index, incoming) in paste.neighborhoods.enumerated() {
        guard let place = resolutions["n\(index)"] else {
          if skipped.contains("n\(index)") { continue }
          throw ChatImportError.invalidRow(path: "neighborhoods[\(index)]", reason: "unresolved place")
        }
        let existing = neighborhoods.first { Self.normalize($0.name) == Self.normalize(incoming.name) }
        let neighborhoodID = existing?.id ?? uuid()
        neighborhoodIDs[Self.normalize(incoming.name)] = neighborhoodID
        if let existing {
          if (existing.chapter.isEmpty || replaceChapters.contains(index)), let chapter = incoming.chapter, !chapter.isEmpty {
            try Neighborhood.find(existing.id).update { $0.chapter = #bind(chapter) }.execute(db)
          }
        } else {
          try Neighborhood.insert {
            Neighborhood(id: neighborhoodID, searchID: search.id, name: incoming.name, chapter: incoming.chapter ?? "", centerLatitude: place.latitude, centerLongitude: place.longitude, latitudeSpan: 0.02, longitudeSpan: 0.02, sortOrder: neighborhoods.count)
          }.execute(db)
          neighborhoods.append(Neighborhood(id: neighborhoodID, searchID: search.id, name: incoming.name, chapter: incoming.chapter ?? "", centerLatitude: place.latitude, centerLongitude: place.longitude, latitudeSpan: 0.02, longitudeSpan: 0.02, sortOrder: neighborhoods.count))
        }
        for (vIndex, vignette) in incoming.vignettes.enumerated() {
          guard let vignettePlace = resolutions["n\(index)v\(vIndex)"] else {
            if skipped.contains("n\(index)v\(vIndex)") { continue }
            throw ChatImportError.invalidRow(path: "neighborhoods[\(index)].vignettes[\(vIndex)]", reason: "unresolved place")
          }
          guard !vignetteRows.contains(where: { $0.neighborhoodID == neighborhoodID && Self.normalize($0.placeName) == Self.normalize(vignette.place) }) else { continue }
          try NeighborhoodVignette.insert {
            NeighborhoodVignette(id: uuid(), neighborhoodID: neighborhoodID, placeName: vignette.place, latitude: vignettePlace.latitude, longitude: vignettePlace.longitude, mapItemIdentifier: vignettePlace.mapItemIdentifier, caption: vignette.caption, sortOrder: vIndex)
          }.execute(db)
        }
      }

      for (index, incoming) in paste.buildings.enumerated() {
        guard let place = resolutions["b\(index)"] else {
          if skipped.contains("b\(index)") { continue }
          throw ChatImportError.invalidRow(path: "buildings[\(index)]", reason: "unresolved place")
        }
        guard let neighborhoodID = neighborhoodIDs[Self.normalize(incoming.neighborhood)] ?? neighborhoods.first(where: { Self.normalize($0.name) == Self.normalize(incoming.neighborhood) })?.id else {
          throw ChatImportError.invalidRow(path: "buildings[\(index)]", reason: "neighborhood is unresolved")
        }
        let existing = ChatImportReconciliation.matchingBuilding(
          mapItemIdentifier: place.mapItemIdentifier, address: incoming.address, among: buildings
        )
        let buildingID = existing?.id ?? uuid()
        if let existing {
          let fill = ChatImportReconciliation.fillEmptyFields(
            of: existing, from: incoming, mapItemIdentifier: place.mapItemIdentifier
          )
          try Building.find(existing.id).update {
            if let value = fill.summary { $0.summary = #bind(value) }
            if let value = fill.mapItemIdentifier { $0.mapItemIdentifier = #bind(value) }
            if let value = fill.streetEasyURL { $0.streetEasyURL = #bind(value) }
            if let value = fill.websiteURL { $0.websiteURL = #bind(value) }
            if let value = fill.rejectionReason { $0.rejectionReason = #bind(value) }
          }.execute(db)
        } else {
          try Building.insert {
            Building(id: buildingID, neighborhoodID: neighborhoodID, name: incoming.name, address: incoming.address, latitude: place.latitude, longitude: place.longitude, mapItemIdentifier: place.mapItemIdentifier, summary: incoming.summary, status: incoming.status, rejectionReason: incoming.rejectionReason, streetEasyURL: incoming.streetEasyURL, websiteURL: incoming.website)
          }.execute(db)
          let inserted = Building(id: buildingID, neighborhoodID: neighborhoodID, name: incoming.name, address: incoming.address, latitude: place.latitude, longitude: place.longitude, mapItemIdentifier: place.mapItemIdentifier, summary: incoming.summary, status: incoming.status, rejectionReason: incoming.rejectionReason, streetEasyURL: incoming.streetEasyURL, websiteURL: incoming.website)
          buildings.append(inserted)
          importedBuildings.append(inserted)
        }
        for (rIndex, review) in incoming.reviews.enumerated() {
          let subject: BuildingReviewSubject = review.subject == .building ? .building : .landlord
          let key = "b\(index)r\(rIndex)"
          let old = ChatImportReconciliation.matchingReview(buildingID: buildingID, source: review.source, subject: subject, among: reviews)
          guard ChatImportReconciliation.shouldReplaceReview(existing: old, replaceExisting: replaceReviews.contains(key)) else { continue }
          if let old {
            try BuildingReview.find(old.id).update {
              $0.sourceURL = #bind(review.sourceURL); $0.rating = #bind(review.rating); $0.ratingScale = #bind(review.ratingScale)
              $0.reviewCount = #bind(review.reviewCount); $0.newestReviewMonth = #bind(review.newestReviewMonth)
              $0.summary = #bind(review.summary); $0.gatheredAt = #bind(now)
            }.execute(db)
          } else {
            let newReview = BuildingReview(id: uuid(), buildingID: buildingID, source: review.source, subject: subject, sourceURL: review.sourceURL, rating: review.rating, ratingScale: review.ratingScale, reviewCount: review.reviewCount, newestReviewMonth: review.newestReviewMonth, summary: review.summary, gatheredAt: now)
            try BuildingReview.insert {
              newReview
            }.execute(db)
            reviews.append(newReview)
          }
        }
      }
    }
    let buildingsToCheck = buildings + importedBuildings
    Task { await refreshMissingCommutes(for: buildingsToCheck) }
  }
  // swiftlint:enable function_body_length

  static func normalize(_ value: String) -> String {
    ChatImportReconciliation.normalizedNeighborhoodName(value)
  }
}
