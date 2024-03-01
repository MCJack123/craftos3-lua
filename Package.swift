// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lua",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v7),
        .driverKit(.v19)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Lua",
            targets: ["Lua"]),
        .library(
            name: "LuaLib",
            targets: ["LuaLib"]),
    ],
    dependencies: [
        .package(name: "Math", path: "Packages/Math")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Lua",
            dependencies: ["Math"]),
        .target(
            name: "LuaLib",
            dependencies: ["Lua", "Math"]),
        .testTarget(
            name: "LuaTests",
            dependencies: ["Lua", "LuaLib"]),
    ]
)
