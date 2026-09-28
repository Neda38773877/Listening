// swift-tools-version:5.9
import PackageDescription

// Pure-Foundation logic for the Hören-Trainer app: transcript parsing, audio/word
// alignment, correction suggestions, segmentation, spaced repetition, Redemittel
// detection and search. No UIKit/AVFoundation here so it can be unit-tested anywhere.
let package = Package(
    name: "MeetingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeetingCore", targets: ["MeetingCore"]),
    ],
    targets: [
        .target(name: "MeetingCore"),
        .testTarget(name: "MeetingCoreTests", dependencies: ["MeetingCore"]),
    ]
)
