import Foundation
import LLMClientKit
import SQLiteData
import UrbaneCore
import UrbaneSchema

@MainActor extension UrbaneMapModel {
  func importNeighborhoodRents(_ data: Data) {
    do {
      let points = try NeighborhoodRentCSV.parse(data)
      try database.write { db in
        let neighborhoods = try Neighborhood.fetchAll(db)
        let existing = try NeighborhoodRent.fetchAll(db)
        for point in points {
          guard let neighborhood = neighborhoods.first(where: {
            Self.normalize($0.name) == Self.normalize(point.neighborhood)
          }) else {
            throw NeighborhoodRentCSV.ImportError.unknownNeighborhood(point.neighborhood)
          }
          if let row = existing.first(where: {
            $0.neighborhoodID == neighborhood.id && $0.month == point.month
          }) {
            try NeighborhoodRent.find(row.id).update {
              $0.median2BRRent = #bind(point.median2BRRent)
              $0.sourceLabel = #bind("StreetEasy Data Dashboard")
            }.execute(db)
          } else {
            try NeighborhoodRent.insert {
              NeighborhoodRent(
                id: uuid(), neighborhoodID: neighborhood.id, month: point.month,
                median2BRRent: point.median2BRRent, sourceLabel: "StreetEasy Data Dashboard"
              )
            }.execute(db)
          }
        }
      }
      rentImportMessage = "Imported \(points.count) neighborhood rent observations."
      rentImportError = nil
    } catch {
      rentImportMessage = nil
      rentImportError = error.localizedDescription
    }
  }

  func saveRentObservations(_ candidates: [RentListingCandidate], building: Building, sourceURL: URL) {
    guard !candidates.isEmpty else { return }
    withErrorReporting {
      try database.write { db in
        for candidate in candidates {
          try RentObservation.insert {
            RentObservation(
              id: uuid(), buildingID: building.id, rent: candidate.rent,
              unit: candidate.unit, squareFeet: candidate.squareFeet,
              dateSeen: now, sourceURL: sourceURL.absoluteString
            )
          }.execute(db)
        }
      }
    }
  }

  func extractRentCandidates(from html: String, sourceURL: URL) async throws -> [RentListingCandidate] {
    try await RentListingExtractor.extract(from: html, sourceURL: sourceURL, using: modelClient)
  }

  func refreshCommutes(for building: Building) async {
    commuteError = nil
    var failures: [String] = []
    for destination in CommuteDestination.allCases {
      do {
        let seconds = try await commuteClient.transitSeconds(
          GeoCoordinate(latitude: building.latitude, longitude: building.longitude), destination.coordinate
        )
        let computedAt = now
        let newID = uuid()
        try await database.write { db in
          let existing = try Commute.fetchAll(db).first {
            $0.buildingID == building.id && $0.destination == destination
          }
          if let existing {
            try Commute.find(existing.id).update {
              $0.transitSeconds = #bind(seconds)
              $0.computedAt = #bind(computedAt)
            }.execute(db)
          } else {
            try Commute.insert {
              Commute(
                id: newID, buildingID: building.id, destination: destination,
                transitSeconds: seconds, computedAt: computedAt
              )
            }.execute(db)
          }
        }
      } catch {
        failures.append("\(destination.displayName): \(error.localizedDescription)")
      }
    }
    commuteError = failures.isEmpty ? nil : failures.joined(separator: "\n")
  }
}
