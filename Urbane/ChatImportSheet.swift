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
  @State private var searching = false
  @State private var reviewing = false

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
              Button(searching ? "Searching places…" : "Review import") { Task { await prepareReview() } }
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
            }
          }
        }
      }
      .navigationTitle("Import from chat")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }

  @ViewBuilder private func review(_ paste: ChatImportPaste) -> some View {
    List {
      if let warning = paste.warning {
        Section { Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
      }
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
      let knownNames = Set(paste.neighborhoods.map { UrbaneMapModel.normalize($0.name) })
      let ungrouped = Array(paste.buildings.enumerated().filter { !knownNames.contains(UrbaneMapModel.normalize($0.element.neighborhood)) })
      if !ungrouped.isEmpty {
        Section("Unresolved neighborhood") {
          ForEach(ungrouped, id: \.offset) { index, building in buildingReview(building, index: index) }
          let otherNames = Array(Set(ungrouped.map { $0.element.neighborhood })).sorted()
          ForEach(otherNames, id: \.self) { name in
            resolutionRow("x\(UrbaneMapModel.normalize(name))", title: "Resolve neighborhood · \(name)")
          }
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

  @ViewBuilder private func buildingReview(_ building: ChatBuilding, index: Int) -> some View {
    let existing = existingBuilding(building.address)
    VStack(alignment: .leading, spacing: 8) {
      Text("\(building.name) · \(existing == nil ? "new" : "already in Urbane")").font(.headline)
      Text("\(building.address) · \(String(describing: building.status))").font(.footnote).foregroundStyle(.secondary)
      resolutionRow("b\(index)", title: "Building location")
      if let existing, !existing.summary.isEmpty {
        Text("Urbane: \(existing.summary)").font(.footnote).foregroundStyle(.secondary)
      }
      ForEach(Array(building.reviews.enumerated()), id: \.offset) { reviewIndex, review in
        let key = "b\(index)r\(reviewIndex)"
        let old = model.reviews.first { $0.buildingID == existing?.id && $0.source == review.source && $0.subject == (review.subject == .building ? .building : .landlord) }
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
        Label("Unresolved — search returned no match", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
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

  private func prepareReview() async {
    searching = true
    error = nil
    defer { searching = false }
    do {
      let decoded = try ChatImportDecoder.decode(pasteText)
      paste = decoded
      var nextChoices: [String: [PlaceMatch]] = [:]
      var nextIDs: [String: String] = [:]
      var nextReviewReplacements: Set<String> = []
      for (index, neighborhood) in decoded.neighborhoods.enumerated() {
        let matches = try await model.search("\(neighborhood.name), New York, NY")
        nextChoices["n\(index)"] = matches
        if matches.count == 1 { nextIDs["n\(index)"] = matches[0].id }
        for (vIndex, vignette) in neighborhood.vignettes.enumerated() {
          let places = try await model.search("\(vignette.place), \(neighborhood.name), New York, NY")
          let key = "n\(index)v\(vIndex)"
          nextChoices[key] = places
          if places.count == 1 { nextIDs[key] = places[0].id }
        }
      }
      for (index, building) in decoded.buildings.enumerated() {
        let matches = try await model.search("\(building.name), \(building.address), New York, NY")
        let key = "b\(index)"
        nextChoices[key] = matches
        if matches.count == 1 { nextIDs[key] = matches[0].id }
        let oldBuilding = existingBuilding(building.address)
        for (reviewIndex, review) in building.reviews.enumerated() {
          if let oldBuilding, model.reviews.contains(where: { $0.buildingID == oldBuilding.id && $0.source == review.source && $0.subject == (review.subject == .building ? .building : .landlord) }) {
            nextReviewReplacements.insert("b\(index)r\(reviewIndex)")
          }
        }
      }
      let declared = Set(decoded.neighborhoods.map { UrbaneMapModel.normalize($0.name) })
      let otherNames = Set(decoded.buildings.map(\.neighborhood).filter { !declared.contains(UrbaneMapModel.normalize($0)) })
      for name in otherNames {
        let key = "x\(UrbaneMapModel.normalize(name))"
        let matches = try await model.search("\(name), New York, NY")
        nextChoices[key] = matches
        if matches.count == 1 { nextIDs[key] = matches[0].id }
      }
      choices = nextChoices
      selectedIDs = nextIDs
      replaceReviews = nextReviewReplacements
      skipped = []
      reviewing = true
    } catch { self.error = error.localizedDescription }
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
    choices.count > 0 && choices.allSatisfy { key, matches in
      skipped.contains(key) || (!matches.isEmpty && matches.contains(where: { $0.id == selectedIDs[key] }))
    } && paste.neighborhoods.enumerated().allSatisfy { index, n in
      (selectedIDs["n\(index)"] != nil || skipped.contains("n\(index)")) && n.vignettes.indices.allSatisfy { selectedIDs["n\(index)v\($0)"] != nil || skipped.contains("n\(index)v\($0)") }
    } && paste.buildings.indices.allSatisfy { selectedIDs["b\($0)"] != nil || skipped.contains("b\($0)") }
      && Set(paste.buildings.map(\.neighborhood).map(UrbaneMapModel.normalize)).allSatisfy { name in
        paste.neighborhoods.contains(where: { UrbaneMapModel.normalize($0.name) == name }) || selectedIDs["x\(name)"] != nil || skipped.contains("x\(name)")
      }
  }

  private func existingNeighborhood(_ name: String) -> Neighborhood? {
    model.neighborhoods.first { UrbaneMapModel.normalize($0.name) == UrbaneMapModel.normalize(name) }
  }
  private func existingBuilding(_ address: String) -> Building? {
    model.buildings.first { UrbaneMapModel.normalize($0.address) == UrbaneMapModel.normalize(address) }
  }
  private func idBinding(_ key: String) -> Binding<String> {
    Binding(get: { selectedIDs[key] ?? "" }, set: { selectedIDs[key] = $0 })
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
