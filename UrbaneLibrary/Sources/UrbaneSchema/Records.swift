import Foundation
import SQLiteData

public enum BuildingStatus: Int, QueryBindable, CaseIterable, Sendable {
  case exploring = 0
  case watching = 1
  case tourCandidate = 2
  case rejected = 3
}

public enum TuesdayPart: Int, QueryBindable, CaseIterable, Sendable {
  case morning = 0
  case commute = 1
  case dinner = 2
  case eveningWalk = 3
}

public enum BuildingReviewSubject: Int, QueryBindable, CaseIterable, Sendable {
  case building = 0
  case landlord = 1
}

public struct GeoCoordinate: Equatable, Sendable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

public enum CommuteDestination: Int, QueryBindable, CaseIterable, Sendable {
  case soho = 0
  case tribeca = 1
  case westVillage = 2
  case lowerEastSide = 3
  case midtown = 4

  public var displayName: String {
    switch self {
    case .soho: "Soho"
    case .tribeca: "Tribeca"
    case .westVillage: "West Village"
    case .lowerEastSide: "Lower East Side"
    case .midtown: "Midtown"
    }
  }

  /// Representative routing anchors at the centers of the named work destinations.
  public var coordinate: GeoCoordinate {
    switch self {
    case .soho: GeoCoordinate(latitude: 40.7233, longitude: -73.9982)
    case .tribeca: GeoCoordinate(latitude: 40.7163, longitude: -74.0086)
    case .westVillage: GeoCoordinate(latitude: 40.7358, longitude: -74.0036)
    case .lowerEastSide: GeoCoordinate(latitude: 40.7157, longitude: -73.9863)
    case .midtown: GeoCoordinate(latitude: 40.7549, longitude: -73.9840)
    }
  }
}

@Table
public struct Search: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title = ""
  public var moveInTargetDate: Date?

  public init(id: UUID, title: String = "", moveInTargetDate: Date? = nil) {
    self.id = id
    self.title = title
    self.moveInTargetDate = moveInTargetDate
  }
}

@Table("people")
public struct Person: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var searchID: Search.ID
  public var displayName = ""
  public var iCloudUserRecordName: String?

  public init(
    id: UUID, searchID: Search.ID, displayName: String = "", iCloudUserRecordName: String? = nil
  ) {
    self.id = id
    self.searchID = searchID
    self.displayName = displayName
    self.iCloudUserRecordName = iCloudUserRecordName
  }
}

@Table
public struct Neighborhood: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var searchID: Search.ID
  public var name = ""
  public var chapter = ""
  public var centerLatitude = 0.0
  public var centerLongitude = 0.0
  public var latitudeSpan = 0.0
  public var longitudeSpan = 0.0
  public var sortOrder = 0

  public init(
    id: UUID, searchID: Search.ID, name: String = "", chapter: String = "",
    centerLatitude: Double = 0, centerLongitude: Double = 0, latitudeSpan: Double = 0,
    longitudeSpan: Double = 0, sortOrder: Int = 0
  ) {
    self.id = id
    self.searchID = searchID
    self.name = name
    self.chapter = chapter
    self.centerLatitude = centerLatitude
    self.centerLongitude = centerLongitude
    self.latitudeSpan = latitudeSpan
    self.longitudeSpan = longitudeSpan
    self.sortOrder = sortOrder
  }
}

@Table
public struct NeighborhoodRent: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var neighborhoodID: Neighborhood.ID
  public var month = ""
  public var median2BRRent = 0.0
  public var sourceLabel = ""

  public init(
    id: UUID, neighborhoodID: Neighborhood.ID, month: String = "", median2BRRent: Double = 0,
    sourceLabel: String = ""
  ) {
    self.id = id
    self.neighborhoodID = neighborhoodID
    self.month = month
    self.median2BRRent = median2BRRent
    self.sourceLabel = sourceLabel
  }
}

@Table
public struct Building: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var neighborhoodID: Neighborhood.ID
  public var name = ""
  public var address = ""
  public var latitude = 0.0
  public var longitude = 0.0
  public var mapItemIdentifier: String?
  public var summary = ""
  public var status: BuildingStatus = .exploring
  public var rejectionReason: String?
  public var streetEasyURL: String?
  public var websiteURL: String?
  public var heroImage: Data?

  public init(
    id: UUID, neighborhoodID: Neighborhood.ID, name: String = "", address: String = "",
    latitude: Double = 0, longitude: Double = 0, mapItemIdentifier: String? = nil, summary: String = "",
    status: BuildingStatus = .exploring, rejectionReason: String? = nil,
    streetEasyURL: String? = nil, websiteURL: String? = nil, heroImage: Data? = nil
  ) {
    self.id = id
    self.neighborhoodID = neighborhoodID
    self.name = name
    self.address = address
    self.latitude = latitude
    self.longitude = longitude
    self.mapItemIdentifier = mapItemIdentifier
    self.summary = summary
    self.status = status
    self.rejectionReason = rejectionReason
    self.streetEasyURL = streetEasyURL
    self.websiteURL = websiteURL
    self.heroImage = heroImage
  }
}

@Table
public struct NeighborhoodVignette: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var neighborhoodID: Neighborhood.ID
  public var placeName = ""
  public var latitude = 0.0
  public var longitude = 0.0
  public var mapItemIdentifier: String?
  public var caption = ""
  public var sortOrder = 0

  public init(
    id: UUID, neighborhoodID: Neighborhood.ID, placeName: String = "", latitude: Double = 0,
    longitude: Double = 0, mapItemIdentifier: String? = nil, caption: String = "", sortOrder: Int = 0
  ) {
    self.id = id
    self.neighborhoodID = neighborhoodID
    self.placeName = placeName
    self.latitude = latitude
    self.longitude = longitude
    self.mapItemIdentifier = mapItemIdentifier
    self.caption = caption
    self.sortOrder = sortOrder
  }
}

@Table
public struct BuildingVignette: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var placeName = ""
  public var latitude = 0.0
  public var longitude = 0.0
  public var mapItemIdentifier: String?
  public var caption = ""
  public var sortOrder = 0
  public var tuesdayPart: TuesdayPart?

  public init(
    id: UUID, buildingID: Building.ID, placeName: String = "", latitude: Double = 0,
    longitude: Double = 0, mapItemIdentifier: String? = nil, caption: String = "",
    sortOrder: Int = 0, tuesdayPart: TuesdayPart? = nil
  ) {
    self.id = id
    self.buildingID = buildingID
    self.placeName = placeName
    self.latitude = latitude
    self.longitude = longitude
    self.mapItemIdentifier = mapItemIdentifier
    self.caption = caption
    self.sortOrder = sortOrder
    self.tuesdayPart = tuesdayPart
  }
}

@Table
public struct Commute: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var destination: CommuteDestination
  public var transitSeconds = 0
  public var computedAt: Date

  public init(
    id: UUID, buildingID: Building.ID, destination: CommuteDestination,
    transitSeconds: Int = 0, computedAt: Date
  ) {
    self.id = id
    self.buildingID = buildingID
    self.destination = destination
    self.transitSeconds = transitSeconds
    self.computedAt = computedAt
  }
}

@Table
public struct RentObservation: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var rent = 0
  public var unit: String?
  public var squareFeet: Double?
  public var dateSeen: Date
  public var sourceURL = ""

  public init(
    id: UUID, buildingID: Building.ID, rent: Int = 0, unit: String? = nil,
    squareFeet: Double? = nil, dateSeen: Date, sourceURL: String = ""
  ) {
    self.id = id
    self.buildingID = buildingID
    self.rent = rent
    self.unit = unit
    self.squareFeet = squareFeet
    self.dateSeen = dateSeen
    self.sourceURL = sourceURL
  }
}

@Table
public struct Reaction: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var personID: Person.ID
  public var rating: Int?
  public var isFavorite = false
  public var note = ""

  public init(
    id: UUID, buildingID: Building.ID, personID: Person.ID, rating: Int? = nil,
    isFavorite: Bool = false, note: String = ""
  ) {
    self.id = id
    self.buildingID = buildingID
    self.personID = personID
    self.rating = rating
    self.isFavorite = isFavorite
    self.note = note
  }
}

@Table
public struct Photo: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var personID: Person.ID
  public var image: Data
  public var caption = ""
  public var dateTaken: Date

  public init(
    id: UUID, buildingID: Building.ID, personID: Person.ID, image: Data,
    caption: String = "", dateTaken: Date
  ) {
    self.id = id
    self.buildingID = buildingID
    self.personID = personID
    self.image = image
    self.caption = caption
    self.dateTaken = dateTaken
  }
}

@Table
public struct BuildingReview: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var buildingID: Building.ID
  public var source = ""
  public var subject: BuildingReviewSubject
  public var sourceURL = ""
  public var rating: Double?
  public var ratingScale: Double?
  public var reviewCount: Int?
  public var newestReviewMonth: String?
  public var summary = ""
  public var gatheredAt: Date

  public init(
    id: UUID, buildingID: Building.ID, source: String = "",
    subject: BuildingReviewSubject, sourceURL: String = "", rating: Double? = nil,
    ratingScale: Double? = nil, reviewCount: Int? = nil, newestReviewMonth: String? = nil,
    summary: String = "", gatheredAt: Date
  ) {
    self.id = id
    self.buildingID = buildingID
    self.source = source
    self.subject = subject
    self.sourceURL = sourceURL
    self.rating = rating
    self.ratingScale = ratingScale
    self.reviewCount = reviewCount
    self.newestReviewMonth = newestReviewMonth
    self.summary = summary
    self.gatheredAt = gatheredAt
  }
}
