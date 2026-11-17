import SwiftUI
import UrbaneSchema

struct BuildingStatusSection: View {
  let building: Building
  let model: UrbaneMapModel
  let onPass: () -> Void

  private var currentBuilding: Building {
    model.buildings.first { $0.id == building.id } ?? building
  }

  var body: some View {
    Section("Status") {
      Menu {
        Button("Exploring") { set(.exploring) }
        Button("Watching") { set(.watching) }
        Button("Tour candidate") { set(.tourCandidate) }
        Button("Passed", action: onPass)
      } label: {
        LabeledContent("Status", value: statusLabel)
      }
      if currentBuilding.status == .rejected,
         let reason = currentBuilding.rejectionReason, !reason.isEmpty {
        LabeledContent("Reason", value: reason)
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
        BuildingOpinionRow(
          person: person, reaction: reaction, isMe: person.id.uuidString == thisIsMe,
          building: building, model: model
        )
      }
    }
  }

  private func reaction(for personID: UUID) -> Reaction? {
    reactions
      .filter { $0.buildingID == building.id && $0.personID == personID }
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .first
  }

}

private struct BuildingOpinionRow: View {
  let person: Person
  let reaction: Reaction?
  let isMe: Bool
  let building: Building
  let model: UrbaneMapModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(person.displayName).font(.headline)
        if isMe { Text("Me").font(.caption).foregroundStyle(.secondary) }
      }
      if isMe {
        Picker("Rating", selection: ratingBinding) {
          Text("Not rated").tag(nil as Int?)
          ForEach(1...5, id: \.self) { rating in
            if rating == 1 {
              Text("1 star").tag(Optional(rating))
            } else {
              Text("\(rating) stars").tag(Optional(rating))
            }
          }
        }
        .pickerStyle(.menu)
        Toggle("Favorite", isOn: favoriteBinding)
        OpinionNoteEditor(note: reaction?.note ?? "") { note in
          save(rating: reaction?.rating, isFavorite: reaction?.isFavorite ?? false, note: note)
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

  private var ratingBinding: Binding<Int?> {
    Binding(
      get: { reaction?.rating },
      set: { save(rating: $0, isFavorite: reaction?.isFavorite ?? false, note: reaction?.note ?? "") }
    )
  }

  private var favoriteBinding: Binding<Bool> {
    Binding(
      get: { reaction?.isFavorite ?? false },
      set: { save(rating: reaction?.rating, isFavorite: $0, note: reaction?.note ?? "") }
    )
  }

  private func save(rating: Int?, isFavorite: Bool, note: String) {
    model.upsertReaction(
      buildingID: building.id, personID: person.id, rating: rating,
      isFavorite: isFavorite, note: note
    )
  }
}

private struct OpinionNoteEditor: View {
  let note: String
  let onChange: (String) -> Void
  @State private var draft = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Note")
      TextField("Add a note", text: $draft, axis: .vertical)
        .lineLimit(2...5)
        .onChange(of: draft) { _, value in onChange(value) }
    }
    .onAppear { draft = note }
  }
}
