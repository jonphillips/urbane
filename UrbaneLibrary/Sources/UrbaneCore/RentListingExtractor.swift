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

  public var noCandidatesMessage: String {
    if unitsFound == 0 { return "No rental units found on this page." }
    return "Found \(unitsFound) units on this page, none with 2 bedrooms. If the page has a 2 beds tab, tap it, then Extract rents again."
  }

  public init(unitsFound: Int, candidates: [RentListingCandidate]) {
    self.unitsFound = unitsFound
    self.candidates = candidates
  }
}

public enum RentListingExtractor {
  public static let maximumInputCharacters = 10_000
  private static let cardHeaderPattern = #"#([A-Za-z0-9-]+)(?: - [^$#]*)?\s+\$([0-9,]+)\s+base rent\b"#
  private static let unitTokenPattern = #"#([A-Za-z0-9-]+)(?=\s|$)"#
  private static let bedroomPattern = #"\b(\d+)\s+beds?\b|\bstudio\b"#
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
    if let extraction = parseCards(visibleText) { return extraction }
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

  /// Reads the regular unit-card text exposed by StreetEasy's building page reducer.
  /// Returns nil when the page does not contain a card, allowing the model fallback to run.
  public static func parseCards(_ text: String) -> RentListingExtraction? {
    guard let headerRegex = try? NSRegularExpression(pattern: cardHeaderPattern, options: [.caseInsensitive]),
          let unitRegex = try? NSRegularExpression(pattern: unitTokenPattern),
          let bedroomRegex = try? NSRegularExpression(pattern: bedroomPattern, options: [.caseInsensitive]) else {
      return nil
    }
    let textRange = NSRange(text.startIndex..., in: text)
    let headers = headerRegex.matches(in: text, range: textRange)
    guard !headers.isEmpty else { return nil }
    let unitStarts = unitRegex.matches(in: text, range: textRange).map(\.range.location)
    let source = text as NSString
    var cards: [(unit: String, rent: Int, bedrooms: Int)] = []
    var seen = Set<String>()

    for (index, header) in headers.enumerated() {
      guard let unitRange = Range(header.range(at: 1), in: text),
            let rentRange = Range(header.range(at: 2), in: text),
            let rent = Int(String(text[rentRange]).replacingOccurrences(of: ",", with: "")) else { continue }
      let nextCardStart = unitStarts.first(where: { $0 > header.range.location }) ?? textRange.length
      let nextHeaderStart = index + 1 < headers.count ? headers[index + 1].range.location : textRange.length
      let cardEnd = min(min(nextCardStart, nextHeaderStart), header.range.location + 400)
      guard cardEnd > header.range.location else { continue }
      let cardRange = NSRange(location: header.range.location, length: cardEnd - header.range.location)
      let cardText = source.substring(with: cardRange)
      let bedroomMatches = bedroomRegex.matches(in: cardText, range: NSRange(cardText.startIndex..., in: cardText))
      guard let bedroomMatch = bedroomMatches.first else { continue }
      let bedrooms: Int
      if bedroomMatch.range(at: 1).location == NSNotFound {
        bedrooms = 0
      } else if let bedroomRange = Range(bedroomMatch.range(at: 1), in: cardText), let value = Int(cardText[bedroomRange]) {
        bedrooms = value
      } else {
        continue
      }
      let unit = String(text[unitRange])
      let identity = "\(unit)|\(rent)"
      guard seen.insert(identity).inserted else { continue }
      cards.append((unit, rent, bedrooms))
    }

    guard !cards.isEmpty else { return nil }
    let candidates = cards.compactMap { card -> RentListingCandidate? in
      guard card.bedrooms == 2, card.rent > 0 else { return nil }
      return RentListingCandidate(rent: card.rent, unit: card.unit)
    }
    return RentListingExtraction(unitsFound: cards.count, candidates: candidates)
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
        .components(separatedBy: " - ").first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return RentListingCandidate(rent: listing.rent, unit: unit.isEmpty ? nil : unit)
    }
    return RentListingExtraction(unitsFound: response.listings.count, candidates: candidates)
  }
}
