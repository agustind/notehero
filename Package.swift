// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NoteHero",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NoteHero",
            path: "Sources/NoteHero",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
