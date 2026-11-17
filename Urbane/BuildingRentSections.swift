import SwiftUI
import UIKit
import UrbaneCore
import UrbaneSchema

struct BuildingRentSection: View {
  let building: Building
  let model: UrbaneMapModel
  let onCapture: () -> Void
  let captureError: String?
  let pageTextToCopy: String?

  var body: some View {
    Section("Rent band") {
      rentBand
      Button("Capture from StreetEasy", systemImage: "magnifyingglass", action: onCapture)
        .disabled(!hasStreetEasyLink)
      if let pageTextToCopy {
        Button("Copy page text", systemImage: "doc.on.doc") {
          UIPasteboard.general.string = pageTextToCopy
        }
      }
      if !hasStreetEasyLink {
        Text("Add a StreetEasy link in Edit links to capture rents.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let captureError { Text(captureError).font(.footnote).foregroundStyle(.red) }
    }
  }

  private var hasStreetEasyLink: Bool {
    guard let value = building.streetEasyURL,
          let validated = try? BuildingLinkValidator.validate(value, for: .streetEasy) else { return false }
    return URL(string: validated) != nil
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
          Button {
            model.openTransitDirections(for: building, to: commute.destination)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(commute.destination.displayName)
                  .foregroundStyle(.primary)
                Text("\(Duration.seconds(commute.transitSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) · Apple Maps · \(commute.computedAt.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
          .accessibilityHint("Opens transit directions in Maps")
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
