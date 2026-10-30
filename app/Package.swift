// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IELTSMock",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IELTSMock",
            path: "Sources/IELTSMock"
        )
    ]
)
