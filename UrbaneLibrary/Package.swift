// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "UrbaneLibrary",
  platforms: [.iOS("27.0"), .macOS("26.0")],
  products: [
    .library(name: "UrbaneSchema", targets: ["UrbaneSchema"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "UrbaneSchema",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "UrbaneSchemaTests",
      dependencies: [
        "UrbaneSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
  ]
)
