// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FormationFlow",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FormationFlow",
            targets: ["FormationFlow"])
    ],
    targets: [
        .target(
            name: "FormationFlow",
            path: "Sources/FormationFlow"
        )
    ]
)
