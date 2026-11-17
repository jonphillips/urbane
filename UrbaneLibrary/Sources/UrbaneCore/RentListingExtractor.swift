import Foundation
import LLMClientKit

public struct RentListingCandidate: Equatable, Sendable, Identifiable {
  public var rent: Int
  public var unit: String?
  public var squareFeet: Double?

  public var id: String { "\(rent)|\(unit ?? "")|\(squareFeet ?? 0)" }

  public init(rent: Int, unit: String? = nil, squareFeet: Double? = nil) {
    self.rent = rent
    self.unit = unit
    self.squareFeet = squareFeet
  }
}

public struct RentListingExtraction: Equatable, Sendable {
  public let unitsFound: Int
  public let candidates: [RentListingCandidate]

  public init(unitsFound: Int, candidates: [RentListingCandidate]) {
    self.unitsFound = unitsFound
    self.candidates = candidates
  }
}

public enum RentListingExtractor {
  public static let maximumInputCharacters = 10_000
  public static let instructions = """
    You read the visible text of a StreetEasy rental page. List every rental unit the page
    currently offers: its unit number (as written after #), its base rent, and its bedrooms from
    "N beds" or "N bed" (0 for a studio; "rooms" is not bedrooms). Use only numbers shown on the
    page. Skip price history, neighborhood medians, and similar or nearby homes. If no unit is
    offered, return an empty list.
    """

  public static let responseSchema: JSONValue = [
    "type": "object",
    "properties": [
      "listings": [
        "type": "array",
        "description": "Every rental unit currently listed on the page",
        "items": [
          "type": "object",
          "properties": [
            "bedrooms": ["type": "integer", "description": "Bedrooms, from text like 2 beds; 0 for a studio. Never the rooms count."],
            "rent": ["type": "integer", "description": "Monthly base rent in dollars"],
            "unit": ["type": "string", "description": "Unit number, e.g. 1009"],
          ],
          "required": ["bedrooms", "rent", "unit"],
          "additionalProperties": .bool(false),
        ],
      ],
    ],
    "required": ["listings"],
    "additionalProperties": .bool(false),
  ]

  public enum ExtractionError: Error, LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
      "The model returned rental data that could not be read. Please try again."
    }
  }

  private struct Response: Decodable { let listings: [Listing] }
  private struct Listing: Decodable {
    let bedrooms: Int
    let rent: Int
    let unit: String
  }

  public static func extract(
    from html: String, sourceURL: URL, using modelClient: any ModelClient
  ) async throws -> RentListingExtraction {
    let visibleText = StreetEasyPageReducer.reduce(html)
    let request = ModelRequest(
      tier: .onDevice,
      system: instructions,
      prompt: "Source URL: \(sourceURL.absoluteString)\nVisible listing page text:\n\(visibleText)",
      maxTokens: 1024,
      responseFormat: .jsonSchema(name: "street_easy_rental_units", schema: responseSchema)
    )
    let response = try await modelClient.complete(request)
    return try parse(response.text)
  }

  /// Model output is only a candidate list; each candidate needs user confirmation before saving.
  public static func parse(_ text: String) throws -> RentListingExtraction {
    guard let data = text.data(using: .utf8), let response = try? JSONDecoder().decode(Response.self, from: data) else {
      throw ExtractionError.invalidResponse
    }
    let candidates = response.listings.compactMap { listing -> RentListingCandidate? in
      guard listing.bedrooms == 2, listing.rent > 0 else { return nil }
      let unit = listing.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "^#\\s*", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return RentListingCandidate(rent: listing.rent, unit: unit.isEmpty ? nil : unit)
    }
    return RentListingExtraction(unitsFound: response.listings.count, candidates: candidates)
  }
}
