import Foundation
import LLMClientKit
import SQLiteData
import UrbaneCore
import UrbaneSchema

@MainActor extension UrbaneMapModel {
  func importNeighborhoodRents(_ data: Data) {
    do {
      let dataset = try NeighborhoodRentCSV.parse(data)
      let plan = StreetEasyNeighborhoodAliases.plan(
        neighborhoods: neighborhoods.map(\.name), points: dataset.points, areaNames: dataset.areaNames
      )
      try database.write { db in
        let activeNeighborhoodIDs = Set(neighborhoods.map(\.id))
        let storedNeighborhoods = try Neighborhood.fetchAll(db).filter { activeNeighborhoodIDs.contains($0.id) }
        let existing = try NeighborhoodRent.fetchAll(db).filter { activeNeighborhoodIDs.contains($0.neighborhoodID) }
        for match in plan.matches {
          guard let neighborhood = storedNeighborhoods.first(where: {
            Self.normalize($0.name) == Self.normalize(match.neighborhood)
          }) else { continue }
          for point in match.points {
            if let row = existing.first(where: {
              $0.neighborhoodID == neighborhood.id && $0.month == point.month
            }) {
              try NeighborhoodRent.find(row.id).update {
                $0.median2BRRent = #bind(point.median2BRRent)
                $0.sourceLabel = #bind("StreetEasy")
              }.execute(db)
            } else {
              try NeighborhoodRent.insert {
                NeighborhoodRent(
                  id: uuid(), neighborhoodID: neighborhood.id, month: point.month,
                  median2BRRent: point.median2BRRent, sourceLabel: "StreetEasy"
                )
              }.execute(db)
            }
          }
        }
      }
      let importedCount = plan.matches.reduce(0) { $0 + $1.points.count }
      let missing = plan.missingNeighborhoods.isEmpty
        ? ""
        : " No StreetEasy area for: \(plan.missingNeighborhoods.joined(separator: ", "))."
      rentImportMessage = "Imported \(importedCount) neighborhood rent observations.\(missing)"
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

  func extractRentCandidates(from html: String, sourceURL: URL) async throws -> RentListingExtraction {
    try await RentListingExtractor.extract(from: html, sourceURL: sourceURL, using: modelClient)
  }

  func refreshCommutes(for building: Building) async {
    await refreshCommutes(for: building, onlyMissing: false)
  }

  func refreshMissingCommutes(for candidates: [Building]? = nil) async {
    var seen = Set<UUID>()
    let buildingsToCheck = (candidates ?? buildings).filter { seen.insert($0.id).inserted }
    for building in buildingsToCheck {
      let existing = Set(commutes.filter { $0.buildingID == building.id }.map(\.destination))
      guard existing.count < CommuteDestination.allCases.count else { continue }
      await refreshCommutes(for: building, onlyMissing: true)
    }
  }

  func refreshCommutes(for building: Building, onlyMissing: Bool) async {
    guard commuteBuildingsInProgress.insert(building.id).inserted else { return }
    defer { commuteBuildingsInProgress.remove(building.id) }
    commuteErrors[building.id] = nil
    let storedCommutes = onlyMissing
      ? ((try? await database.read { db in try Commute.fetchAll(db) }) ?? commutes)
      : commutes
    let existingDestinations = Set(storedCommutes.filter { $0.buildingID == building.id }.map(\.destination))
    let destinations = CommuteDestination.allCases.filter {
      !onlyMissing || !existingDestinations.contains($0)
    }
    var failures: [String] = []
    for destination in destinations {
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
    if !failures.isEmpty { commuteErrors[building.id] = failures.joined(separator: "\n") }
  }
}
