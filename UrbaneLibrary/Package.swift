// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "UrbaneLibrary",
  platforms: [.iOS("27.0"), .macOS("26.0")],
  products: [
    .library(name: "UrbaneSchema", targets: ["UrbaneSchema"]),
    .library(name: "UrbaneImaging", targets: ["UrbaneImaging"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.31.0"),
  ],
  targets: [
    .target(
      name: "UrbaneSchema",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "UrbaneImaging",
      dependencies: [.product(name: "Dependencies", package: "swift-dependencies")]
    ),
    .testTarget(
      name: "UrbaneSchemaTests",
      dependencies: [
        "UrbaneSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
  ]
)
