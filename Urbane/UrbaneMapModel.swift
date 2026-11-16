import Dependencies
import Foundation
import Observation
import SQLiteData
import UrbaneCore
import UrbaneSchema

@MainActor
@Observable
final class UrbaneMapModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Dependency(\.placeSearch) private var placeSearch
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @FetchAll(Search.all) var searches
  @ObservationIgnored @FetchAll(Neighborhood.order(by: \.name)) var neighborhoods
  @ObservationIgnored @FetchAll(Building.order(by: \.name)) var buildings
  @ObservationIgnored @FetchAll(BuildingReview.all) var reviews

  private var didBootstrap = false
  var message: String?

  func bootstrap() {
    guard !didBootstrap else { return }
    didBootstrap = true
    withErrorReporting {
      try database.write { db in
        guard try Search.fetchAll(db).isEmpty else { return }
        try Search.insert { Search(id: uuid(), title: "Search") }.execute(db)
      }
    }
  }

  func search(_ query: String) async throws -> [PlaceMatch] { try await placeSearch.search(query) }

  func resolveSearchRow(_ query: String) async throws -> PlaceSearchRowResolution {
    try await PlaceSearchRows.resolve(query: query, using: placeSearch)
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
    withErrorReporting {
      try database.write { db in
        try Building.insert {
          Building(
            id: uuid(), neighborhoodID: neighborhoodID, name: name,
            address: address.isEmpty ? match.address : address,
            latitude: match.latitude, longitude: match.longitude,
            mapItemIdentifier: match.mapItemIdentifier,
            summary: summary, status: status, rejectionReason: rejectionReason,
            streetEasyURL: streetEasyURL, websiteURL: websiteURL
          )
        }.execute(db)
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
            Neighborhood(id: neighborhoodID, searchID: search.id, name: incoming.name, chapter: incoming.chapter ?? "", centerLatitude: place.latitude, centerLongitude: place.longitude, latitudeSpan: 0.06, longitudeSpan: 0.06, sortOrder: neighborhoods.count)
          }.execute(db)
          neighborhoods.append(Neighborhood(id: neighborhoodID, searchID: search.id, name: incoming.name, chapter: incoming.chapter ?? "", centerLatitude: place.latitude, centerLongitude: place.longitude, latitudeSpan: 0.06, longitudeSpan: 0.06, sortOrder: neighborhoods.count))
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
          buildings.append(Building(id: buildingID, neighborhoodID: neighborhoodID, name: incoming.name, address: incoming.address, latitude: place.latitude, longitude: place.longitude, mapItemIdentifier: place.mapItemIdentifier, summary: incoming.summary, status: incoming.status, rejectionReason: incoming.rejectionReason, streetEasyURL: incoming.streetEasyURL, websiteURL: incoming.website))
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
  }
  // swiftlint:enable function_body_length

  static func normalize(_ value: String) -> String {
    ChatImportReconciliation.normalizedNeighborhoodName(value)
  }
}
