// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "craftos3-lua",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
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
        .executable(
            name: "LuaC",
            targets: ["LuaC"])
    ],
    dependencies: [
        .package(name: "LibC", path: "Packages/LibC"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "601.0.0"),
        .package(url: "https://github.com/pbk20191/BTree.git", branch: "master"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Lua",
            dependencies: ["LibC", "LuaMacros", .product(name: "BTreeModule", package: "BTree")]),
        .target(
            name: "LuaLib",
            dependencies: ["Lua", "LibC"]),
        .executableTarget(
            name: "LuaC",
            dependencies: ["Lua", "LuaLib"]),
        .testTarget(
            name: "LuaTests",
            dependencies: ["Lua", "LuaLib"]),
        .macro(
            name: "LuaMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]),
    ]
)
