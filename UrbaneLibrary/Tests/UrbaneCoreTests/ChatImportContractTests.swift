import Foundation
import Testing
import UrbaneCore
import UrbaneSchema

@Suite struct ChatImportContractTests {
  @Test func missingMarkerWarnsAndStillDecodesFixturePaste() throws {
    let decoded = try ChatImportDecoder.decode(paste())
    #expect(decoded.warning?.contains("missing its contract marker") == true)
    #expect(decoded.buildings.count == 1)
  }

  @Test func newerMarkerIsRefused() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode("URBANE-CONTRACT: v2\n```json\n{}\n```") }
  }

  @Test func unknownStatusFailsTheBuildingRow() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(status: "watching-ish")) }
  }

  @Test func rejectedBuildingWithoutReasonFails() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(status: "rejected", rejectionReason: nil)) }
  }

  @Test func ratingWithoutScaleFails() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","url":"https://example.com/reviews","rating":3.8,"outOf":null,"count":null,"newestReview":null,"summary":"Good maintenance."}"#)) }
  }

  @Test func ratingAboveScaleFails() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","url":"https://example.com/reviews","rating":6,"outOf":5,"count":null,"newestReview":null,"summary":"Good maintenance."}"#)) }
  }

  @Test func unknownReviewSubjectFails() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"neighborhood","url":"https://example.com/reviews","rating":null,"outOf":null,"count":null,"newestReview":null,"summary":"Good maintenance."}"#)) }
  }

  @Test func missingReviewURLFails() {
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","rating":null,"outOf":null,"count":null,"newestReview":null,"summary":"Good maintenance."}"#)) }
  }

  @Test func validReviewRoundTripsItsScaleAndProvenance() throws {
    let decoded = try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","url":"https://example.com/reviews","rating":3.8,"outOf":5,"count":42,"newestReview":"2026-09","summary":"Repairs are prompt."}"#))
    #expect(decoded.buildings[0].reviews[0].ratingScale == 5)
    #expect(decoded.buildings[0].reviews[0].sourceURL == "https://example.com/reviews")
  }

  @Test func reimportPreservesEditedFieldsAndRejectedStatus() throws {
    let incoming = try ChatImportDecoder.decode(paste()).buildings[0]
    let edited = Building(
      id: UUID(), neighborhoodID: UUID(), name: "One North Fourth",
      address: incoming.address, summary: "Our edited note", status: .rejected,
      rejectionReason: "Too noisy"
    )
    #expect(ChatImportReconciliation.matchingBuilding(address: "1 north 4th place brooklyn ny 11249", among: [edited])?.id == edited.id)
    #expect(ChatImportReconciliation.fillEmptyFields(of: edited, from: incoming) == BuildingFill(
      summary: nil, streetEasyURL: nil, websiteURL: nil, rejectionReason: nil
    ))
    #expect(edited.status == .rejected)
  }

  @Test func reviewReimportReplacesSelectedReviewAndKeepsOtherSources() throws {
    let buildingID = UUID()
    let incoming = try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","url":"https://example.com/new","rating":4.1,"outOf":5,"count":50,"newestReview":"2026-10","summary":"Recent repair notes."}"#)).buildings[0].reviews[0]
    let existing = BuildingReview(
      id: UUID(), buildingID: buildingID, source: "Openigloo", subject: .building,
      sourceURL: "https://example.com/old", summary: "Old", gatheredAt: Date(timeIntervalSince1970: 1)
    )
    let otherSource = BuildingReview(
      id: UUID(), buildingID: buildingID, source: "Reddit", subject: .building,
      sourceURL: "https://reddit.com/r/nyc", summary: "Separate source", gatheredAt: Date(timeIntervalSince1970: 1)
    )
    let match = ChatImportReconciliation.matchingReview(buildingID: buildingID, source: incoming.source, subject: .building, among: [existing, otherSource])
    #expect(match == existing)
    #expect(ChatImportReconciliation.shouldReplaceReview(existing: match, replaceExisting: true))
    #expect(!ChatImportReconciliation.shouldReplaceReview(existing: existing, replaceExisting: false))
    #expect(ChatImportReconciliation.shouldReplaceReview(existing: nil, replaceExisting: false))
    #expect(otherSource.source == "Reddit")
  }

  private func paste(status: String = "exploring", rejectionReason: String? = "null", review: String? = nil) -> String {
    let reason = rejectionReason ?? "null"
    let reviews = review.map { "[\($0)]" } ?? "[]"
    return """
    ```json
    {"neighborhoods":[{"name":"Williamsburg","chapter":"","vignettes":[]}],"buildings":[{"name":"One North Fourth","address":"1 North 4th Place, Brooklyn, NY 11249","neighborhood":"Williamsburg","summary":"Courtyard building.","status":"\(status)","rejectionReason":\(reason),"streetEasyURL":null,"website":null,"reviews":\(reviews)}]}
    ```
    """
  }
}

@Suite struct BuildingURLSlugTests {
  @Test func parsesStreetEasyBuildingSlug() {
    #expect(BuildingURLSlug.parse("https://streeteasy.com/building/the-oosten-brooklyn/4b") == nil)
    #expect(BuildingURLSlug.parse("https://streeteasy.com/building/420-kent-avenue-williamsburg-brooklyn/4b") == BuildingURLSlug.Result(name: "420 Kent Avenue Williamsburg", address: "420 Kent Avenue Williamsburg"))
  }

  @Test func preservesStreetNumberOrdinalsFromRealisticSlug() {
    #expect(BuildingURLSlug.parse("https://streeteasy.com/building/one-north-fourth-1-north-4th-place-brooklyn/4b") == BuildingURLSlug.Result(name: "One North Fourth", address: "1 North 4th Place"))
  }

  @Test func parsesBuildingWebsiteAddressSlug() {
    #expect(BuildingURLSlug.parse("https://example.com/the-oosten-429-kent-avenue-brooklyn") == BuildingURLSlug.Result(name: "The Oosten", address: "429 Kent Avenue"))
  }
}
