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
    .package(path: "../../jon-platform/Vendor/sqlite-data"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.39.1"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(path: "../../jon-platform/packages/LLMHandoffKit"),
    .package(path: "../../jon-platform/packages/LLMClientKit"),
    .package(path: "../../jon-platform/packages/CloudSyncKit"),
  ],
  targets: [
    .target(
      name: "UrbaneSchema",
      dependencies: [
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
        .product(name: "CloudSyncKit", package: "CloudSyncKit"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .target(
      name: "UrbaneCore",
      dependencies: [
        "UrbaneSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "LLMHandoffKit", package: "LLMHandoffKit"),
        .product(name: "LLMClientKit", package: "LLMClientKit"),
      ],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "UrbaneSchemaTests",
      dependencies: [
        "UrbaneSchema",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
      ]
    ),
    .testTarget(
      name: "UrbaneCoreTests",
      dependencies: ["UrbaneCore", "UrbaneSchema", .product(name: "LLMClientKit", package: "LLMClientKit")],
      resources: [.process("Fixtures")]
    ),
  ]
)
