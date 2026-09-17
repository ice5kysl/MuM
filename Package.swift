// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuM",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", "0.4.0"..<"2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MuM",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/MuM",
            swiftSettings: [
                // AppKit 全是主线程 UI 代码。Swift 6 严格并发模式会把 @MainActor
                // 标注撒满整个工程却不带来实际收益，这里退回 v5 语言模式。
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MuMTests",
            dependencies: ["MuM"],
            path: "Tests/MuMTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
