import Foundation

public enum BuildingLinkField: String, Equatable, Sendable {
  case website
  case streetEasy

  public var displayName: String {
    switch self {
    case .website: "Website"
    case .streetEasy: "StreetEasy"
    }
  }
}

public enum BuildingLinkValidationError: Error, Equatable, LocalizedError {
  case invalidURL(BuildingLinkField)
  case invalidStreetEasyHost

  public var errorDescription: String? {
    switch self {
    case let .invalidURL(field): "\(field.displayName) must be an http(s) URL with a host."
    case .invalidStreetEasyHost: "StreetEasy must use streeteasy.com or a subdomain of it."
    }
  }
}

public enum BuildingLinkValidator {
  /// Returns a trimmed URL, or nil for an empty value. Invalid values name their field.
  public static func validate(_ value: String, for field: BuildingLinkField) throws -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = components.host, !host.isEmpty, components.url != nil else {
      throw BuildingLinkValidationError.invalidURL(field)
    }
    if field == .streetEasy {
      let normalizedHost = host.lowercased()
      guard normalizedHost == "streeteasy.com" || normalizedHost.hasSuffix(".streeteasy.com") else {
        throw BuildingLinkValidationError.invalidStreetEasyHost
      }
    }
    return trimmed
  }
}
