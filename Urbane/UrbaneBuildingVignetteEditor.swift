import MapKit
import SwiftUI
import UIKit
import UrbaneCore
import UrbaneSchema

struct BuildingVignetteEditor: View {
  let building: Building
  let model: UrbaneMapModel
  let vignette: BuildingVignette?
  let onSave: (UUID) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  @State private var caption: String
  @State private var results: [PlaceMatch] = []
  @State private var selected: PlaceMatch?
  @State private var error: String?
  @State private var scene: MKLookAroundScene?
  @State private var snapshot: UIImage?
  private let imageryClient = UrbaneImageryClient()

  init(
    building: Building, model: UrbaneMapModel, vignette: BuildingVignette?,
    onSave: @escaping (UUID) -> Void = { _ in }
  ) {
    self.building = building
    self.model = model
    self.vignette = vignette
    self.onSave = onSave
    _query = State(initialValue: vignette?.placeName ?? "")
    _caption = State(initialValue: vignette?.caption ?? "")
    _selected = State(initialValue: vignette.map {
      PlaceMatch(
        name: $0.placeName, address: $0.placeName,
        latitude: $0.latitude, longitude: $0.longitude, mapItemIdentifier: $0.mapItemIdentifier
      )
    })
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Place or corner", text: $query)
        Button("Search nearby places") { Task { await search() } }.disabled(query.isEmpty)
        ForEach(results) { place in
          Button {
            selected = place
            if caption.isEmpty { caption = place.name }
          } label: {
            Label("\(place.name) · \(place.address)", systemImage: selected?.id == place.id ? "checkmark.circle.fill" : "mappin")
          }
        }
        Section("Look Around") {
          if let snapshot {
            Image(uiImage: snapshot).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
          } else if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true)
              .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 12))
          } else if selected == nil {
            ContentUnavailableView("Search for a place", systemImage: "magnifyingglass")
              .frame(height: 130)
          } else {
            ContentUnavailableView("No still available", systemImage: "binoculars")
              .frame(height: 130)
          }
        }
        TextField("Why this place matters", text: $caption, axis: .vertical)
          .lineLimit(2...5)
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle(vignette == nil ? "Add a place" : "Edit place")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard let selected else { return }
            if let vignette {
              model.updateBuildingVignette(vignette, place: selected, caption: caption)
            } else {
              let id = model.addBuildingVignette(building: building, place: selected, caption: caption)
              onSave(id)
            }
            dismiss()
          }.disabled(selected == nil)
        }
      }
      .task { if vignette != nil { await search() } }
      .task(id: selected?.id) { await loadPreview() }
    }
  }

  private func search() async {
    do {
      results = try await model.search("\(query), near \(building.address), New York, NY")
      if results.isEmpty { error = "No match found. Try another name or address." }
      else { error = nil }
    } catch { self.error = error.localizedDescription }
  }

  private func loadPreview() async {
    guard let selected else { snapshot = nil; scene = nil; return }
    let image = await imageryClient.lookAroundSnapshot(
      latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier
    )
    snapshot = image
    scene = image == nil
      ? await imageryClient.lookAroundScene(latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier)
      : nil
  }
}
