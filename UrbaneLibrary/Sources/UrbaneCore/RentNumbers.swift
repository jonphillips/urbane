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

public struct NeighborhoodRentDataset: Equatable, Sendable {
  public var areaNames: [String]
  public var points: [NeighborhoodRentPoint]
}

public struct NeighborhoodRentMatch: Equatable, Sendable {
  public var neighborhood: String
  public var points: [NeighborhoodRentPoint]

  public init(neighborhood: String, points: [NeighborhoodRentPoint]) {
    self.neighborhood = neighborhood
    self.points = points
  }
}

public struct NeighborhoodRentImportPlan: Equatable, Sendable {
  public var matches: [NeighborhoodRentMatch]
  public var missingNeighborhoods: [String]
}

public enum StreetEasyNeighborhoodAliases {
  private static let aliases = ["hellskitchen": "Midtown West"]

  public static func areaName(for neighborhood: String) -> String {
    aliases[normalize(neighborhood)] ?? neighborhood
  }

  public static func plan(
    neighborhoods: [String], points: [NeighborhoodRentPoint], areaNames: [String]? = nil
  ) -> NeighborhoodRentImportPlan {
    let byName = Dictionary(grouping: points, by: { normalize($0.neighborhood) })
    let availableAreas = Set((areaNames ?? points.map(\.neighborhood)).map(normalize))
    var matches: [NeighborhoodRentMatch] = []
    var missing: [String] = []
    for neighborhood in neighborhoods {
      let area = areaName(for: neighborhood)
      guard availableAreas.contains(normalize(area)) else {
        missing.append(neighborhood)
        continue
      }
      matches.append(NeighborhoodRentMatch(neighborhood: neighborhood, points: byName[normalize(area)] ?? []))
    }
    return NeighborhoodRentImportPlan(matches: matches, missingNeighborhoods: missing)
  }

  static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .filter { $0.isLetter || $0.isNumber }
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
    case unknownAreaType(String)
    case malformedRow(Int)
    case invalidMonthHeader(String)
    case invalidRent(Int, String)
  }

  /// Lossless-or-loud: parses the official wide dashboard export, retaining only its
  /// newest 12 monthly values for neighborhoods and rejecting unknown structure.
  public static func parse(_ data: Data) throws -> NeighborhoodRentDataset {
    guard var text = String(data: data, encoding: .utf8) else { throw ImportError.invalidUTF8 }
    if text.first == "\u{feff}" { text.removeFirst() }
    let rows = try CSVRows.parse(text)
    guard let header = rows.first, !header.isEmpty else { throw ImportError.missingHeader }
    guard header.count >= 4 else { throw ImportError.missingHeader }
    guard Array(header.prefix(3)) == ["areaName", "Borough", "areaType"] else {
      throw ImportError.unknownHeader(header.first(where: { !["areaName", "Borough", "areaType"].contains($0) }) ?? header[0])
    }
    let months = Array(header.dropFirst(3))
    if let unknown = months.first(where: { !isMonth($0) }) { throw ImportError.unknownHeader(unknown) }
    guard monthsHaveConsecutiveOrder(months) else { throw ImportError.invalidMonthHeader("nonconsecutive months") }
    guard rows.count > 1 else { throw ImportError.noRows }
    let recentMonths = Array(months.suffix(12))
    let offset = months.count - recentMonths.count
    var result: [NeighborhoodRentPoint] = []
    var areaNames: [String] = []
    for (rowOffset, row) in rows.dropFirst().enumerated() {
      let csvLine = rowOffset + 2
      guard row.count == header.count else { throw ImportError.malformedRow(csvLine) }
      let areaType = row[2]
      guard ["borough", "city", "neighborhood"].contains(areaType) else {
        throw ImportError.unknownAreaType(areaType)
      }
      guard areaType == "neighborhood" else { continue }
      let neighborhood = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
      areaNames.append(neighborhood)
      for (recentOffset, month) in recentMonths.enumerated() {
        let cell = row[3 + offset + recentOffset].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cell.isEmpty else { continue }
        guard let amount = Double(cell), amount.isFinite, amount > 0 else {
          throw ImportError.invalidRent(csvLine, month)
        }
        result.append(NeighborhoodRentPoint(neighborhood: neighborhood, month: month, median2BRRent: amount))
      }
    }
    return NeighborhoodRentDataset(areaNames: areaNames, points: result)
  }

  public static func date(for month: String) -> Date? {
    let parts = month.split(separator: "-")
    guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: year, month: month, day: 1))
  }

  public static func isOlderThanSixMonths(_ month: String, relativeTo date: Date, calendar: Calendar = .current) -> Bool {
    guard let storedIndex = monthIndex(month) else { return false }
    let components = calendar.dateComponents([.year, .month], from: date)
    guard let year = components.year, let currentMonth = components.month else { return false }
    return year * 12 + currentMonth - storedIndex > 6
  }

  private static func isMonth(_ value: String) -> Bool {
    let parts = value.split(separator: "-")
    guard parts.count == 2, parts[0].count == 4, let year = Int(parts[0]),
      let month = Int(parts[1]) else { return false }
    return (1900...2200).contains(year) && (1...12).contains(month)
  }

  private static func monthsHaveConsecutiveOrder(_ months: [String]) -> Bool {
    guard months.count > 1 else { return true }
    for index in 1..<months.count {
      guard let previous = monthIndex(months[index - 1]), let current = monthIndex(months[index]),
        current == previous + 1 else { return false }
    }
    return true
  }

  private static func monthIndex(_ value: String) -> Int? {
    let parts = value.split(separator: "-")
    guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
      return nil
    }
    return year * 12 + month
  }
}

extension NeighborhoodRentCSV.ImportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidUTF8: "The CSV file is not UTF-8 text."
    case .noRows: "The CSV has no neighborhood rent rows."
    case .missingHeader: "The CSV must contain areaName, Borough, areaType, and monthly YYYY-MM columns."
    case .unknownHeader(let header): "Unknown CSV column: \(header). The file was not imported."
    case .unknownAreaType(let areaType): "Unknown StreetEasy area type: \(areaType). The file was not imported."
    case .malformedRow(let line): "CSV row \(line) has the wrong number of columns."
    case .invalidMonthHeader(let month): "Unknown or out-of-order CSV month column: \(month)."
    case .invalidRent(let line, let month): "CSV row \(line) has an invalid rent for \(month)."
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

public enum StreetEasyPageReducer {
  private struct Element {
    var name: String
    var suppressed: Bool
    var start: String.Index
  }

  private static let hiddenElements: Set<String> = [
    "head", "script", "style", "svg", "noscript", "template", "iframe", "nav", "header", "footer",
  ]
  private static let blockElements: Set<String> = ["section", "article", "aside", "div", "main"]

  /// Intentionally lossy: drops markup and non-visible/interface content, plus similar-home blocks;
  /// retains bounded visible text for an on-device listing review.
  public static func reduce(_ html: String, maximumCharacters: Int = RentListingExtractor.maximumInputCharacters) -> String {
    let pattern = #"<!--(?s:.*?)-->|<[^>]*>|[^<]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
    var output = ""
    var stack: [Element] = []
    let range = NSRange(html.startIndex..., in: html)
    for match in regex.matches(in: html, range: range) {
      guard let tokenRange = Range(match.range, in: html) else { continue }
      let token = String(html[tokenRange])
      if token.hasPrefix("<!--") { continue }
      if token.hasPrefix("<") {
        if token.hasPrefix("</") {
          let name = tagName(token)
          if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
          continue
        }
        let name = tagName(token)
        guard !name.isEmpty else { continue }
        let attributes = token.lowercased()
        let inherited = stack.last?.suppressed ?? false
        let isSimilar = ["similar", "related-homes", "related_homes"].contains(where: attributes.contains)
        let hiddenAttribute = attributes.contains(" hidden")
          || attributes.contains("aria-hidden=\"true\"")
          || attributes.contains("aria-hidden='true'")
          || (attributes.contains("style=") && attributes.contains("display:none"))
        let suppressed = inherited || hiddenElements.contains(name) || isSimilar || hiddenAttribute
        stack.append(Element(name: name, suppressed: suppressed, start: output.endIndex))
      } else if stack.allSatisfy({ !$0.suppressed }) {
        let visible = decodeEntities(token)
        let collapsed = visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { continue }
        if collapsed.localizedCaseInsensitiveContains("similar homes"),
           let block = stack.lastIndex(where: { blockElements.contains($0.name) }) {
          let start = stack[block].start
          output = String(output[..<start])
          for index in block..<stack.count { stack[index].suppressed = true }
          continue
        }
        if !output.isEmpty, output.last?.isWhitespace == false { output.append(" ") }
        output.append(contentsOf: collapsed)
      }
    }
    let normalized = output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard normalized.count > maximumCharacters else { return normalized }
    let lower = normalized.lowercased()
    let markers = ["for rent", "rental unit", " beds", "bedroom"]
    let start = markers.compactMap { marker in lower.range(of: marker)?.lowerBound }
      .min() ?? lower.startIndex
    let contextStart = normalized.index(start, offsetBy: -min(2_000, normalized.distance(from: normalized.startIndex, to: start)))
    let contextEnd = normalized.index(contextStart, offsetBy: maximumCharacters, limitedBy: normalized.endIndex) ?? normalized.endIndex
    return String(normalized[contextStart..<contextEnd])
  }

  private static func tagName(_ token: String) -> String {
    let content = token.dropFirst().drop(while: { $0.isWhitespace || $0 == "/" })
    return String(content.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased())
  }

  private static func decodeEntities(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
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
  public static let maximumInputCharacters = 10_000
  public static let instructions = """
    Extract only rental units explicitly shown in this rendered StreetEasy page.
    Return JSON only: {"listings":[{"rent":4395,"unit":"1F","squareFeet":null}]}.
    Include only 2-bedroom rentals. Do not infer unit, square feet, or rent. Do not
    include similar homes or historical prices. Return an empty array when none qualify.
    """

  public static func extract(
    from html: String, sourceURL: URL, using modelClient: any ModelClient
  ) async throws -> [RentListingCandidate] {
    let visibleText = StreetEasyPageReducer.reduce(html)
    let request = ModelRequest(
      tier: .onDevice,
      system: instructions,
      prompt: "Source URL: \(sourceURL.absoluteString)\nVisible listing page text:\n\(visibleText)",
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
