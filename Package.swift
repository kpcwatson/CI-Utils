// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "CI-Utils",
    dependencies: [
        .Package(url: "https://github.com/ravrx8/SwiftLogger.git", majorVersion: 0),
        .Package(url: "https://github.com/ravrx8/JiraKit.git", majorVersion: 0),
        .Package(url: "https://github.com/ravrx8/SwiftSendmail.git", majorVersion: 0),
        .Package(url: "https://github.com/ravrx8/SwiftHTML.git", majorVersion: 0),
        .Package(url: "https://github.com/kareman/Moderator.git", majorVersion: 0),
        .Package(url: "https://github.com/kareman/SwiftShell.git", majorVersion: 3),
    ]
)
