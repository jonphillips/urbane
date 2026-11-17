import SwiftUI
import UrbaneCore
import UrbaneSchema
import WebExtractorKit

struct BuildingRentSection: View {
  let building: Building
  let model: UrbaneMapModel
  @State private var showingBrowser = false
  @State private var pendingReview: RentReviewContext?
  @State private var review: RentReviewContext?
  @State private var error: String?

  private var streetEasyPageURL: URL? {
    guard let value = building.streetEasyURL,
          let validated = try? BuildingLinkValidator.validate(value, for: .streetEasy) else { return nil }
    return URL(string: validated)
  }

  var body: some View {
    Section("Rent band") {
      rentBand
      Button("Capture from StreetEasy", systemImage: "magnifyingglass") { showingBrowser = true }
        .disabled(streetEasyPageURL == nil)
      if streetEasyPageURL == nil {
        Text("Add a StreetEasy link in Edit links to capture rents.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let error { Text(error).font(.footnote).foregroundStyle(.red) }
    }
    .onChange(of: showingBrowser) { _, isShowing in
      if !isShowing {
        review = pendingReview
        pendingReview = nil
      }
    }
    .sheet(isPresented: $showingBrowser) {
      if let url = streetEasyPageURL {
        WebExtractorBrowser(startURL: url, title: "Capture rents", confirmLabel: "Extract rents") { html, pageURL in
          let sourceURL = pageURL ?? url
          do {
            let candidates = try await model.extractRentCandidates(from: html, sourceURL: sourceURL)
            guard !candidates.isEmpty else {
              return .notFound(message: "No 2 bedroom rental candidates were found. Try the listing page and confirm it has loaded.")
            }
            pendingReview = RentReviewContext(building: building, candidates: candidates, sourceURL: sourceURL)
            error = nil
            return .extracted
          } catch {
            self.error = error.localizedDescription
            return .notFound(message: "Rent extraction failed: \(error.localizedDescription)")
          }
        }
      }
    }
    .sheet(item: $review) { context in RentReviewSheet(context: context, model: model) }
  }

  @ViewBuilder
  private var rentBand: some View {
    let observations = model.rentObservations.filter { $0.buildingID == building.id }
      .sorted { $0.dateSeen > $1.dateSeen }
    let band = RentBand(observations: observations, now: model.currentDate)
    if observations.isEmpty {
      Text("No rental observations yet.").foregroundStyle(.secondary)
    } else {
      if band.count > 0 {
        Text(band.count < 2
          ? band.low.formatted(.currency(code: "USD").precision(.fractionLength(0)))
          : "\(band.low.formatted(.currency(code: "USD").precision(.fractionLength(0))))–\(band.high.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
          .font(.title3.weight(.semibold))
        let recent = observations.filter { !model.isRentObservationStale($0) }
        if band.count < 2, let date = recent.first?.dateSeen {
          Text("\(date.formatted(date: .abbreviated, time: .omitted)) · StreetEasy")
            .font(.caption).foregroundStyle(.secondary)
        } else if let oldest = recent.last?.dateSeen, let newest = recent.first?.dateSeen {
          Text("\(oldest.formatted(date: .abbreviated, time: .omitted))–\(newest.formatted(date: .abbreviated, time: .omitted)) · StreetEasy")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Text("No observations within the last six months.").foregroundStyle(.secondary)
      }
      ForEach(observations.prefix(6)) { observation in
        VStack(alignment: .leading, spacing: 3) {
          Text(observation.rent, format: .currency(code: "USD").precision(.fractionLength(0)))
          Text("\(observation.unit ?? "Unit not recorded") · \(observation.dateSeen.formatted(date: .abbreviated, time: .omitted)) · \(URL(string: observation.sourceURL)?.host ?? "Source")")
            .font(.caption).foregroundStyle(.secondary)
        }
        .opacity(model.isRentObservationStale(observation) ? 0.58 : 1)
      }
    }
  }
}

struct BuildingCommuteSection: View {
  let building: Building
  let model: UrbaneMapModel

  var body: some View {
    Section("Commutes by transit") {
      let commutes = model.commutes.filter { $0.buildingID == building.id }
        .sorted { $0.destination.rawValue < $1.destination.rawValue }
      if commutes.isEmpty {
        Text("Transit times have not been calculated yet.").foregroundStyle(.secondary)
      } else {
        ForEach(commutes) { commute in
          VStack(alignment: .leading, spacing: 3) {
            Text(commute.destination.displayName)
            Text("\(Duration.seconds(commute.transitSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) · Apple Maps · \(commute.computedAt.formatted(date: .abbreviated, time: .omitted))")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Button("Refresh transit times", systemImage: "arrow.clockwise") {
        Task { await model.refreshCommutes(for: building) }
      }
      if let commuteError = model.commuteErrors[building.id] {
        Text(commuteError).font(.footnote).foregroundStyle(.red)
      }
    }
  }
}
