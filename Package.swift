// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoPic",
    defaultLocalization: "es",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PhotoPicKit",
            targets: ["PhotoPicKit"]
        ),
        .executable(
            name: "PhotoPic",
            targets: ["AppEntry"]
        ),
        .executable(
            name: "PhotoPicVerify",
            targets: ["PhotoPicVerify"]
        )
    ],
    targets: [
        .target(
            name: "PhotoPicKit",
            path: "macos/PhotoPic",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Metal"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "AppEntry",
            dependencies: ["PhotoPicKit"],
            path: "macos/AppEntry"
        ),
        .executableTarget(
            name: "PhotoPicVerify",
            dependencies: ["PhotoPicKit"],
            path: "macos/Verification"
        )
    ]
)
