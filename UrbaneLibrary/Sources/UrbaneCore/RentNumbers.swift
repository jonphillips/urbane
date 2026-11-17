import Foundation
import LLMClientKit
import UrbaneSchema

public struct NeighborhoodRentPoint: Equatable, Sendable {
  public var neighborhood: String
  public var month: String
  public var median2BRRent: Double

  public init(neighborhood: String, month: String, median2BRRent: Double) {
    self.neighborhood = neighborhood
    self.month = month
    self.median2BRRent = median2BRRent
  }
}

public struct RentBand: Equatable, Sendable {
  public var low: Int
  public var high: Int
  public var count: Int

  public init(low: Int, high: Int, count: Int = 0) {
    self.low = low
    self.high = high
    self.count = count
  }

  public init(observations: [RentObservation], now: Date, calendar: Calendar = .current) {
    let cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? now
    let recent = observations.filter { $0.dateSeen >= cutoff }.map(\.rent)
    guard !recent.isEmpty else {
      low = 0
      high = 0
      count = 0
      return
    }
    low = recent.min() ?? 0
    high = recent.max() ?? 0
    count = recent.count
  }
}

public enum NeighborhoodRentCSV {
  public enum ImportError: Error, Equatable {
    case invalidUTF8
    case noRows
    case missingHeader
    case unknownHeader(String)
    case unknownNeighborhood(String)
    case malformedRow(Int)
    case invalidMonth(Int)
    case invalidRent(Int)
  }

  /// Lossless-or-loud: accepts only the documented long CSV columns and rejects
  /// unknown headers or malformed rows before any persistence occurs.
  public static func parse(_ data: Data) throws -> [NeighborhoodRentPoint] {
    guard let text = String(data: data, encoding: .utf8) else { throw ImportError.invalidUTF8 }
    let rows = try CSVRows.parse(text)
    guard let header = rows.first, !header.isEmpty else { throw ImportError.missingHeader }
    let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    let known: Set<String> = ["neighborhood", "month", "median 2br rent"]
    for name in names where !known.contains(name) { throw ImportError.unknownHeader(name) }
    guard names.count == known.count, Set(names) == known else { throw ImportError.missingHeader }
    guard rows.count > 1 else { throw ImportError.noRows }
    let neighborhood = names.firstIndex(of: "neighborhood")!
    let month = names.firstIndex(of: "month")!
    let rent = names.firstIndex(of: "median 2br rent")!
    return try rows.dropFirst().enumerated().map { offset, row in
      let line = offset + 2
      guard row.count == header.count else { throw ImportError.malformedRow(line) }
      let monthValue = row[month].trimmingCharacters(in: .whitespacesAndNewlines)
      guard Self.isMonth(monthValue) else { throw ImportError.invalidMonth(line) }
      let rentValue = row[rent].replacingOccurrences(of: "$", with: "")
        .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard let amount = Double(rentValue), amount.isFinite, amount > 0 else {
        throw ImportError.invalidRent(line)
      }
      return NeighborhoodRentPoint(
        neighborhood: row[neighborhood].trimmingCharacters(in: .whitespacesAndNewlines),
        month: monthValue, median2BRRent: amount
      )
    }
  }

  private static func isMonth(_ value: String) -> Bool {
    let parts = value.split(separator: "-")
    guard parts.count == 2, parts[0].count == 4, let year = Int(parts[0]),
      let month = Int(parts[1]) else { return false }
    return (1900...2200).contains(year) && (1...12).contains(month)
  }
}

extension NeighborhoodRentCSV.ImportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidUTF8: "The CSV file is not UTF-8 text."
    case .noRows: "The CSV has no neighborhood rent rows."
    case .missingHeader: "The CSV must contain Neighborhood, Month, and Median 2BR Rent columns."
    case .unknownHeader(let header): "Unknown CSV column: \(header). The file was not imported."
    case .unknownNeighborhood(let name): "No Urbane neighborhood matches ‘\(name)’. The file was not imported."
    case .malformedRow(let line): "CSV row \(line) has the wrong number of columns."
    case .invalidMonth(let line): "CSV row \(line) must use a YYYY-MM month."
    case .invalidRent(let line): "CSV row \(line) has an invalid median rent."
    }
  }
}

private enum CSVRows {
  static func parse(_ text: String) throws -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var characters = Array(text)
    if characters.last == "\r" { characters.removeLast() }
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if quoted {
        if character == "\"" {
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            field.append("\"")
            index += 1
          } else {
            quoted = false
          }
        } else {
          field.append(character)
        }
      } else {
        switch character {
        case "\"" where field.isEmpty: quoted = true
        case ",": row.append(field); field = ""
        case "\n", "\r":
          row.append(field)
          if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
          row = []
          field = ""
        default: field.append(character)
        }
      }
      index += 1
    }
    guard !quoted else { throw NeighborhoodRentCSV.ImportError.malformedRow(rows.count + 1) }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
    }
    return rows
  }
}

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

public enum RentListingExtractor {
  public static let instructions = """
    Extract only rental units explicitly shown in this rendered StreetEasy page.
    Return JSON only: {"listings":[{"rent":4395,"unit":"1F","squareFeet":null}]}.
    Include only 2-bedroom rentals. Do not infer unit, square feet, or rent. Do not
    include similar homes or historical prices. Return an empty array when none qualify.
    """

  public static func extract(
    from html: String, sourceURL: URL, using modelClient: any ModelClient
  ) async throws -> [RentListingCandidate] {
    let request = ModelRequest(
      tier: .onDevice,
      system: instructions,
      prompt: "Source URL: \(sourceURL.absoluteString)\nRendered page HTML:\n\(html)",
      maxTokens: 1024
    )
    let response = try await modelClient.complete(request)
    return parse(response.text)
  }

  /// Review-dependent: model output becomes candidates only; callers must expose and
  /// confirm each candidate before saving any observation.
  public static func parse(_ text: String) -> [RentListingCandidate] {
    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end,
      let data = String(text[start...end]).data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = object["listings"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
      guard let rent = row["rent"] as? Int, rent > 0 else { return nil }
      let unit = (row["unit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      let squareFeet = row["squareFeet"] as? Double
      guard squareFeet == nil || squareFeet! > 0 else { return nil }
      return RentListingCandidate(rent: rent, unit: unit, squareFeet: squareFeet)
    }
  }
}
