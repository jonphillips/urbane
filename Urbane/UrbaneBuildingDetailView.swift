import CoreLocation
import MapKit
import SwiftUI
import UIKit
import UrbaneCore
import UrbaneSchema
import WebExtractorKit

private struct BrowserDestination: Identifiable {
  var id: String { url.absoluteString }
  let url: URL
  let title: String
}

struct BuildingDetailSheet: View {
  let building: Building
  let model: UrbaneMapModel
  @State private var postcard: UIImage?
  @State private var showingBrowser = false
  @State private var browserDestination: BrowserDestination?
  @State private var imageCandidates: [URL] = []
  @State private var imageError: String?
  @State private var selectedReviewURL: BrowserDestination?
  @State private var editingVignette: BuildingVignette?
  @State private var addingVignette = false
  @State private var fixingLocation = false

  private let imageryClient = UrbaneImageryClient()

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          TabView {
          if let postcard {
              GalleryImage(image: postcard, title: "3D map")
          } else {
              PostcardFallback(building: building)
          }
          let vignettes = model.buildingVignettes.filter { $0.buildingID == building.id }.sorted { $0.sortOrder < $1.sortOrder }
          if vignettes.isEmpty {
            GalleryUnavailable(title: "No Look Around views yet", detail: "Add a nearby place below to build the street level gallery.")
          } else {
            ForEach(vignettes) { vignette in
              LookAroundGalleryPage(vignette: vignette) { editingVignette = vignette }
            }
          }
          if let data = building.heroImage, let hero = UIImage(data: data) {
              GalleryImage(image: hero, title: "Chosen building image")
          }
          }
          .tabViewStyle(.page(indexDisplayMode: .automatic))
          .frame(height: 220)
        }
        .padding(.vertical, 4)
      }

      Section {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(building.name).font(.title2.weight(.semibold))
            Text(building.address).foregroundStyle(.secondary)
            Text(statusLabel).font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Fix location", systemImage: "mappin.and.ellipse") { fixingLocation = true }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Fix building location")
        }
        if !building.summary.isEmpty { Text(building.summary) }
      }

      Section("Rent band") {
        Label("Dated rental listings will appear here.", systemImage: "calendar")
          .foregroundStyle(.secondary)
      }

      Section("What renters say") {
        let reviews = model.reviews.filter { $0.buildingID == building.id }
        if reviews.isEmpty {
          Text("No reviews imported yet.").foregroundStyle(.secondary)
        } else {
          ForEach(reviews.sorted { $0.gatheredAt > $1.gatheredAt }) { review in
            Button {
              guard let url = URL(string: review.sourceURL) else { return }
              selectedReviewURL = BrowserDestination(url: url, title: review.source)
            } label: {
              ReviewCard(review: review)
                .opacity(isStale(review.gatheredAt) ? 0.58 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }

      Section {
        let vignettes = model.buildingVignettes.filter { $0.buildingID == building.id }.sorted { $0.sortOrder < $1.sortOrder }
        if vignettes.isEmpty {
          Text("Add a few nearby corners that make the block feel like home.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(vignettes) { vignette in
            Button { editingVignette = vignette } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(vignette.placeName).font(.headline).foregroundStyle(.primary)
                Text(vignette.caption).font(.subheadline).foregroundStyle(.secondary)
              }
              .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
          }
          .onMove { model.moveBuildingVignettes(buildingID: building.id, from: $0, to: $1) }
          .onDelete { offsets in
            for offset in offsets where vignettes.indices.contains(offset) {
              model.deleteBuildingVignette(vignettes[offset])
            }
          }
        }
        Button("Add place", systemImage: "plus") { addingVignette = true }
      } header: {
        HStack {
          Text("Around the block")
          Spacer()
          EditButton().labelStyle(.iconOnly)
        }
      }

      if let imageError { Section { Text(imageError).foregroundStyle(.red) } }
    }
    .navigationTitle("Building")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Choose hero image", systemImage: "photo") { openHeroBrowser() }
            .disabled(building.websiteURL.flatMap(URL.init(string:)) == nil)
          Button("Open building website", systemImage: "safari") { openBuildingSite() }
            .disabled(building.websiteURL.flatMap(URL.init(string:)) == nil)
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .task { await loadImagery() }
    .sheet(isPresented: $showingBrowser) {
      if let browserDestination {
        WebExtractorBrowser(
          startURL: browserDestination.url, title: browserDestination.title, confirmLabel: "Choose image"
        ) { html, pageURL in
          imageCandidates = Self.imageURLs(in: html, baseURL: pageURL ?? browserDestination.url)
          return .extracted
        }
      }
    }
    .sheet(item: $selectedReviewURL) { destination in
      WebExtractorBrowser(startURL: destination.url, title: destination.title, confirmLabel: "Done") { _, _ in .extracted }
    }
    .sheet(isPresented: $addingVignette) {
      BuildingVignetteEditor(building: building, model: model, vignette: nil)
    }
    .sheet(item: $editingVignette) { vignette in
      BuildingVignetteEditor(building: building, model: model, vignette: vignette)
    }
    .sheet(isPresented: $fixingLocation) { BuildingLocationSheet(building: building, model: model) }
    .confirmationDialog("Choose the building's hero image", isPresented: Binding(
      get: { !imageCandidates.isEmpty }, set: { if !$0 { imageCandidates = [] } }
    )) {
      ForEach(Array(imageCandidates.prefix(8)), id: \.absoluteString) { url in
        Button(url.host ?? url.lastPathComponent) { Task { await saveHeroImage(from: url) } }
      }
    } message: {
      Text("Choose an image from the building's website.")
    }
  }

  private var statusLabel: String {
    switch building.status {
    case .exploring: "Exploring"
    case .watching: "Watching"
    case .tourCandidate: "Tour candidate"
    case .rejected: "Passed"
    }
  }

  private func loadImagery() async {
    postcard = await imageryClient.postcard(
      latitude: building.latitude, longitude: building.longitude, mapItemIdentifier: building.mapItemIdentifier
    )
  }

  private func openHeroBrowser() {
    guard let url = building.websiteURL.flatMap(URL.init(string:)) else { return }
    browserDestination = BrowserDestination(url: url, title: "Choose hero image")
    showingBrowser = true
  }

  private func openBuildingSite() {
    guard let url = building.websiteURL.flatMap(URL.init(string:)) else { return }
    selectedReviewURL = BrowserDestination(url: url, title: building.name)
  }

  private func saveHeroImage(from url: URL) async {
    imageCandidates = []
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
            let image = UIImage(data: data), let resized = Self.downscaled(image, maxEdge: 1600),
            let jpeg = resized.jpegData(compressionQuality: 0.86) else {
        imageError = "That page image could not be saved. Try another one."
        return
      }
      model.updateHeroImage(building, image: jpeg)
    } catch { imageError = error.localizedDescription }
  }

  private func isStale(_ date: Date) -> Bool {
    (Calendar.current.dateComponents([.month], from: date, to: .now).month ?? 0) > 6
  }

  private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
  }

  private static func imageURLs(in html: String, baseURL: URL) -> [URL] {
    let patterns = [
      #"<meta[^>]+(?:property|name)=[\"'](?:og:image|twitter:image)[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
      #"<img[^>]+src=[\"']([^\"']+)[\"']"#,
    ]
    var urls: [URL] = []
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
      let range = NSRange(html.startIndex..., in: html)
      for match in regex.matches(in: html, range: range) {
        guard let valueRange = Range(match.range(at: 1), in: html),
              let url = URL(string: String(html[valueRange]), relativeTo: baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), !urls.contains(url) else { continue }
        urls.append(url)
      }
    }
    return urls
  }

}

private struct GalleryImage: View {
  let image: UIImage
  let title: String

  var body: some View {
    Image(uiImage: image).resizable().scaledToFill()
      .frame(maxWidth: .infinity).frame(height: 220)
      .overlay(alignment: .bottomLeading) { GalleryLabel(text: title) }
      .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

private struct GalleryLabel: View {
  let text: String

  var body: some View {
    Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
      .background(.regularMaterial, in: Capsule()).padding(10)
  }
}

private struct GalleryUnavailable: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "binoculars").font(.largeTitle)
      Text(title).font(.headline)
      Text(detail).font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).frame(height: 220)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
  }
}

private struct PostcardFallback: View {
  let building: Building

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: "building.2.crop.circle").font(.largeTitle).foregroundStyle(.secondary)
      Text(building.name).font(.title2.weight(.semibold))
      Text(building.address).font(.subheadline).foregroundStyle(.secondary)
      Text("Map imagery will appear when Apple has coverage.").font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(18).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
  }
}

private struct LookAroundGalleryPage: View {
  let vignette: BuildingVignette
  let onAdjust: () -> Void
  @State private var image: UIImage?
  @State private var scene: MKLookAroundScene?
  private let imageryClient = UrbaneImageryClient()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        } else if let scene {
          LookAroundPreview(initialScene: scene, allowsNavigation: true)
        } else {
          GalleryUnavailable(title: "No Look Around coverage", detail: "The map postcard remains available.")
        }
      }
      .frame(maxWidth: .infinity).frame(height: 174)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(vignette.placeName).font(.subheadline.weight(.semibold))
          Text(vignette.caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer()
        Button("Adjust view", systemImage: "viewfinder", action: onAdjust)
          .labelStyle(.iconOnly).accessibilityLabel("Adjust view for \(vignette.placeName)")
      }
      .padding(.horizontal, 3)
    }
    .task {
      async let snapshot = imageryClient.lookAroundSnapshot(
        latitude: vignette.latitude, longitude: vignette.longitude, mapItemIdentifier: vignette.mapItemIdentifier
      )
      async let liveScene = imageryClient.lookAroundScene(
        latitude: vignette.latitude, longitude: vignette.longitude, mapItemIdentifier: vignette.mapItemIdentifier
      )
      image = await snapshot
      scene = await liveScene
    }
  }
}

private struct ReviewCard: View {
  let review: BuildingReview

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Text(review.source).fontWeight(.semibold)
        Text("· \(review.subject == .building ? "building" : "landlord")")
        if let rating = review.rating, let scale = review.ratingScale {
          Text("· \(rating.formatted(.number.precision(.fractionLength(0...1))))/\(scale.formatted(.number.precision(.fractionLength(0...1))))")
        }
        if let count = review.reviewCount { Text("· \(count) reviews") }
      }
      .font(.subheadline)
      HStack {
        if let month = review.newestReviewMonth { Text("Newest \(month)") }
        Text("Gathered \(review.gatheredAt.formatted(date: .abbreviated, time: .omitted))")
      }.font(.caption).foregroundStyle(.secondary)
      Text(review.summary).font(.body).foregroundStyle(.primary)
      Label("Open source", systemImage: "arrow.up.right.square").font(.caption)
    }
    .padding(.vertical, 3)
  }
}

private struct BuildingVignetteEditor: View {
  let building: Building
  let model: UrbaneMapModel
  let vignette: BuildingVignette?
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  @State private var caption: String
  @State private var results: [PlaceMatch] = []
  @State private var selected: PlaceMatch?
  @State private var error: String?
  @State private var scene: MKLookAroundScene?
  @State private var snapshot: UIImage?
  @State private var camera: MapCameraPosition
  private let imageryClient = UrbaneImageryClient()

  init(building: Building, model: UrbaneMapModel, vignette: BuildingVignette?) {
    self.building = building
    self.model = model
    self.vignette = vignette
    _query = State(initialValue: vignette?.placeName ?? "")
    _caption = State(initialValue: vignette?.caption ?? "")
    _selected = State(initialValue: nil)
    _camera = State(initialValue: .region(MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: vignette?.latitude ?? building.latitude, longitude: vignette?.longitude ?? building.longitude),
      span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )))
    if let vignette {
      _selected = State(initialValue: PlaceMatch(
        name: vignette.placeName, address: vignette.placeName,
        latitude: vignette.latitude, longitude: vignette.longitude,
        mapItemIdentifier: vignette.mapItemIdentifier
      ))
    }
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
        Section("Look Around view") {
          if let snapshot {
            Image(uiImage: snapshot).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
          } else if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true)
              .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            ContentUnavailableView("No still available", systemImage: "binoculars")
              .frame(height: 130)
          }
          MapReader { proxy in
            Map(position: $camera) {
              if let selected {
                Annotation("Viewpoint", coordinate: CLLocationCoordinate2D(latitude: selected.latitude, longitude: selected.longitude)) {
                  Image(systemName: "mappin.and.ellipse").font(.title).foregroundStyle(.red)
                }.annotationTitles(.hidden)
              }
            }
            .onTapGesture(coordinateSpace: .local) { point in
              guard let coordinate = proxy.convert(point, from: .local) else { return }
              selected = PlaceMatch(name: query, address: query, latitude: coordinate.latitude, longitude: coordinate.longitude, mapItemIdentifier: nil)
            }
            .frame(height: 190)
          }
          Text("Choose a nearby map place above, or tap a point on the map.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        TextField("Why this place matters", text: $caption, axis: .vertical)
          .lineLimit(2...5)
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle(vignette == nil ? "Add a place" : "Adjust view")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard let selected else { return }
            if let vignette { model.updateBuildingVignette(vignette, place: selected, caption: caption) }
            else { model.addBuildingVignette(building: building, place: selected, caption: caption) }
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
      if results.isEmpty { error = "No match found. You can save the current coordinate and edit it later." }
      else { error = nil }
    } catch { self.error = error.localizedDescription }
  }

  private func loadPreview() async {
    guard let selected else { snapshot = nil; scene = nil; return }
    async let image = imageryClient.lookAroundSnapshot(
      latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier
    )
    async let liveScene = imageryClient.lookAroundScene(
      latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier
    )
    snapshot = await image
    scene = await liveScene
  }
}
