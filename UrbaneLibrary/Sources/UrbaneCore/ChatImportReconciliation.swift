import Foundation
import UrbaneSchema

public struct BuildingFill: Equatable, Sendable {
  public var summary: String?
  public var streetEasyURL: String?
  public var websiteURL: String?
  public var rejectionReason: String?

  public init(summary: String?, streetEasyURL: String?, websiteURL: String?, rejectionReason: String?) {
    self.summary = summary
    self.streetEasyURL = streetEasyURL
    self.websiteURL = websiteURL
    self.rejectionReason = rejectionReason
  }
}

/// Lossless-or-loud re-import rules. Existing user-edited fields are preserved.
public enum ChatImportReconciliation {
  public static func normalizedAddress(_ address: String) -> String {
    address.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
  }

  public static func matchingBuilding(address: String, among buildings: [Building]) -> Building? {
    let normalized = normalizedAddress(address)
    return buildings.first { normalizedAddress($0.address) == normalized }
  }

  public static func fillEmptyFields(of existing: Building, from incoming: ChatBuilding) -> BuildingFill {
    BuildingFill(
      summary: isEmpty(existing.summary) ? incoming.summary : nil,
      streetEasyURL: isEmpty(existing.streetEasyURL) ? incoming.streetEasyURL : nil,
      websiteURL: isEmpty(existing.websiteURL) ? incoming.website : nil,
      rejectionReason: existing.status == .rejected && isEmpty(existing.rejectionReason) ? incoming.rejectionReason : nil
    )
  }

  public static func matchingReview(
    buildingID: UUID, source: String, subject: BuildingReviewSubject,
    among reviews: [BuildingReview]
  ) -> BuildingReview? {
    reviews.first { $0.buildingID == buildingID && $0.source == source && $0.subject == subject }
  }

  public static func shouldReplaceReview(existing: BuildingReview?, replaceExisting: Bool) -> Bool {
    existing == nil || replaceExisting
  }

  private static func isEmpty(_ value: String?) -> Bool {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
