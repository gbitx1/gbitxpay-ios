// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GbitXPay",
    // iOS is the supported target; macOS is declared so the pure core builds and
    // its tests run on the host (the WKWebView/UIKit UI is #if canImport(UIKit)
    // guarded and compiles to nothing on non-UIKit platforms).
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "GbitXPay", targets: ["GbitXPay"])
    ],
    targets: [
        .target(
            name: "GbitXPay",
            path: "Sources/GbitXPay"
        ),
        .testTarget(
            name: "GbitXPayTests",
            dependencies: ["GbitXPay"],
            path: "Tests/GbitXPayTests"
        )
    ]
)
