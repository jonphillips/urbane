import Foundation
import UrbaneSchema

public struct BuildingFill: Equatable, Sendable {
  public var summary: String?
  public var mapItemIdentifier: String?
  public var streetEasyURL: String?
  public var websiteURL: String?
  public var rejectionReason: String?

  public init(summary: String?, mapItemIdentifier: String?, streetEasyURL: String?, websiteURL: String?, rejectionReason: String?) {
    self.summary = summary
    self.mapItemIdentifier = mapItemIdentifier
    self.streetEasyURL = streetEasyURL
    self.websiteURL = websiteURL
    self.rejectionReason = rejectionReason
  }
}

/// Lossless-or-loud re-import rules. Existing user-edited fields are preserved.
public enum ChatImportReconciliation {
  public static func normalizedAddress(_ address: String) -> String {
    let streetLine = address.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? address
    var tokens = plainTokens(streetLine)
    let suffixes = ["ave": "avenue", "st": "street", "pl": "place", "blvd": "boulevard", "rd": "road", "dr": "drive", "pkwy": "parkway"]
    let directions = ["n": "north", "s": "south", "e": "east", "w": "west"]
    for index in tokens.indices {
      if let direction = directions[tokens[index]] { tokens[index] = direction }
    }
    if let last = tokens.indices.last, let suffix = suffixes[tokens[last]] { tokens[last] = suffix }
    return tokens.joined(separator: " ")
  }

  public static func normalizedNeighborhoodName(_ name: String) -> String {
    plainTokens(name).joined(separator: " ")
  }

  public static func normalizedReviewSource(_ source: String) -> String {
    source.trimmingCharacters(in: .whitespacesAndNewlines).folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
  }

  public static func matchingBuilding(
    mapItemIdentifier: String?, address: String, among buildings: [Building]
  ) -> Building? {
    if let mapItemIdentifier,
      let identifierMatch = buildings.first(where: { $0.mapItemIdentifier == mapItemIdentifier }) {
      return identifierMatch
    }
    let normalized = normalizedAddress(address)
    return buildings.first { normalizedAddress($0.address) == normalized }
  }

  public static func fillEmptyFields(
    of existing: Building, from incoming: ChatBuilding, mapItemIdentifier: String?
  ) -> BuildingFill {
    BuildingFill(
      summary: isEmpty(existing.summary) ? incoming.summary : nil,
      mapItemIdentifier: isEmpty(existing.mapItemIdentifier) ? mapItemIdentifier : nil,
      streetEasyURL: isEmpty(existing.streetEasyURL) ? incoming.streetEasyURL : nil,
      websiteURL: isEmpty(existing.websiteURL) ? incoming.website : nil,
      rejectionReason: existing.status == .rejected && isEmpty(existing.rejectionReason) ? incoming.rejectionReason : nil
    )
  }

  public static func matchingReview(
    buildingID: UUID, source: String, subject: BuildingReviewSubject,
    among reviews: [BuildingReview]
  ) -> BuildingReview? {
    reviews
      .filter {
        $0.buildingID == buildingID
          && normalizedReviewSource($0.source) == normalizedReviewSource(source)
          && $0.subject == subject
      }
      .sorted {
        if $0.gatheredAt != $1.gatheredAt { return $0.gatheredAt > $1.gatheredAt }
        return $0.id.uuidString < $1.id.uuidString
      }
      .first
  }

  public static func shouldReplaceReview(existing: BuildingReview?, replaceExisting: Bool) -> Bool {
    existing == nil || replaceExisting
  }

  private static func isEmpty(_ value: String?) -> Bool {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func plainTokens(_ value: String) -> [String] {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }
}
