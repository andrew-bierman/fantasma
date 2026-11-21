// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fantasma",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.5.2"),
    ],
    targets: [
        .executableTarget(
            name: "Fantasma",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm"),
            ]
        ),
    ]
)
