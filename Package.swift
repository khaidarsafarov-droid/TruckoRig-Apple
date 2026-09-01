// swift-tools-version: 5.9
import PackageDescription

// The iOS app is built from TruckoRig.xcodeproj. This package exists so the pure-Foundation
// domain layer (parsers, week math, goal calculators) can be built and tested with `swift test`
// on any machine or CI runner, including Linux, without Xcode.
let package = Package(
    name: "TruckoRigDomain",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "TruckoRigDomain", targets: ["TruckoRigDomain"]),
    ],
    targets: [
        .target(
            name: "TruckoRigDomain",
            path: "TruckoRig/Domain"
        ),
        .testTarget(
            name: "TruckoRigDomainTests",
            dependencies: ["TruckoRigDomain"],
            path: "Tests/TruckoRigDomainTests"
        ),
    ]
)
