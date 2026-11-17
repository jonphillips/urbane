import SwiftUI
import UrbaneCore
import UrbaneSchema

struct RentReviewContext: Identifiable {
  var id: String { "\(building.id)-\(sourceURL.absoluteString)" }
  let building: Building
  let candidates: [RentListingCandidate]
  let sourceURL: URL
}

struct RentReviewSheet: View {
  let context: RentReviewContext
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var selected = Set<Int>()

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Check each rent against the page. Nothing is saved until you confirm.")
            .foregroundStyle(.secondary)
          Text(context.sourceURL.absoluteString)
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Section("2 bedroom listings found") {
          ForEach(Array(context.candidates.enumerated()), id: \.offset) { index, candidate in
            Button {
              if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(candidate.rent, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.headline)
                  Text([candidate.unit, candidate.squareFeet.map { "\(Int($0)) sq ft" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selected.contains(index) ? Color.accentColor : Color.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("Review rents")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save \(selected.count)") {
            let approved = context.candidates.enumerated().compactMap { index, value in
              selected.contains(index) ? value : nil
            }
            model.saveRentObservations(approved, building: context.building, sourceURL: context.sourceURL)
            dismiss()
          }
          .disabled(selected.isEmpty)
        }
      }
      .onAppear { selected = Set(context.candidates.indices) }
    }
  }
}
