import UrbaneCore

@MainActor enum ChatImportSearchJobs {
  static func make(paste: ChatImportPaste, validBuildingNeighborhoods: Set<String>) -> [(String, String)] {
    var jobs: [(String, String)] = []
    for (index, neighborhood) in paste.neighborhoods.enumerated() {
      jobs.append(("n\(index)", "\(neighborhood.name), New York, NY"))
    }
    for (index, building) in paste.buildings.enumerated()
    where validBuildingNeighborhoods.contains(UrbaneMapModel.normalize(building.neighborhood)) {
      jobs.append(("b\(index)", "\(building.name), \(building.address), New York, NY"))
    }
    for (index, neighborhood) in paste.neighborhoods.enumerated() {
      for (vIndex, vignette) in neighborhood.vignettes.enumerated() {
        jobs.append(("n\(index)v\(vIndex)", "\(vignette.place), \(neighborhood.name), New York, NY"))
      }
    }
    return jobs
  }
}
