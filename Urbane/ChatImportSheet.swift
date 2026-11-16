import SwiftUI
import UrbaneCore
import UrbaneSchema

struct ChatImportSheet: View {
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var pasteText = ""
  @State private var paste: ChatImportPaste?
  @State private var choices: [String: [PlaceMatch]] = [:]
  @State private var selectedIDs: [String: String] = [:]
  @State private var skipped: Set<String> = []
  @State private var replaceChapters: Set<Int> = []
  @State private var replaceReviews: Set<String> = []
  @State private var error: String?
  @State private var rowErrors: [String: String] = [:]
  @State private var failedSearchKeys: Set<String> = []
  @State private var resolvedPlaces = 0
  @State private var totalPlaces = 0
  @State private var searching = false
  @State private var reviewing = false
  @State private var resolutionTask: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      Group {
        if reviewing, let paste {
          review(paste)
        } else {
          Form {
            Section("Paste the chat result") {
              TextEditor(text: $pasteText).frame(minHeight: 180)
              if let error { Text(error).foregroundStyle(.red) }
              if searching {
                ChatImportProgress(resolved: resolvedPlaces, total: totalPlaces, waitingFor: model.placeSearchWaitingFor)
              }
              Button(searching ? "Resolving places…" : "Review import") {
                resolutionTask = Task { await prepareReview() }
              }
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
            }
          }
        }
      }
      .navigationTitle("Import from chat")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { resolutionTask?.cancel(); dismiss() }
        }
      }
    }
  }

  @ViewBuilder private func review(_ paste: ChatImportPaste) -> some View {
    List {
      if searching || !failedSearchKeys.isEmpty {
        Section {
          ChatImportProgress(
            resolved: resolvedPlaces,
            total: totalPlaces,
            waitingFor: model.placeSearchWaitingFor,
            canRetry: !failedSearchKeys.isEmpty,
            isRetryDisabled: searching,
            retry: { resolutionTask = Task { await retryFailedRows(in: paste) } }
          )
        }
      }
      if let warning = paste.warning {
        Section { Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
      }
      neighborhoodSections(paste)
      let declaredNames = Set(paste.neighborhoods.map { UrbaneMapModel.normalize($0.name) })
      let existingGroups = model.neighborhoods.filter { neighborhood in
        !declaredNames.contains(UrbaneMapModel.normalize(neighborhood.name))
          && paste.buildings.contains { UrbaneMapModel.normalize($0.neighborhood) == UrbaneMapModel.normalize(neighborhood.name) }
      }
      ForEach(existingGroups) { neighborhood in
        Section(neighborhood.name) {
          Text("Neighborhood · already in Urbane")
          ForEach(Array(paste.buildings.enumerated().filter { UrbaneMapModel.normalize($0.element.neighborhood) == UrbaneMapModel.normalize(neighborhood.name) }), id: \.offset) { buildingIndex, building in
            buildingReview(building, index: buildingIndex)
          }
        }
      }
      let ungrouped = Array(paste.buildings.enumerated().filter {
        !declaredNames.contains(UrbaneMapModel.normalize($0.element.neighborhood)) && existingNeighborhood($0.element.neighborhood) == nil
      })
      if !ungrouped.isEmpty {
        Section("Unresolved neighborhood") {
          ForEach(ungrouped, id: \.offset) { index, building in buildingReview(building, index: index) }
        }
      }
      Section {
        Button("Import") { commit(paste) }
          .disabled(!hasAllResolutions(paste))
      } footer: {
        Text("Nothing is saved until Import. Every place must have one selected MapKit match.")
      }
    }
  }

  @ViewBuilder private func neighborhoodSections(_ paste: ChatImportPaste) -> some View {
    ForEach(Array(paste.neighborhoods.enumerated()), id: \.offset) { index, neighborhood in
      Section(neighborhood.name) {
        Text("Neighborhood · \(existingNeighborhood(neighborhood.name) == nil ? "new" : "already in Urbane")")
        resolutionRow("n\(index)", title: "Neighborhood region")
        if let old = existingNeighborhood(neighborhood.name), !old.chapter.isEmpty, let chapter = neighborhood.chapter {
          Toggle("Replace chapter", isOn: chapterBinding(index))
          DisclosureGroup("Compare chapter text") {
            VStack(alignment: .leading) {
              Text("Urbane: \(old.chapter)").foregroundStyle(.secondary)
              Text("Chat: \(chapter)")
            }.font(.footnote)
          }
        } else if let chapter = neighborhood.chapter {
          DisclosureGroup("New chapter") { Text(chapter).font(.footnote) }
        }
        ForEach(Array(neighborhood.vignettes.enumerated()), id: \.offset) { vignetteIndex, vignette in
          resolutionRow("n\(index)v\(vignetteIndex)", title: "\(vignette.place) · \(vignette.caption)")
        }
        ForEach(Array(paste.buildings.enumerated().filter { UrbaneMapModel.normalize($0.element.neighborhood) == UrbaneMapModel.normalize(neighborhood.name) }), id: \.offset) { buildingIndex, building in
          buildingReview(building, index: buildingIndex)
        }
      }
    }
  }

  @ViewBuilder private func buildingReview(_ building: ChatBuilding, index: Int) -> some View {
    let match = selectedPlace("b\(index)")
    let existing = existingBuilding(building.address, mapItemIdentifier: match?.mapItemIdentifier)
    VStack(alignment: .leading, spacing: 8) {
      Text("\(building.name) · \(existing == nil ? "new" : "already in Urbane")").font(.headline)
      Text("\(building.address) · \(String(describing: building.status))").font(.footnote).foregroundStyle(.secondary)
      if paste?.neighborhoods.contains(where: { UrbaneMapModel.normalize($0.name) == UrbaneMapModel.normalize(building.neighborhood) }) == true || existingNeighborhood(building.neighborhood) != nil {
        resolutionRow("b\(index)", title: "Building location")
      } else {
        Label("Unresolved — neighborhood not in this paste or in Urbane", systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.orange)
        Toggle("Skip this building", isOn: skipBinding("b\(index)"))
      }
      if let existing, !existing.summary.isEmpty {
        Text("Urbane: \(existing.summary)").font(.footnote).foregroundStyle(.secondary)
      }
      ForEach(Array(building.reviews.enumerated()), id: \.offset) { reviewIndex, review in
        let key = "b\(index)r\(reviewIndex)"
        let old = existing.flatMap { ChatImportReconciliation.matchingReview(buildingID: $0.id, source: review.source, subject: review.subject == .building ? .building : .landlord, among: model.reviews) }
        if let old {
          Toggle("Replace \(review.source) · \(review.subject.rawValue) review", isOn: reviewBinding(key))
          Text("Old: \(old.summary) → New: \(review.summary)").font(.caption).foregroundStyle(.secondary)
        } else {
          Text("New review · \(review.source) · \(review.subject.rawValue)").font(.footnote)
        }
      }
    }
    .padding(.vertical, 5)
  }

  private func resolutionRow(_ key: String, title: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.subheadline)
      let matches = choices[key] ?? []
      if matches.isEmpty {
        Label(rowErrors[key].map { "Search failed: \($0)" } ?? "Unresolved — search returned no match", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      } else {
        Picker("Choose place", selection: idBinding(key)) {
          Text("Choose a match").tag("")
          ForEach(matches) { match in
            Text("\(match.name) · \(match.address)").tag(match.id)
          }
        }
        .pickerStyle(.menu)
        if matches.count > 1 { Text("Several matches · select the right place").font(.caption).foregroundStyle(.orange) }
      }
      Toggle("Skip this row", isOn: skipBinding(key))
    }
  }

  // swiftlint:disable function_body_length
  private func prepareReview() async {
    searching = true
    error = nil
    model.placeSearchWaitingFor = nil
    defer { searching = false; resolutionTask = nil; model.placeSearchWaitingFor = nil }
    do {
      let decoded = try ChatImportDecoder.decode(pasteText)
      paste = decoded
      var nextChoices: [String: [PlaceMatch]] = [:]
      var nextIDs: [String: String] = [:]
      var nextReviewReplacements: Set<String> = []
      let declared = Set(decoded.neighborhoods.map { UrbaneMapModel.normalize($0.name) })
      let validBuildingNeighborhoods = Set(decoded.buildings.map(\.neighborhood).filter {
        declared.contains(UrbaneMapModel.normalize($0)) || existingNeighborhood($0) != nil
      }.map(UrbaneMapModel.normalize))
      totalPlaces = decoded.neighborhoods.count + decoded.neighborhoods.reduce(0) { $0 + $1.vignettes.count }
        + decoded.buildings.filter { validBuildingNeighborhoods.contains(UrbaneMapModel.normalize($0.neighborhood)) }.count
      resolvedPlaces = 0
      rowErrors = [:]
      failedSearchKeys = []
      for (index, neighborhood) in decoded.neighborhoods.enumerated() {
        let key = "n\(index)"
        let matches = try await searchRow("\(neighborhood.name), New York, NY", key: key)
        nextChoices[key] = matches
        if matches.count == 1 { nextIDs["n\(index)"] = matches[0].id }
      }
      for (index, building) in decoded.buildings.enumerated() {
        let key = "b\(index)"
        guard validBuildingNeighborhoods.contains(UrbaneMapModel.normalize(building.neighborhood)) else {
          rowErrors[key] = "Neighborhood is not in this paste or in Urbane. Skip this building to continue."
          continue
        }
        let matches = try await searchRow("\(building.name), \(building.address), New York, NY", key: key)
        nextChoices[key] = matches
        if matches.count == 1 { nextIDs[key] = matches[0].id }
        let chosenMatch = matches.first { $0.id == nextIDs[key] }
        let oldBuilding = existingBuilding(building.address, mapItemIdentifier: chosenMatch?.mapItemIdentifier)
        for (reviewIndex, review) in building.reviews.enumerated() {
          if let oldBuilding, ChatImportReconciliation.matchingReview(buildingID: oldBuilding.id, source: review.source, subject: review.subject == .building ? .building : .landlord, among: model.reviews) != nil {
            nextReviewReplacements.insert("b\(index)r\(reviewIndex)")
          }
        }
      }
      for (index, neighborhood) in decoded.neighborhoods.enumerated() {
        for (vIndex, vignette) in neighborhood.vignettes.enumerated() {
          let key = "n\(index)v\(vIndex)"
          let places = try await searchRow("\(vignette.place), \(neighborhood.name), New York, NY", key: key)
          nextChoices[key] = places
          if places.count == 1 { nextIDs[key] = places[0].id }
        }
      }
      choices = nextChoices
      selectedIDs = nextIDs
      replaceReviews = nextReviewReplacements
      skipped = []
      reviewing = true
    } catch is CancellationError {
      return
    } catch { self.error = error.localizedDescription }
  }
  // swiftlint:enable function_body_length

  private func searchRow(_ query: String, key: String) async throws -> [PlaceMatch] {
    do {
      let result = try await model.resolveSearchRow(query)
      resolvedPlaces += 1
      switch result {
      case .matches(let matches):
        rowErrors[key] = nil
        failedSearchKeys.remove(key)
        return matches
      case .unresolved(let message):
        rowErrors[key] = message
        failedSearchKeys.insert(key)
        return []
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      resolvedPlaces += 1
      rowErrors[key] = error.localizedDescription
      failedSearchKeys.insert(key)
      return []
    }
  }

  private func retryFailedRows(in paste: ChatImportPaste) async {
    guard !searching else { return }
    searching = true
    totalPlaces = failedSearchKeys.count
    resolvedPlaces = 0
    model.placeSearchWaitingFor = nil
    defer { searching = false; resolutionTask = nil; model.placeSearchWaitingFor = nil }
    let declared = Set(paste.neighborhoods.map { UrbaneMapModel.normalize($0.name) })
    let validBuildingNeighborhoods = Set(paste.buildings.map(\.neighborhood).filter {
      declared.contains(UrbaneMapModel.normalize($0)) || existingNeighborhood($0) != nil
    }.map(UrbaneMapModel.normalize))
    for (key, query) in ChatImportSearchJobs.make(paste: paste, validBuildingNeighborhoods: validBuildingNeighborhoods)
    where failedSearchKeys.contains(key) {
      let matches: [PlaceMatch]
      do { matches = try await searchRow(query, key: key) }
      catch is CancellationError { return }
      catch { continue }
      choices[key] = matches
      if matches.count == 1, selectedIDs[key] == nil { selectedIDs[key] = matches[0].id }
    }
  }

  private func commit(_ paste: ChatImportPaste) {
    do {
      var resolutions: [String: PlaceMatch] = [:]
      for (key, options) in choices {
        if let selectedID = selectedIDs[key], let match = options.first(where: { $0.id == selectedID }) { resolutions[key] = match }
      }
      try model.importPaste(paste, resolutions: resolutions, skipped: skipped, replaceChapters: replaceChapters, replaceReviews: replaceReviews)
      dismiss()
    } catch { self.error = error.localizedDescription; reviewing = false }
  }

  private func hasAllResolutions(_ paste: ChatImportPaste) -> Bool {
    (!paste.neighborhoods.isEmpty || !paste.buildings.isEmpty)
      && (choices.count > 0 || paste.buildings.indices.allSatisfy { skipped.contains("b\($0)") })
      && choices.allSatisfy { key, matches in
      skipped.contains(key) || (!matches.isEmpty && matches.contains(where: { $0.id == selectedIDs[key] }))
    } && paste.neighborhoods.enumerated().allSatisfy { index, n in
      (selectedIDs["n\(index)"] != nil || skipped.contains("n\(index)")) && n.vignettes.indices.allSatisfy { selectedIDs["n\(index)v\($0)"] != nil || skipped.contains("n\(index)v\($0)") }
    } && paste.buildings.enumerated().allSatisfy { index, building in
      let known = paste.neighborhoods.contains(where: { UrbaneMapModel.normalize($0.name) == UrbaneMapModel.normalize(building.neighborhood) })
        || existingNeighborhood(building.neighborhood) != nil
      if known { return selectedIDs["b\(index)"] != nil || skipped.contains("b\(index)") }
      return skipped.contains("b\(index)")
    }
  }

  private func existingNeighborhood(_ name: String) -> Neighborhood? {
    model.neighborhoods.first { UrbaneMapModel.normalize($0.name) == UrbaneMapModel.normalize(name) }
  }
  private func existingBuilding(_ address: String, mapItemIdentifier: String? = nil) -> Building? {
    ChatImportReconciliation.matchingBuilding(
      mapItemIdentifier: mapItemIdentifier, address: address, among: model.buildings
    )
  }
  private func selectedPlace(_ key: String) -> PlaceMatch? {
    guard let id = selectedIDs[key] else { return nil }
    return choices[key]?.first { $0.id == id }
  }
  private func idBinding(_ key: String) -> Binding<String> {
    Binding(get: { selectedIDs[key] ?? "" }, set: { value in
      selectedIDs[key] = value
      if key.hasPrefix("b"), let index = Int(key.dropFirst()) { setReviewDefaults(forBuildingAt: index) }
    })
  }
  private func setReviewDefaults(forBuildingAt index: Int) {
    guard let paste, paste.buildings.indices.contains(index) else { return }
    let building = paste.buildings[index]
    let existing = existingBuilding(building.address, mapItemIdentifier: selectedPlace("b\(index)")?.mapItemIdentifier)
    for reviewIndex in building.reviews.indices {
      let key = "b\(index)r\(reviewIndex)"
      replaceReviews.remove(key)
      guard let existing else { continue }
      let incoming = building.reviews[reviewIndex]
      let subject: BuildingReviewSubject = incoming.subject == .building ? .building : .landlord
      if ChatImportReconciliation.matchingReview(buildingID: existing.id, source: incoming.source, subject: subject, among: model.reviews) != nil {
        replaceReviews.insert(key)
      }
    }
  }
  private func chapterBinding(_ index: Int) -> Binding<Bool> {
    Binding(get: { replaceChapters.contains(index) }, set: { value in if value { replaceChapters.insert(index) } else { replaceChapters.remove(index) } })
  }
  private func reviewBinding(_ key: String) -> Binding<Bool> {
    Binding(get: { replaceReviews.contains(key) }, set: { value in if value { replaceReviews.insert(key) } else { replaceReviews.remove(key) } })
  }
  private func skipBinding(_ key: String) -> Binding<Bool> {
    Binding(get: { skipped.contains(key) }, set: { value in
      if value { skipped.insert(key); selectedIDs.removeValue(forKey: key) }
      else { skipped.remove(key) }
    })
  }
}

private struct ChatImportProgress: View {
  let resolved: Int
  let total: Int
  var waitingFor: Duration?
  var canRetry = false
  var isRetryDisabled = false
  var retry: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if total > 0 { Text("Resolving \(resolved) of \(total)…") }
      if let duration = waitingFor {
        let seconds = max(1, Int(duration.components.seconds))
        Text("Waiting for Apple Maps (about \(seconds) s)")
      }
      if canRetry {
        Button("Retry failed rows", action: retry).disabled(isRetryDisabled)
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }
}
