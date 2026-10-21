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
            // The app icon ships from the repo path (scripts/package-app.sh), not a bundle.
            exclude: ["Vendored/SOPRANO_COMMIT", "Resources/AppIcon.icns"],
            linkerSettings: [
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
