import Foundation
import LLMHandoffKit
import UrbaneSchema

public struct ChatImportPaste: Equatable, Sendable {
  public var warning: String?
  public var neighborhoods: [ChatNeighborhood]
  public var buildings: [ChatBuilding]
}

public struct ChatNeighborhood: Equatable, Sendable {
  public var name: String
  public var chapter: String?
  public var vignettes: [ChatVignette]
}

public struct ChatBuilding: Equatable, Sendable {
  public var name: String
  public var address: String
  public var neighborhood: String
  public var summary: String
  public var status: BuildingStatus
  public var rejectionReason: String?
  public var streetEasyURL: String?
  public var website: String?
  public var reviews: [ChatReview]
}

public struct ChatVignette: Equatable, Sendable {
  public var place: String
  public var caption: String
}

public enum ReviewSubject: String, Equatable, Sendable {
  case building
  case landlord
}

public struct ChatReview: Equatable, Sendable {
  public var source: String
  public var subject: ReviewSubject
  public var sourceURL: String
  public var rating: Double?
  public var ratingScale: Double?
  public var reviewCount: Int?
  public var newestReviewMonth: String?
  public var summary: String
}

public enum ChatImportError: Error, Equatable, LocalizedError, Sendable {
  case invalidPaste(String)
  case invalidRow(path: String, reason: String)
  case unsupportedReviewAbout(String)
  case newerContract(String)

  public var errorDescription: String? {
    switch self {
    case .invalidPaste(let reason): reason
    case .invalidRow(let path, let reason): "\(path): \(reason)"
    case .unsupportedReviewAbout(let value): "Unknown review about value: \(value)"
    case .newerContract(let reason): reason
    }
  }
}

/// Lossless-or-loud boundary. The marker is checked before a strict row decode; no bad row is dropped.
public enum ChatImportDecoder {
  private static let marker = HandoffContractMarker(prefix: "URBANE-CONTRACT", version: "v1")

  public static func decode(_ pastedText: String) throws -> ChatImportPaste {
    let checked: HandoffContractResult
    do {
      checked = try marker.strippingMarker(from: pastedText)
    } catch {
      throw ChatImportError.newerContract(error.localizedDescription)
    }

    let json = try jsonPayload(in: checked.text)
    guard let data = json.data(using: .utf8) else { throw ChatImportError.invalidPaste("The JSON paste is not valid text.") }
    do {
      try validateKeys(in: data)
      let payload = try JSONDecoder().decode(Payload.self, from: data)
      return ChatImportPaste(
        warning: checked.warning,
        neighborhoods: try payload.neighborhoods.enumerated().map { try $0.element.value(path: "neighborhoods[\($0.offset)]") },
        buildings: try payload.buildings.enumerated().map { try $0.element.value(path: "buildings[\($0.offset)]") }
      )
    } catch let error as ChatImportError {
      throw error
    } catch let error as DecodingError {
      throw decodingFailure(error)
    } catch {
      throw ChatImportError.invalidPaste(error.localizedDescription)
    }
  }

  private static func decodingFailure(_ error: DecodingError) -> ChatImportError {
    let path: [any CodingKey]
    let reason: String
    switch error {
    case let .keyNotFound(key, context):
      path = context.codingPath + [key]
      reason = "required, got missing"
    case let .valueNotFound(type, context):
      path = context.codingPath
      reason = "required, got null (expected \(typeName(type)))"
    case let .typeMismatch(type, context):
      path = context.codingPath
      reason = "expected \(typeName(type)), got wrong type"
    case let .dataCorrupted(context):
      path = context.codingPath
      reason = "invalid value"
    @unknown default:
      path = []
      reason = "invalid value"
    }
    let location = path.reduce(into: "") { result, key in
      if let index = key.intValue {
        result += "[\(index)]"
      } else if result.isEmpty {
        result = key.stringValue
      } else {
        result += ".\(key.stringValue)"
      }
    }
    return .invalidRow(path: location.isEmpty ? "root" : location, reason: reason)
  }

  private static func typeName(_ type: Any.Type) -> String {
    String(describing: type)
  }

  private static func validateKeys(in data: Data) throws {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any] else { throw ChatImportError.invalidPaste("The fenced value must be one JSON object.") }
    try check(root, allowed: ["neighborhoods", "buildings"], path: "root")
    for (index, value) in (root["neighborhoods"] as? [Any] ?? []).enumerated() {
      guard let row = value as? [String: Any] else { throw ChatImportError.invalidRow(path: "neighborhoods[\(index)]", reason: "expected an object") }
      try check(row, allowed: ["name", "chapter", "vignettes"], path: "neighborhoods[\(index)]")
      for (vIndex, vignette) in (row["vignettes"] as? [Any] ?? []).enumerated() {
        guard let row = vignette as? [String: Any] else { throw ChatImportError.invalidRow(path: "neighborhoods[\(index)].vignettes[\(vIndex)]", reason: "expected an object") }
        try check(row, allowed: ["place", "caption"], path: "neighborhoods[\(index)].vignettes[\(vIndex)]")
      }
    }
    for (index, value) in (root["buildings"] as? [Any] ?? []).enumerated() {
      guard let row = value as? [String: Any] else { throw ChatImportError.invalidRow(path: "buildings[\(index)]", reason: "expected an object") }
      try check(row, allowed: ["name", "address", "neighborhood", "summary", "status", "rejectionReason", "streetEasyURL", "website", "reviews"], path: "buildings[\(index)]")
      for (rIndex, review) in (row["reviews"] as? [Any] ?? []).enumerated() {
        guard let row = review as? [String: Any] else { throw ChatImportError.invalidRow(path: "buildings[\(index)].reviews[\(rIndex)]", reason: "expected an object") }
        try check(row, allowed: ["source", "about", "url", "rating", "outOf", "count", "newestReview", "summary"], path: "buildings[\(index)].reviews[\(rIndex)]")
      }
    }
  }

  private static func check(_ object: [String: Any], allowed: Set<String>, path: String) throws {
    if let unknown = object.keys.first(where: { !allowed.contains($0) }) {
      throw ChatImportError.invalidRow(path: path, reason: "unknown field '\(unknown)'")
    }
  }

  private static func jsonPayload(in text: String) throws -> String {
    let parts = text.components(separatedBy: "```")
    if parts.count > 1 {
      guard !parts.count.isMultiple(of: 2) else {
        throw ChatImportError.invalidPaste("The paste contains an unclosed code fence.")
      }
      var jsonBlocks: [String] = []
      var untaggedBlocks: [String] = []
      for blockIndex in stride(from: 1, to: parts.count, by: 2) {
        let block = parts[blockIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = block.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if firstLine.lowercased() == "json" {
          jsonBlocks.append(String(block.dropFirst(firstLine.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        } else if block.hasPrefix("{") {
          untaggedBlocks.append(block)
        }
      }
      let candidates = jsonBlocks + untaggedBlocks
      guard candidates.count == 1, let candidate = candidates.first else {
        throw ChatImportError.invalidPaste("Expected exactly one JSON block in the paste.")
      }
      return candidate
    }

    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
      throw ChatImportError.invalidPaste("Expected a JSON object in the paste.")
    }
    return String(text[start...end])
  }
}

private struct Payload: Decodable {
  var neighborhoods: [NeighborhoodRow]
  var buildings: [BuildingRow]
}

private struct NeighborhoodRow: Decodable {
  var name: String
  var chapter: String?
  var vignettes: [VignetteRow]?

  enum CodingKeys: String, CodingKey { case name, chapter, vignettes }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    chapter = try c.decodeIfPresent(String.self, forKey: .chapter)
    vignettes = try c.decodeIfPresent([VignetteRow].self, forKey: .vignettes)
  }

  func value(path: String) throws -> ChatNeighborhood {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ChatImportError.invalidRow(path: path, reason: "name is empty")
    }
    return ChatNeighborhood(name: name, chapter: chapter, vignettes: try (vignettes ?? []).enumerated().map {
      try $0.element.value(path: "\(path).vignettes[\($0.offset)]")
    })
  }
}

private struct VignetteRow: Decodable {
  var place: String
  var caption: String
  enum CodingKeys: String, CodingKey { case place, caption }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    place = try c.decode(String.self, forKey: .place)
    caption = try c.decode(String.self, forKey: .caption)
  }
  func value(path: String) throws -> ChatVignette {
    guard !place.isEmpty, !caption.isEmpty else { throw ChatImportError.invalidRow(path: path, reason: "place and caption are required") }
    return ChatVignette(place: place, caption: caption)
  }
}

private struct BuildingRow: Decodable {
  var name: String
  var address: String
  var neighborhood: String
  var summary: String
  var status: String
  var rejectionReason: String?
  var streetEasyURL: String?
  var website: String?
  var reviews: [ReviewRow]?

  enum CodingKeys: String, CodingKey { case name, address, neighborhood, summary, status, rejectionReason, streetEasyURL, website, reviews }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    address = try c.decode(String.self, forKey: .address)
    neighborhood = try c.decode(String.self, forKey: .neighborhood)
    summary = try c.decode(String.self, forKey: .summary)
    status = try c.decode(String.self, forKey: .status)
    rejectionReason = try c.decode(Optional<String>.self, forKey: .rejectionReason)
    streetEasyURL = try c.decode(Optional<String>.self, forKey: .streetEasyURL)
    website = try c.decode(Optional<String>.self, forKey: .website)
    reviews = try c.decodeIfPresent([ReviewRow].self, forKey: .reviews)
  }

  func value(path: String) throws -> ChatBuilding {
    guard let status = BuildingStatus(contractValue: status) else {
      throw ChatImportError.invalidRow(path: path, reason: "unknown status '\(self.status)'")
    }
    guard status != .rejected || !(rejectionReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ChatImportError.invalidRow(path: path, reason: "rejected building requires a rejectionReason")
    }
    guard !name.isEmpty, !address.isEmpty, !neighborhood.isEmpty, !summary.isEmpty else {
      throw ChatImportError.invalidRow(path: path, reason: "name, address, neighborhood, and summary are required")
    }
    let decodedReviews = try (reviews ?? []).enumerated().map {
      try $0.element.value(path: "\(path).reviews[\($0.offset)]")
    }
    var reviewKeys = Set<String>()
    for review in decodedReviews {
      let key = "\(ChatImportReconciliation.normalizedReviewSource(review.source))|\(review.subject.rawValue)"
      guard reviewKeys.insert(key).inserted else {
        throw ChatImportError.invalidRow(path: path, reason: "repeated review source and subject")
      }
    }
    return ChatBuilding(
      name: name, address: address, neighborhood: neighborhood, summary: summary,
      status: status, rejectionReason: rejectionReason, streetEasyURL: streetEasyURL,
      website: website, reviews: decodedReviews
    )
  }
}

private extension BuildingStatus {
  init?(contractValue: String) {
    switch contractValue {
    case "exploring": self = .exploring
    case "watching": self = .watching
    case "tourCandidate": self = .tourCandidate
    case "rejected": self = .rejected
    default: return nil
    }
  }
}

private struct ReviewRow: Decodable {
  var source: String
  var about: String
  var url: String
  var rating: Double?
  var outOf: Double?
  var count: Int?
  var newestReview: String?
  var summary: String
  enum CodingKeys: String, CodingKey { case source, about, url, rating, outOf, count, newestReview, summary }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    source = try c.decode(String.self, forKey: .source)
    about = try c.decode(String.self, forKey: .about)
    url = try c.decode(String.self, forKey: .url)
    rating = try c.decode(Optional<Double>.self, forKey: .rating)
    outOf = try c.decode(Optional<Double>.self, forKey: .outOf)
    count = try c.decode(Optional<Int>.self, forKey: .count)
    newestReview = try c.decode(Optional<String>.self, forKey: .newestReview)
    summary = try c.decode(String.self, forKey: .summary)
  }

  func value(path: String) throws -> ChatReview {
    guard let subject = ReviewSubject(rawValue: about) else { throw ChatImportError.unsupportedReviewAbout(about) }
    guard let sourceURL = URL(string: url), ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? "") else {
      throw ChatImportError.invalidRow(path: path, reason: "url must be an http(s) URL")
    }
    guard (rating == nil) == (outOf == nil), (outOf ?? 1) > 0, (rating ?? 0) >= 0, (rating == nil || rating! <= outOf!) else {
      throw ChatImportError.invalidRow(path: path, reason: "rating and outOf must both be null or valid, and rating cannot exceed its scale")
    }
    if let newestReview, newestReview.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) == nil {
      throw ChatImportError.invalidRow(path: path, reason: "newestReview must use YYYY-MM")
    }
    guard !source.isEmpty, !summary.isEmpty, count == nil || count! >= 0 else {
      throw ChatImportError.invalidRow(path: path, reason: "source and summary are required; count cannot be negative")
    }
    return ChatReview(source: source, subject: subject, sourceURL: url, rating: rating, ratingScale: outOf, reviewCount: count, newestReviewMonth: newestReview, summary: summary)
  }
}
