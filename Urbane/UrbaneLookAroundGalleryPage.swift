import MapKit
import SwiftUI
import UIKit
import UrbaneSchema

struct LookAroundGalleryPage: View {
  let id: String
  let placeName: String
  let caption: String
  let latitude: Double
  let longitude: Double
  let mapItemIdentifier: String?
  let onAdjust: (() -> Void)?
  @State private var image: UIImage?
  @State private var scene: MKLookAroundScene?
  @State private var showingLookAroundViewer = false
  private let imageryClient = UrbaneImageryClient()

  init(vignette: BuildingVignette, onAdjust: @escaping () -> Void) {
    self.init(
      id: vignette.id.uuidString, placeName: vignette.placeName, caption: vignette.caption,
      latitude: vignette.latitude, longitude: vignette.longitude,
      mapItemIdentifier: vignette.mapItemIdentifier, onAdjust: onAdjust
    )
  }

  init(neighborhoodVignette: NeighborhoodVignette) {
    self.init(
      id: neighborhoodVignette.id.uuidString, placeName: neighborhoodVignette.placeName,
      caption: neighborhoodVignette.caption, latitude: neighborhoodVignette.latitude,
      longitude: neighborhoodVignette.longitude, mapItemIdentifier: neighborhoodVignette.mapItemIdentifier,
      onAdjust: nil
    )
  }

  init(
    id: String, placeName: String, caption: String, latitude: Double, longitude: Double,
    mapItemIdentifier: String?, onAdjust: (() -> Void)?
  ) {
    self.id = id
    self.placeName = placeName
    self.caption = caption
    self.latitude = latitude
    self.longitude = longitude
    self.mapItemIdentifier = mapItemIdentifier
    self.onAdjust = onAdjust
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Button {
        Task { await presentLookAroundViewer() }
      } label: {
        Group {
          if let image {
            Image(uiImage: image).resizable().scaledToFill()
          } else if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: false)
          } else {
            GalleryUnavailable(title: "No Look Around coverage", detail: "The map postcard remains available.")
          }
        }
        .frame(maxWidth: .infinity).aspectRatio(3.0 / 2.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      GalleryLabel(text: caption.isEmpty ? placeName : "\(placeName) · \(caption)")
      if let onAdjust {
        Button("Adjust view", systemImage: "viewfinder", action: onAdjust)
          .labelStyle(.iconOnly).buttonStyle(.borderless)
          .accessibilityLabel("Adjust view for \(placeName)")
          .padding(10)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
    }
    .lookAroundViewer(isPresented: $showingLookAroundViewer, initialScene: scene)
    .task(id: id + "|\(latitude)|\(longitude)|\(mapItemIdentifier ?? "coordinate")") {
      let snapshot = await imageryClient.lookAroundSnapshot(
        latitude: latitude, longitude: longitude, mapItemIdentifier: mapItemIdentifier
      )
      image = snapshot
      scene = snapshot == nil
        ? await imageryClient.lookAroundScene(latitude: latitude, longitude: longitude, mapItemIdentifier: mapItemIdentifier)
        : nil
    }
  }

  private func presentLookAroundViewer() async {
    if scene == nil {
      scene = await imageryClient.lookAroundScene(
        latitude: latitude, longitude: longitude, mapItemIdentifier: mapItemIdentifier
      )
    }
    showingLookAroundViewer = scene != nil
  }
}

struct ReviewCard: View {
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
        if let month = Self.formattedMonth(review.newestReviewMonth) { Text("Newest \(month)") }
        Text("Gathered \(review.gatheredAt.formatted(date: .abbreviated, time: .omitted))")
      }.font(.caption).foregroundStyle(.secondary)
      Text(review.summary).font(.body).foregroundStyle(.primary)
      Label("Open source", systemImage: "arrow.up.right.square").font(.caption)
    }
    .padding(.vertical, 3)
  }

  private static func formattedMonth(_ value: String?) -> String? {
    guard let value else { return nil }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 2 else { return value }
    var components = DateComponents()
    components.year = parts[0]
    components.month = parts[1]
    components.day = 1
    guard let date = Calendar.current.date(from: components) else { return value }
    return date.formatted(.dateTime.month(.abbreviated).year())
  }
}
