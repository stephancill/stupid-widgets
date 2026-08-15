// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "StupidWidgets",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "StupidWidgets",
      targets: ["StupidWidgetsApp"]
    ),
    .library(
      name: "StupidWidgetsWidgetExtension",
      targets: ["StupidWidgetsWidgetExtension"]
    ),
  ],
  targets: [
    .target(
      name: "StupidWidgetsCore",
      path: "Sources/StupidWidgets"
    ),
    .target(
      name: "StupidWidgetsApp",
      dependencies: ["StupidWidgetsCore"]
    ),
    .target(
      name: "StupidWidgetsWidgetExtension",
      dependencies: ["StupidWidgetsCore"]
    ),
    .testTarget(
      name: "StupidWidgetsTests",
      dependencies: ["StupidWidgetsCore"]
    ),
  ]
)
