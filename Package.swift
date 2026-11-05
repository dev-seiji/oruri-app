// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Oruri",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Oruri",
            path: "Sources/Oruri"
        ),
        // QA: testes automáticos (rodar com ./qa.sh depois de cada mudança).
        .testTarget(
            name: "OruriTests",
            dependencies: ["Oruri"],
            path: "Tests/OruriTests"
        ),
    ]
)
