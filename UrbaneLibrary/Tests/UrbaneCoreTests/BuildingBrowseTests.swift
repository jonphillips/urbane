import Foundation
import Testing
import UrbaneCore
import UrbaneSchema

@Test
func rejectedBuildingsAreHiddenUntilTheMapFilterIsEnabled() {
  let neighborhoodID = UUID()
  let exploring = Building(id: UUID(), neighborhoodID: neighborhoodID, name: "Exploring")
  let rejected = Building(id: UUID(), neighborhoodID: neighborhoodID, name: "Passed", status: .rejected)

  #expect(BuildingBrowse.visibleBuildings([exploring, rejected], showingRejected: false) == [exploring])
  #expect(BuildingBrowse.visibleBuildings([exploring, rejected], showingRejected: true) == [exploring, rejected])
}
