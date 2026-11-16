// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "UrbaneLibrary",
  platforms: [.iOS("27.0"), .macOS("26.0")],
  products: [
    .library(name: "UrbaneSchema", targets: ["UrbaneSchema"]),
    .library(name: "UrbaneCore", targets: ["UrbaneCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(path: "../../jon-platform/packages/LLMHandoffKit"),
  ],
  targets: [
    .target(
      name: "UrbaneSchema",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .target(
      name: "UrbaneCore",
      dependencies: [
        "UrbaneSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
      ]
    ),
    .testTarget(
      name: "UrbaneSchemaTests",
      dependencies: [
        "UrbaneSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "UrbaneCoreTests",
      dependencies: ["UrbaneCore", "UrbaneSchema"]
    ),
  ]
)
