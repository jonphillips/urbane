import Foundation

/// Lossless-or-loud boundary: extract only name/address text represented by a listing slug.
public enum BuildingURLSlug {
  public struct Result: Equatable, Sendable {
    public var name: String
    public var address: String

    public init(name: String, address: String) {
      self.name = name
      self.address = address
    }
  }

  public static func parse(_ rawURL: String) -> Result? {
    guard let url = URL(string: rawURL),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host?.lowercased(), !host.isEmpty
    else { return nil }

    let components = url.pathComponents.filter { $0 != "/" }
    let slug: String
    if let buildingIndex = components.firstIndex(of: "building"), components.indices.contains(buildingIndex + 1) {
      slug = components[buildingIndex + 1]
    } else if let last = components.last {
      slug = last
    } else { return nil }
    let decoded = slug.removingPercentEncoding ?? slug
    let tokens = decoded.split(separator: "-").map(String.init)
    guard let numberIndex = tokens.firstIndex(where: { $0.first?.isNumber == true }) else { return nil }

    let boroughs = Set(["brooklyn", "queens", "manhattan", "bronx", "staten", "island"])
    let addressTokens = tokens[numberIndex...].prefix { !boroughs.contains($0.lowercased()) }
    guard !addressTokens.isEmpty else { return nil }
    let nameTokens = tokens[..<numberIndex]
    let name = (nameTokens.isEmpty ? addressTokens.joined(separator: " ") : nameTokens.joined(separator: " ")).capitalized
    let address = addressTokens.map { token in
      token.first?.isNumber == true ? token.lowercased() : token.capitalized
    }.joined(separator: " ")
    guard !name.isEmpty, !address.isEmpty else { return nil }
    return Result(name: name, address: address)
  }
}
