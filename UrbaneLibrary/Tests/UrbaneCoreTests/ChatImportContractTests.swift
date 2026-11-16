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

  @Test func markerAndBareJSONObjectDecodeWithoutFences() throws {
    let text = "URBANE-CONTRACT: v1\n" + json()
    #expect(try ChatImportDecoder.decode(text).warning == nil)
  }

  @Test func chapterParagraphsAndWhitespaceSurviveImportDecoding() throws {
    let chapter = "Morning light on the stoops.\n\nAt night, the avenue stays lively.  "
    let encoded = #"{"neighborhoods":[{"name":"Williamsburg","chapter":"Morning light on the stoops.\n\nAt night, the avenue stays lively.  ","vignettes":[]}],"buildings":[]}"#
    let decoded = try ChatImportDecoder.decode(encoded)
    #expect(decoded.neighborhoods[0].chapter == chapter)
  }

  @Test func bareJSONWithoutMarkerWarns() throws {
    #expect(try ChatImportDecoder.decode(json()).warning?.contains("missing its contract marker") == true)
  }

  @Test func proseBeforeBareJSONObjectIsAccepted() throws {
    #expect(try ChatImportDecoder.decode("Here is your Urbane seed:\n\n" + json()).buildings.count == 1)
  }

  @Test func untaggedSingleFenceIsAccepted() throws {
    #expect(try ChatImportDecoder.decode("```\n" + json() + "\n```").buildings.count == 1)
  }

  @Test func multipleJSONFencesAreRefused() {
    #expect(throws: ChatImportError.self) {
      try ChatImportDecoder.decode("```json\n\(json())\n```\n```json\n{}\n```")
    }
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

  @Test func nullReviewURLReportsItsExactLocation() {
    let text = paste(review: #"{"source":"Openigloo","about":"building","url":null,"rating":null,"outOf":null,"count":null,"newestReview":null,"summary":"Good maintenance."}"#)
    do {
      _ = try ChatImportDecoder.decode(text)
      Issue.record("Expected a null review URL to fail")
    } catch {
      #expect(error.localizedDescription.contains("buildings[0].reviews[0].url"))
      #expect(error.localizedDescription.contains("required, got null"))
    }
  }

  @Test func missingBuildingSummaryReportsItsExactLocation() {
    let text = json().replacingOccurrences(of: #""summary":"Courtyard building.","status""#, with: #""status""#)
    do {
      _ = try ChatImportDecoder.decode(text)
      Issue.record("Expected a missing building summary to fail")
    } catch {
      #expect(error.localizedDescription.contains("buildings[0].summary"))
      #expect(error.localizedDescription.contains("required, got missing"))
    }
  }

  @Test func repeatedReviewSourceAndSubjectInOneBuildingFails() {
    let one = #"{"source":"Openigloo","about":"building","url":"https://example.com/1","rating":null,"outOf":null,"count":null,"newestReview":null,"summary":"First."}"#
    let two = #"{"source":" openigloo ","about":"building","url":"https://example.com/2","rating":null,"outOf":null,"count":null,"newestReview":null,"summary":"Second."}"#
    #expect(throws: ChatImportError.self) { try ChatImportDecoder.decode(paste(reviews: [one, two])) }
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
    #expect(ChatImportReconciliation.matchingBuilding(mapItemIdentifier: nil, address: "1 North 4th Pl, Brooklyn, NY 11249", among: [edited])?.id == edited.id)
    #expect(ChatImportReconciliation.fillEmptyFields(of: edited, from: incoming, mapItemIdentifier: "resolved-id") == BuildingFill(
      summary: nil, mapItemIdentifier: "resolved-id", streetEasyURL: nil, websiteURL: nil, rejectionReason: nil
    ))
    #expect(edited.status == .rejected)
  }

  @Test func addressMatchNormalizesStreetLineAndKeepsNumbersDistinct() {
    #expect(ChatImportReconciliation.normalizedAddress("420 Kent Ave, Brooklyn, NY") == ChatImportReconciliation.normalizedAddress("420 Kent Avenue, Brooklyn, NY 11249"))
    #expect(ChatImportReconciliation.normalizedAddress("1 N 4th Pl, Brooklyn, NY") == ChatImportReconciliation.normalizedAddress("1 North 4th Place, Brooklyn, NY 11249"))
    #expect(ChatImportReconciliation.normalizedAddress("420 Kent Avenue, Brooklyn, NY") != ChatImportReconciliation.normalizedAddress("429 Kent Avenue, Brooklyn, NY"))
  }

  @Test func buildingReimportMatchesMapIdentifierBeforeAddressAndFillsAnEmptyIdentifier() throws {
    let incoming = try ChatImportDecoder.decode(paste()).buildings[0]
    let place = PlaceMatch(name: "New place name", address: incoming.address, latitude: 40.71, longitude: -73.96, mapItemIdentifier: "map-item-1")
    let identifierMatch = Building(
      id: UUID(), neighborhoodID: UUID(), name: "Same place", address: "A stale address",
      mapItemIdentifier: "map-item-1"
    )
    let addressMatch = Building(
      id: UUID(), neighborhoodID: UUID(), name: "Same address", address: incoming.address
    )
    #expect(ChatImportReconciliation.matchingBuilding(mapItemIdentifier: place.mapItemIdentifier, address: incoming.address, among: [identifierMatch, addressMatch])?.id == identifierMatch.id)
    #expect(ChatImportReconciliation.matchingBuilding(mapItemIdentifier: "new-id", address: incoming.address, among: [addressMatch])?.id == addressMatch.id)
    #expect(ChatImportReconciliation.fillEmptyFields(of: addressMatch, from: incoming, mapItemIdentifier: place.mapItemIdentifier).mapItemIdentifier == "map-item-1")
  }

  @Test func reviewReimportReplacesSelectedReviewAndKeepsOtherSources() throws {
    let buildingID = UUID()
    let incoming = try ChatImportDecoder.decode(paste(review: #"{"source":"Openigloo","about":"building","url":"https://example.com/new","rating":4.1,"outOf":5,"count":50,"newestReview":"2026-10","summary":"Recent repair notes."}"#)).buildings[0].reviews[0]
    let existing = BuildingReview(
      id: UUID(), buildingID: buildingID, source: " Openigloo ", subject: .building,
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
    return "```json\n\(json(status: status, reason: reason, reviews: reviews))\n```"
  }

  private func paste(reviews: [String]) -> String {
    "```json\n\(json(reviews: "[\(reviews.joined(separator: ","))]"))\n```"
  }

  private func json() -> String { json(status: "exploring", reason: "null", reviews: "[]") }

  private func json(status: String = "exploring", reason: String = "null", reviews: String = "[]") -> String {
    return """
    {"neighborhoods":[{"name":"Williamsburg","chapter":"","vignettes":[]}],"buildings":[{"name":"One North Fourth","address":"1 North 4th Place, Brooklyn, NY 11249","neighborhood":"Williamsburg","summary":"Courtyard building.","status":"\(status)","rejectionReason":\(reason),"streetEasyURL":null,"website":null,"reviews":\(reviews)}]}
    """
  }
}

@Suite struct PlaceSearchRowTests {
  @Test func onePlaceSearchFailureIsContainedToItsRow() async throws {
    let client = PlaceSearchClient { query in
      if query == "fail" { throw FixtureSearchError.offline }
      return []
    }
    #expect(try await PlaceSearchRows.resolve(query: "fail", using: client) == .unresolved("Fixture search failed"))
    #expect(try await PlaceSearchRows.resolve(query: "no match", using: client) == .matches([]))
  }

  @Test func mapKitErrorsDistinguishNoMatchAndThrottle() {
    #expect(PlaceSearchFailureDisposition.classify(domain: "MKErrorDomain", code: 4) == .noMatch)
    #expect(PlaceSearchFailureDisposition.classify(domain: "MKErrorDomain", code: 3) == .throttled)
    #expect(PlaceSearchFailureDisposition.classify(domain: "Other", code: 4) == .other)
  }
}

private enum FixtureSearchError: Error, LocalizedError, Sendable {
  case offline
  var errorDescription: String? { "Fixture search failed" }
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
