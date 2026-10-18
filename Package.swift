// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SopranoCast",
    platforms: [.macOS(.v14)],
    targets: [
        // Search engine: items, matching, keys, settings and layout math. Foundation only, no AppKit.
        .target(
            name: "SopranoCastCore",
            path: "Sources/SopranoCastCore"
        ),
        .executableTarget(
            name: "SopranoCast",
            dependencies: ["SopranoCastCore"],
            path: "Sources/SopranoCast",
            exclude: ["Vendored/SOPRANO_COMMIT"],
            resources: [
                .copy("Resources/DepartureMono-Regular.woff2"),
                .copy("Resources/AppIcon.icns"),
            ],
            linkerSettings: [
                .linkedFramework("CoreText"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "SopranoCastTests",
            dependencies: ["SopranoCast", "SopranoCastCore"],
            path: "Tests/SopranoCastTests",
            swiftSettings: [
                .unsafeFlags(["-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
                .linkedFramework("Testing"),
            ]
        ),
    ]
)
