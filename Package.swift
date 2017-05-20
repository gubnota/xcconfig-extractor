// swift-tools-version:3.1

import Foundation
import PackageDescription

var isDevelopment: Bool {
	return ProcessInfo.processInfo.environment["SWIFTPM_DEVELOPMENT"] == "YES"
}

let package = Package(
    name: "xcconfig-extractor",
    targets: [
        Target(name: "xcconfig-extractor", dependencies: ["Utilities"]),
        Target(name: "Utilities"),
    ],
    dependencies: {
        var deps: [Package.Dependency] = [
            .Package(url: "https://github.com/kylef/Commander.git", majorVersion: 0),
            .Package(url: "https://github.com/kylef/PathKit.git", majorVersion: 0),
            .Package(url: "https://github.com/toshi0383/Pbxproj.git", majorVersion: 0),
        ]
        if isDevelopment {
            deps += [
                .Package(url: "https://github.com/krzysztofzablocki/Sourcery.git", majorVersion: 0, minor: 6),
            ]
        }
        return deps
    }(),
    exclude: ["Resources/SourceryTemplates"]
)

