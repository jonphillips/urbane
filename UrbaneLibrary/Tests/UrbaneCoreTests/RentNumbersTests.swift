import Dependencies
import Foundation
import LLMClientKit
import Testing
import UrbaneSchema

@testable import UrbaneCore

private actor ModelRequestCapture {
  private(set) var request: ModelRequest?
  func store(_ request: ModelRequest) { self.request = request }
}

@Suite struct RentNumbersTests {
  @Test func parsesRealDashboardFixtureUsingOnlyRecentNeighborhoodMonths() throws {
    // Source: https://cdn-charts.streeteasy.com/rentals/TwoBd/medianAskingRent_TwoBd.zip
    // Fetched 2026-11-16; rows and the complete original monthly header are preserved.
    let fixture = try #require(Bundle.module.url(forResource: "medianAskingRent_TwoBd-2026-11-05", withExtension: "csv"))
    let dataset = try NeighborhoodRentCSV.parse(Data(contentsOf: fixture))
    let rows = dataset.points
    #expect(rows.count == 24)
    #expect(rows.allSatisfy { $0.month >= "2025-11" && $0.month <= "2026-10" })
    #expect(rows.allSatisfy { $0.neighborhood != "Manhattan" && $0.neighborhood != "Baychester" })
    #expect(dataset.areaNames.contains("Baychester"))
    #expect(rows.contains(.init(neighborhood: "West Village", month: "2026-10", median2BRRent: 7_295)))
    #expect(rows.contains(.init(neighborhood: "Midtown West", month: "2026-10", median2BRRent: 7_000)))
  }

  @Test func unknownCSVHeaderFailsLoudly() {
    let csv = "areaName,Borough,areaType,2026-01,Notes\nSoho,Manhattan,neighborhood,5400,extra\n"
    #expect(throws: NeighborhoodRentCSV.ImportError.unknownHeader("Notes")) {
      try NeighborhoodRentCSV.parse(Data(csv.utf8))
    }
  }

  @Test func rejectsUnknownAreaTypesAndInvalidRents() {
    let header = "areaName,Borough,areaType,2026-01"
    #expect(throws: NeighborhoodRentCSV.ImportError.unknownAreaType("community")) {
      try NeighborhoodRentCSV.parse(Data("\(header)\nSoho,Manhattan,community,5400\n".utf8))
    }
    #expect(throws: NeighborhoodRentCSV.ImportError.invalidRent(2, "2026-01")) {
      try NeighborhoodRentCSV.parse(Data("\(header)\nSoho,Manhattan,neighborhood,unknown\n".utf8))
    }
  }

  @Test func stripsBomAndSkipsEmptyMonthCells() throws {
    let csv = "\u{feff}areaName,Borough,areaType,2026-01\nBaychester,Bronx,neighborhood,\n"
    #expect(try NeighborhoodRentCSV.parse(Data(csv.utf8)).points.isEmpty)
  }

  @Test func dashboardCityAndBoroughRowsAreIgnored() throws {
    let csv = "areaName,Borough,areaType,2026-01\nNYC,NYC,city,9000\nManhattan,NYC,borough,7000\nSoho,Manhattan,neighborhood,5000\n"
    let dataset = try NeighborhoodRentCSV.parse(Data(csv.utf8))
    #expect(dataset.points == [.init(neighborhood: "Soho", month: "2026-01", median2BRRent: 5_000)])
  }

  @Test func mapsUrbaneNeighborhoodNamesAndListsMissingAliases() {
    let rows = [NeighborhoodRentPoint(neighborhood: "Midtown West", month: "2026-10", median2BRRent: 5_500)]
    let plan = StreetEasyNeighborhoodAliases.plan(
      neighborhoods: ["Hell's Kitchen", "West Village"], points: rows
    )
    #expect(plan.matches == [NeighborhoodRentMatch(neighborhood: "Hell's Kitchen", points: rows)])
    #expect(plan.missingNeighborhoods == ["West Village"])
    let emptyAreaPlan = StreetEasyNeighborhoodAliases.plan(
      neighborhoods: ["Baychester"], points: [], areaNames: ["Baychester"]
    )
    #expect(emptyAreaPlan.matches == [NeighborhoodRentMatch(neighborhood: "Baychester", points: [])])
    #expect(emptyAreaPlan.missingNeighborhoods.isEmpty)
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

  @Test func reducesPageToVisibleListingTextWithinOnDeviceBudget() {
    let html = """
      <html><head><title>Hidden heading</title><script>\(String(repeating: "x", count: 20_000))</script></head>
      <body><header>Navigation</header><div hidden>Hidden attribute</div><span aria-hidden="true">Aria hidden</span><main><section id="listing">
      <h1>978 2nd Avenue #1F</h1><p>$4,395 for rent</p><p>2 beds</p>
      <p>11 ft² measurements omitted</p></section><section><h2>Similar homes</h2><p>$4,000 for rent</p></section>
      </main><footer>Footer</footer></body></html>
      """
    let text = StreetEasyPageReducer.reduce(html)
    #expect(text.count <= RentListingExtractor.maximumInputCharacters)
    #expect(text.contains("978 2nd Avenue #1F"))
    #expect(text.contains("$4,395 for rent"))
    #expect(!text.contains("Hidden heading"))
    #expect(!text.contains("Navigation"))
    #expect(!text.contains("Hidden attribute"))
    #expect(!text.contains("Aria hidden"))
    #expect(!text.contains("Similar homes"))
    #expect(!text.contains("$4,000 for rent"))
  }

  @Test func reducerKeepsTextAfterVoidAriaHiddenImage() {
    let html = "<div><p><img src=photo aria-hidden=\"true\">$4,395 for rent</p><p>Unit 1F · 2 beds</p></div>"
    #expect(StreetEasyPageReducer.reduce(html) == "$4,395 for rent Unit 1F · 2 beds")
  }

  @Test func reducerKeepsTextAfterHiddenVoidInput() {
    let html = "<form><input type=\"hidden\" name=\"x\" hidden><p>$4,395 for rent</p></form>"
    #expect(StreetEasyPageReducer.reduce(html) == "$4,395 for rent")
  }

  @Test func reducerDoesNotTreatHiddenClassNamesAsHiddenAttributes() {
    let html = "<div class=\"block hidden-print\"><p>$4,395 for rent</p></div>"
    #expect(StreetEasyPageReducer.reduce(html) == "$4,395 for rent")
  }

  @Test func reducerKeepsListingBeforeSimilarHomesHeading() {
    let html = "<div id=\"page\"><section><p>$4,395 for rent · 2 beds · #1F</p></section><h2>Similar homes nearby</h2><div><p>$4,000 for rent</p></div></div>"
    let text = StreetEasyPageReducer.reduce(html)
    #expect(text == "$4,395 for rent · 2 beds · #1F")
    #expect(!text.contains("$4,000"))
  }

  @Test func reducerMatchesSimilarAttributesWithoutCaseSensitivity() {
    let html = #"<main><section><p>$4,395 for rent · 2 beds · #1F</p></section><div class="SimilarListings_wrap"><p>$4,000 for rent</p></div></main>"#
    let text = StreetEasyPageReducer.reduce(html)
    #expect(text.contains("$4,395"))
    #expect(!text.contains("$4,000"))
  }

  @Test func reducerTreatsScriptAndStyleAsRawText() {
    let html = #"<main><p>$4,395 for rent</p><script>var s = "</main>"; var t = "secret token";</script><p>after</p></main>"#
    #expect(StreetEasyPageReducer.reduce(html) == "$4,395 for rent after")
  }

  @Test func realBuildingFixtureRetainsListingRentsAndFitsModelBudget() async throws {
    let (html, url) = try loadFixture("streeteasy-420-kent-avenue-building")
    let reduced = StreetEasyPageReducer.reduce(html)
    for expected in ["#560", "$7,482", "#802", "$7,282", "#1009", "$7,105"] {
      #expect(reduced.contains(expected))
    }
    #expect(reduced.count <= RentListingExtractor.maximumInputCharacters)
    let request = try await captureRequest(from: html, sourceURL: url)
    assertReducedTextWasSent(request, reduced: reduced)
  }

  @Test func realListingFixtureRetainsTargetListingAndOmitsSimilarHomes() async throws {
    let (html, url) = try loadFixture("streeteasy-420-kent-avenue-560-listing")
    let reduced = StreetEasyPageReducer.reduce(html)
    #expect(reduced.contains("#560"))
    #expect(reduced.contains("$7,482"))
    #expect(reduced.count <= RentListingExtractor.maximumInputCharacters)
    #expect(!reduced.localizedCaseInsensitiveContains("similar homes"))
    let request = try await captureRequest(from: html, sourceURL: url)
    assertReducedTextWasSent(request, reduced: reduced)
  }

  @Test func buildingLinkValidationAcceptsHTTPURLsAndStreetEasySubdomains() throws {
    #expect(try BuildingLinkValidator.validate("https://example.com/building", for: .website) == "https://example.com/building")
    #expect(try BuildingLinkValidator.validate("http://www.streeteasy.com/building", for: .streetEasy) == "http://www.streeteasy.com/building")
  }

  @Test func buildingLinkValidationAllowsEmptyValuesToClearLinks() throws {
    #expect(try BuildingLinkValidator.validate("  \n", for: .website) == nil)
    #expect(try BuildingLinkValidator.validate("", for: .streetEasy) == nil)
  }

  @Test func buildingLinkValidationKeepsEmptyFieldsWhenTheOtherLinkIsFilled() throws {
    let links = try BuildingLinkValidator.validateLinks(
      website: "", streetEasy: "https://streeteasy.com/building/example"
    )
    #expect(links.website == nil)
    #expect(links.streetEasy == "https://streeteasy.com/building/example")
  }

  @Test func buildingLinkValidationAllowsBothFieldsToBeCleared() throws {
    let links = try BuildingLinkValidator.validateLinks(website: "", streetEasy: " ")
    #expect(links.website == nil)
    #expect(links.streetEasy == nil)
  }

  @Test func buildingLinkValidationRejectsMissingSchemeAndNamesField() {
    #expect(throws: BuildingLinkValidationError.invalidURL(.website)) {
      try BuildingLinkValidator.validate("example.com/building", for: .website)
    }
  }

  @Test func buildingLinkValidationRejectsNonHTTPSScheme() {
    #expect(throws: BuildingLinkValidationError.invalidURL(.website)) {
      try BuildingLinkValidator.validate("mailto:hello@example.com", for: .website)
    }
  }

  @Test func buildingLinkValidationRestrictsStreetEasyHost() {
    #expect(throws: BuildingLinkValidationError.invalidStreetEasyHost) {
      try BuildingLinkValidator.validate("https://example.com/building", for: .streetEasy)
    }
  }

  @Test func extractorUsesGuidedSchemaAndSendsReducedListingTextToOnDeviceModel() async throws {
    let html = "<html><head><script>private menu</script></head><main><p>978 2nd Avenue #1F</p><p>$4,395 for rent · 2 beds</p><section><h2>Similar homes</h2>$4,000 for rent</section></main></html>"
    let schema = RentListingExtractor.responseSchema
    if case let .object(fields) = schema {
      #expect(fields["type"] == .string("object"))
      #expect(fields["required"] == .array([.string("listings")]))
      if case let .object(properties)? = fields["properties"],
         case let .object(listings)? = properties["listings"],
         case let .object(item)? = listings["items"],
         case let .object(itemProperties)? = item["properties"] {
        #expect(itemProperties["bedrooms"] != nil)
        #expect(itemProperties["rent"] != nil)
        #expect(itemProperties["unit"] != nil)
        #expect(item["required"] == .array([.string("bedrooms"), .string("rent"), .string("unit")]))
      } else {
        Issue.record("The rental response schema must describe required listing fields")
      }
    } else {
      Issue.record("The rental response schema must be an object")
    }
    #expect(RentListingExtractor.instructions.contains("List every rental unit"))
    #expect(!RentListingExtractor.instructions.contains("4395"))
    #expect(!RentListingExtractor.instructions.contains("1F"))
    let extraction = try await withDependencies {
      $0.modelClient = StubModelClient { request in
        #expect(request.tier == .onDevice)
        #expect(request.responseFormat == .jsonSchema(name: "street_easy_rental_units", schema: schema))
        let prompt = request.messages.last?.text ?? ""
        #expect(prompt.contains("$4,395 for rent"))
        #expect(!prompt.contains("private menu"))
        #expect(!prompt.contains("$4,000 for rent"))
        return ModelResponse(text: ##"{"listings":[{"bedrooms":2,"rent":4395,"unit":"#1F"},{"bedrooms":1,"rent":3300,"unit":"2A"},{"bedrooms":2,"rent":0,"unit":"3B"}]}"##)
      }
    } operation: {
      @Dependency(\.modelClient) var modelClient
      return try await RentListingExtractor.extract(
        from: html,
        sourceURL: URL(string: "https://streeteasy.com/building/978-2-avenue-new_york/1f")!,
        using: modelClient
      )
    }
    #expect(extraction == RentListingExtraction(
      unitsFound: 3,
      candidates: [RentListingCandidate(rent: 4_395, unit: "1F")]
    ))
  }

  @Test func noTwoBedroomMessageSuggestsSelectingTheTwoBedsTab() {
    let extraction = RentListingExtraction(unitsFound: 9, candidates: [])
    #expect(extraction.noCandidatesMessage == "Found 9 units on this page, none with 2 bedrooms. If the page has a 2 beds tab, tap it, then Extract rents again.")
    #expect(RentListingExtraction(unitsFound: 0, candidates: []).noCandidatesMessage == "No rental units found on this page.")
  }

  @Test func undecodableOutputIsAnErrorAndValidOutputFiltersAndNormalizes() throws {
    #expect(throws: RentListingExtractor.ExtractionError.invalidResponse) {
      try RentListingExtractor.parse("not JSON")
    }
    let extraction = try RentListingExtractor.parse(##"{"listings":[{"bedrooms":0,"rent":2000,"unit":"studio"},{"bedrooms":1,"rent":3300,"unit":"2A"},{"bedrooms":2,"rent":0,"unit":"3B"},{"bedrooms":2,"rent":7482,"unit":"  # 560 - 420 Kent Avenue  "},{"bedrooms":2,"rent":7105,"unit":"#1009 - 420 Kent Avenue"}]}"##)
    #expect(extraction.unitsFound == 5)
    #expect(extraction.candidates == [
      RentListingCandidate(rent: 7_482, unit: "560"),
      RentListingCandidate(rent: 7_105, unit: "1009"),
    ])
  }

  @Test func markerScaleClampsAndInterpolatesAcrossCameraDistances() {
    #expect(SubwayMarkerScale.scale(cameraDistance: 600) == 1.5)
    #expect(SubwayMarkerScale.scale(cameraDistance: 0) == 1.5)
    #expect(SubwayMarkerScale.scale(cameraDistance: 4_440) == 1.0)
    #expect(SubwayMarkerScale.scale(cameraDistance: 8_000) == 1.0)
    #expect(SubwayMarkerScale.scale(cameraDistance: 2_000) > 1.0)
    #expect(SubwayMarkerScale.scale(cameraDistance: 2_000) < 1.5)
    #expect(SubwayMarkerScale.maximumCameraDistance == 10_000)
  }

  private func loadFixture(_ name: String) throws -> (String, URL) {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "html"))
    return (try String(contentsOf: url, encoding: .utf8), url)
  }

  private func captureRequest(from html: String, sourceURL: URL) async throws -> ModelRequest {
    let capture = ModelRequestCapture()
    _ = try await withDependencies {
      $0.modelClient = StubModelClient { request in
        await capture.store(request)
        return ModelResponse(text: #"{"listings":[]}"#)
      }
    } operation: {
      @Dependency(\.modelClient) var modelClient
      return try await RentListingExtractor.extract(from: html, sourceURL: sourceURL, using: modelClient)
    }
    return try #require(await capture.request)
  }

  private func assertReducedTextWasSent(_ request: ModelRequest, reduced: String) {
    #expect(request.tier == .onDevice)
    let prompt = request.messages.last?.text ?? ""
    #expect(prompt.contains(reduced))
    #expect(!prompt.localizedCaseInsensitiveContains("<div"))
  }
}
