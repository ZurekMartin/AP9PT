// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "KinetKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "KinetCurrency", targets: ["KinetCurrency"]),
        .library(name: "KinetDesign", targets: ["KinetDesign"]),
        .library(name: "ProfileFeature", targets: ["ProfileFeature"]),
        .library(name: "StudyFeature", targets: ["StudyFeature"]),
        .library(name: "PetFeature", targets: ["PetFeature"]),
        .library(name: "KinetEconomy", targets: ["KinetEconomy"])
    ],
    targets: [
        .target(name: "KinetCurrency", swiftSettings: settings),
        .target(name: "KinetDesign", swiftSettings: settings),
        .target(name: "ProfileFeature", dependencies: ["KinetCurrency", "KinetDesign"], swiftSettings: settings),
        .target(name: "StudyFeature", dependencies: ["KinetCurrency", "KinetDesign"], swiftSettings: settings),
        .target(name: "PetFeature", dependencies: ["KinetCurrency", "KinetDesign"], swiftSettings: settings),
        .target(name: "KinetEconomy", dependencies: ["KinetCurrency", "ProfileFeature", "StudyFeature", "PetFeature"], swiftSettings: settings)
    ],
    swiftLanguageModes: [.v6]
)
