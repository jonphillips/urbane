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
  @State private var selectedGalleryPage = "postcard"
  @State private var showingBrowser = false
  @State private var showingImagePicker = false
  @State private var browserDestination: BrowserDestination?
  @State private var imageCandidates: [URL] = []
  @State private var imageError: String?
  @State private var selectedReviewURL: BrowserDestination?
  @State private var editingVignette: BuildingVignette?
  @State private var addingVignette = false
  @State private var fixingLocation = false
  @State private var showingMapViewer = false
  @State private var showingHeroViewer = false
  @State private var fullScreenHero: UIImage?

  private let imageryClient = UrbaneImageryClient()

  private var currentBuilding: Building {
    model.buildings.first { $0.id == building.id } ?? building
  }

  private var imageRecipe: String {
    "\(currentBuilding.latitude)|\(currentBuilding.longitude)|\(currentBuilding.mapItemIdentifier ?? "coordinate")"
  }

  var body: some View {
    VStack(spacing: 0) {
      gallery
      List {
        Section {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text(currentBuilding.name).font(.title2.weight(.semibold))
              Text(currentBuilding.address).foregroundStyle(.secondary)
              Text(statusLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix location", systemImage: "mappin.and.ellipse") { fixingLocation = true }
              .labelStyle(.iconOnly)
              .accessibilityLabel("Fix building location")
          }
          if !currentBuilding.summary.isEmpty { Text(currentBuilding.summary) }
        }

        BuildingRentSection(building: currentBuilding, model: model)
        BuildingCommuteSection(building: currentBuilding, model: model)

        Section("What renters say") {
          let reviews = model.reviews.filter { $0.buildingID == building.id }.sorted { $0.gatheredAt > $1.gatheredAt }
          if reviews.isEmpty {
            Text("No reviews imported yet.").foregroundStyle(.secondary)
          } else {
            ForEach(reviews) { review in
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
            .onDelete { offsets in
              for offset in offsets where reviews.indices.contains(offset) {
                model.deleteBuildingReview(reviews[offset])
              }
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
    }
    .navigationTitle("Building")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Choose hero image", systemImage: "photo") { openHeroBrowser() }
            .disabled(currentBuilding.websiteURL.flatMap(URL.init(string:)) == nil)
          Button("Open building website", systemImage: "safari") { openBuildingSite() }
            .disabled(currentBuilding.websiteURL.flatMap(URL.init(string:)) == nil)
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .task(id: imageRecipe) { await loadImagery() }
    .fullScreenCover(isPresented: $showingMapViewer) {
      FullScreenPostcardMap(building: currentBuilding)
    }
    .fullScreenCover(isPresented: $showingHeroViewer) {
      if let fullScreenHero { FullScreenHeroImage(image: fullScreenHero) }
    }
    .onChange(of: showingBrowser) { _, isShowing in
      if !isShowing, !imageCandidates.isEmpty { showingImagePicker = true }
    }
    .sheet(isPresented: $showingBrowser) {
      if let browserDestination {
        WebExtractorBrowser(
          startURL: browserDestination.url, title: browserDestination.title, confirmLabel: "Choose image"
        ) { html, pageURL in
          imageCandidates = Self.imageURLs(in: html, baseURL: pageURL ?? browserDestination.url)
          guard !imageCandidates.isEmpty else {
            return .notFound(message: "No page images found yet. Navigate to a page with the building photos and try again.")
          }
          return .extracted
        }
      }
    }
    .sheet(item: $selectedReviewURL) { destination in
      WebExtractorBrowser(startURL: destination.url, title: destination.title, confirmLabel: "Done") { _, _ in .extracted }
    }
    .sheet(isPresented: $addingVignette) {
      BuildingVignetteEditor(building: currentBuilding, model: model, vignette: nil) { id in
        selectedGalleryPage = id.uuidString
      }
    }
    .sheet(item: $editingVignette) { vignette in
      BuildingVignetteEditor(building: currentBuilding, model: model, vignette: vignette)
    }
    .sheet(isPresented: $fixingLocation) { BuildingLocationSheet(building: currentBuilding, model: model) }
    .sheet(isPresented: $showingImagePicker) {
      NavigationStack {
        ScrollView {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(Array(imageCandidates.prefix(20)), id: \.absoluteString) { url in
              Button {
                showingImagePicker = false
                Task { await saveHeroImage(from: url) }
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  AsyncImage(url: url) { phase in
                    if let image = phase.image {
                      image.resizable().scaledToFill()
                    } else if phase.error != nil {
                      ContentUnavailableView("Image unavailable", systemImage: "photo")
                    } else {
                      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                  }
                  .frame(height: 132).frame(maxWidth: .infinity)
                  .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                  Text(url.lastPathComponent.isEmpty ? (url.host ?? "Image") : url.lastPathComponent)
                    .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
              }
              .buttonStyle(.plain)
            }
          }
          .padding()
        }
        .navigationTitle("Choose hero image")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingImagePicker = false } } }
      }
    }
  }

  private var gallery: some View {
    VStack(spacing: 8) {
      TabView(selection: $selectedGalleryPage) {
          Button { showingMapViewer = true } label: {
            Group {
              if let postcard {
                GalleryImage(image: postcard, title: "3D map")
              } else {
                PostcardFallback(building: currentBuilding)
              }
            }
          }
          .buttonStyle(.plain)
          .tag("postcard")
          let vignettes = model.buildingVignettes.filter { $0.buildingID == building.id }.sorted { $0.sortOrder < $1.sortOrder }
          if vignettes.isEmpty {
            LookAroundGalleryPage(
              id: "\(currentBuilding.id)-facade", placeName: "Facade", caption: "",
              latitude: currentBuilding.latitude, longitude: currentBuilding.longitude,
              mapItemIdentifier: currentBuilding.mapItemIdentifier
            )
              .tag("facade")
          } else {
            ForEach(vignettes) { vignette in
              LookAroundGalleryPage(vignette: vignette)
                .tag(vignette.id.uuidString)
            }
          }
          if let data = currentBuilding.heroImage, let hero = UIImage(data: data) {
            Button {
              fullScreenHero = hero
              showingHeroViewer = true
            } label: {
              GalleryImage(image: hero, title: "Chosen building image")
            }
            .buttonStyle(.plain)
            .tag("hero")
          }
      }
      .tabViewStyle(.page(indexDisplayMode: .automatic))
      .frame(maxWidth: .infinity)
      .containerRelativeFrame(.vertical) { length, _ in length * 0.55 }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private var statusLabel: String {
    switch currentBuilding.status {
    case .exploring: "Exploring"
    case .watching: "Watching"
    case .tourCandidate: "Tour candidate"
    case .rejected: "Passed"
    }
  }

  private func loadImagery() async {
    postcard = nil
    let recipe = imageRecipe
    let building = currentBuilding
    let image = await imageryClient.postcard(
      latitude: building.latitude, longitude: building.longitude, mapItemIdentifier: building.mapItemIdentifier
    )
    guard !Task.isCancelled, recipe == imageRecipe else { return }
    postcard = image
  }

  private func openHeroBrowser() {
    guard let url = currentBuilding.websiteURL.flatMap(URL.init(string:)) else { return }
    browserDestination = BrowserDestination(url: url, title: "Choose hero image")
    showingBrowser = true
  }

  private func openBuildingSite() {
    guard let url = currentBuilding.websiteURL.flatMap(URL.init(string:)) else { return }
    selectedReviewURL = BrowserDestination(url: url, title: currentBuilding.name)
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
      model.updateHeroImage(currentBuilding, image: jpeg)
    } catch { imageError = error.localizedDescription }
  }

  private func isStale(_ date: Date) -> Bool {
    (Calendar.current.dateComponents([.month], from: date, to: .now).month ?? 0) > 6
  }

  private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
    let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let downscale = min(1, maxEdge / max(pixelSize.width, pixelSize.height))
    let renderSize = CGSize(width: pixelSize.width * downscale, height: pixelSize.height * downscale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: renderSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: renderSize))
    }
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

struct GalleryImage: View {
  let image: UIImage
  let title: String

  var body: some View {
    Image(uiImage: image).resizable().scaledToFill()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .overlay(alignment: .bottomLeading) { GalleryLabel(text: title) }
      .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

struct GalleryLabel: View {
  let text: String

  var body: some View {
    Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
      .background(.regularMaterial, in: Capsule()).padding(10)
  }
}

struct GalleryUnavailable: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "binoculars").font(.largeTitle)
      Text(title).font(.headline)
      Text(detail).font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
  }
}

struct PostcardFallback: View {
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
