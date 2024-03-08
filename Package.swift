// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Lua",
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
        .package(name: "Math", path: "Packages/Math"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Lua",
            dependencies: ["Math", "LuaMacros"]),
        .target(
            name: "LuaLib",
            dependencies: ["Lua", "Math"]),
        .executableTarget(
            name: "LuaC",
            dependencies: ["Lua", "LuaLib"]),
        .testTarget(
            name: "LuaTests",
            dependencies: ["Lua", "LuaLib"]),
        .macro(
            name: "LuaMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]),
    ]
)
