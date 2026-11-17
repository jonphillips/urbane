import SwiftUI
import UrbaneSchema

struct BuildingStatusSection: View {
  let building: Building
  let model: UrbaneMapModel
  @State private var showingRejectionReason = false
  @State private var rejectionReasonDraft = ""

  private var currentBuilding: Building {
    model.buildings.first { $0.id == building.id } ?? building
  }

  var body: some View {
    Section("Status") {
      Menu {
        Button("Exploring") { set(.exploring) }
        Button("Watching") { set(.watching) }
        Button("Tour candidate") { set(.tourCandidate) }
        Button("Passed") {
          rejectionReasonDraft = currentBuilding.rejectionReason ?? ""
          showingRejectionReason = true
        }
      } label: {
        LabeledContent("Status", value: statusLabel)
      }
      if currentBuilding.status == .rejected,
         let reason = currentBuilding.rejectionReason, !reason.isEmpty {
        LabeledContent("Reason", value: reason)
      }
    }
    .sheet(isPresented: $showingRejectionReason) {
      NavigationStack {
        Form {
          VStack(alignment: .leading, spacing: 6) {
            Text("Reason")
            TextField("Why pass on this building?", text: $rejectionReasonDraft, axis: .vertical)
              .lineLimit(3...6)
          }
        }
        .navigationTitle("Pass on building")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { showingRejectionReason = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              model.updateBuildingStatus(currentBuilding, status: .rejected, rejectionReason: rejectionReasonDraft)
              showingRejectionReason = false
            }
            .disabled(rejectionReasonDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
    }
  }

  private var statusLabel: String {
    switch currentBuilding.status {
    case .exploring: "Exploring"
    case .watching: "Watching"
    case .tourCandidate: "Tour candidate"
    case .rejected: "Passed"
    }
  }

  private func set(_ status: BuildingStatus) {
    model.updateBuildingStatus(currentBuilding, status: status, rejectionReason: "")
  }
}

struct BuildingOpinionsSection: View {
  let building: Building
  let people: [Person]
  let reactions: [Reaction]
  let model: UrbaneMapModel
  @AppStorage("urbane.thisIsMe") private var thisIsMe = ""

  var body: some View {
    Section("Opinions") {
      if thisIsMe.isEmpty || !people.contains(where: { $0.id.uuidString == thisIsMe }) {
        Text("Choose who you are in Settings before rating a building.")
          .foregroundStyle(.secondary)
      }
      ForEach(people) { person in
        let reaction = reaction(for: person.id)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(person.displayName).font(.headline)
            if person.id.uuidString == thisIsMe {
              Text("Me").font(.caption).foregroundStyle(.secondary)
            }
          }
          if person.id.uuidString == thisIsMe {
            Picker("Rating", selection: ratingBinding(for: person.id)) {
              Text("Not rated").tag(nil as Int?)
              ForEach(1...5, id: \.self) { rating in
                Text("\(rating) stars").tag(Optional(rating))
              }
            }
            .pickerStyle(.menu)
            Toggle("Favorite", isOn: favoriteBinding(for: person.id))
            VStack(alignment: .leading, spacing: 6) {
              Text("Note")
              TextField("Add a note", text: noteBinding(for: person.id), axis: .vertical)
                .lineLimit(2...5)
            }
          } else if reaction == nil {
            Text("No opinion recorded.").font(.subheadline).foregroundStyle(.secondary)
          } else {
            HStack(spacing: 8) {
              if let rating = reaction?.rating {
                Label("\(rating) of 5", systemImage: "star.fill")
              }
              if reaction?.isFavorite == true {
                Label("Favorite", systemImage: "heart.fill")
              }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let note = reaction?.note, !note.isEmpty {
              Text(note).font(.subheadline)
            }
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func reaction(for personID: UUID) -> Reaction? {
    reactions
      .filter { $0.buildingID == building.id && $0.personID == personID }
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .first
  }

  private func ratingBinding(for personID: UUID) -> Binding<Int?> {
    Binding(
      get: { reaction(for: personID)?.rating },
      set: { rating in
        let existing = reaction(for: personID)
        model.upsertReaction(
          buildingID: building.id, personID: personID, rating: rating,
          isFavorite: existing?.isFavorite ?? false, note: existing?.note ?? ""
        )
      }
    )
  }

  private func favoriteBinding(for personID: UUID) -> Binding<Bool> {
    Binding(
      get: { reaction(for: personID)?.isFavorite ?? false },
      set: { isFavorite in
        let existing = reaction(for: personID)
        model.upsertReaction(
          buildingID: building.id, personID: personID, rating: existing?.rating,
          isFavorite: isFavorite, note: existing?.note ?? ""
        )
      }
    )
  }

  private func noteBinding(for personID: UUID) -> Binding<String> {
    Binding(
      get: { reaction(for: personID)?.note ?? "" },
      set: { note in
        let existing = reaction(for: personID)
        model.upsertReaction(
          buildingID: building.id, personID: personID, rating: existing?.rating,
          isFavorite: existing?.isFavorite ?? false, note: note
        )
      }
    )
  }
}
