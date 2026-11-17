import Dependencies
import Foundation
import LLMClientKit
import Testing
import UrbaneSchema

@testable import UrbaneCore

@Suite struct RentNumbersTests {
  @Test func parsesNeighborhoodCSVAndQuotedNames() throws {
    let csv = """
      Neighborhood,Month,Median 2BR Rent
      "Hell's Kitchen",2026-10,"$5,400"
      "West Village",2026-10,6100
      """
    let rows = try NeighborhoodRentCSV.parse(Data(csv.utf8))
    #expect(rows == [
      NeighborhoodRentPoint(neighborhood: "Hell's Kitchen", month: "2026-10", median2BRRent: 5_400),
      NeighborhoodRentPoint(neighborhood: "West Village", month: "2026-10", median2BRRent: 6_100),
    ])
  }

  @Test func unknownCSVHeaderFailsLoudly() {
    let csv = "Neighborhood,Month,Median 2BR Rent,Notes\nSoho,2026-10,5400,extra\n"
    #expect(throws: NeighborhoodRentCSV.ImportError.unknownHeader("notes")) {
      try NeighborhoodRentCSV.parse(Data(csv.utf8))
    }
  }

  @Test func invalidCSVMonthAndRentFailLoudly() {
    #expect(throws: NeighborhoodRentCSV.ImportError.invalidMonth(2)) {
      try NeighborhoodRentCSV.parse(Data("Neighborhood,Month,Median 2BR Rent\nSoho,October,5400\n".utf8))
    }
    #expect(throws: NeighborhoodRentCSV.ImportError.invalidRent(2)) {
      try NeighborhoodRentCSV.parse(Data("Neighborhood,Month,Median 2BR Rent\nSoho,2026-10,unknown\n".utf8))
    }
  }

  @Test func bandUsesOnlyTheLastSixMonths() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar = Calendar(identifier: .gregorian)
    let recent = calendar.date(byAdding: .month, value: -2, to: now)!
    let old = calendar.date(byAdding: .month, value: -7, to: now)!
    let buildingID = UUID()
    let rows = [
      RentObservation(id: UUID(), buildingID: buildingID, rent: 4_000, dateSeen: recent),
      RentObservation(id: UUID(), buildingID: buildingID, rent: 5_500, dateSeen: now),
      RentObservation(id: UUID(), buildingID: buildingID, rent: 3_500, dateSeen: old),
    ]
    #expect(RentBand(observations: rows, now: now, calendar: calendar) == RentBand(low: 4_000, high: 5_500, count: 2))
  }

  @Test func extractsOnlyExplicitTwoBedroomCandidatesFromSavedStreetEasyPage() async throws {
    let fixture = try #require(Bundle.module.url(forResource: "streetEasy-978-2nd-avenue-1f", withExtension: "txt"))
    let page = try String(contentsOf: fixture, encoding: .utf8)
    let extraction = try await withDependencies {
      $0.modelClient = StubModelClient { request in
        #expect(request.tier == .onDevice)
        #expect(request.messages.last?.text.contains("$4,395 for rent") == true)
        return ModelResponse(text: #"{"listings":[{"rent":4395,"unit":"1F","squareFeet":null}]}"#)
      }
    } operation: {
      @Dependency(\.modelClient) var modelClient
      return try await RentListingExtractor.extract(
        from: page,
        sourceURL: URL(string: "https://streeteasy.com/building/978-2-avenue-new_york/1f")!,
        using: modelClient
      )
    }
    #expect(extraction == [RentListingCandidate(rent: 4_395, unit: "1F")])
  }

  @Test func malformedOrUnqualifiedModelOutputIsDiscarded() {
    #expect(RentListingExtractor.parse("not JSON").isEmpty)
    #expect(RentListingExtractor.parse(#"{"listings":[{"rent":0},{"rent":4395,"unit":"1F"}]}"#) == [
      RentListingCandidate(rent: 4_395, unit: "1F")
    ])
  }
}
