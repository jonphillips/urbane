import UrbaneSchema

public enum BuildingBrowse {
  public static func visibleBuildings(_ buildings: [Building], showingRejected: Bool) -> [Building] {
    showingRejected ? buildings : buildings.filter { $0.status != .rejected }
  }
}
