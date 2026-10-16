// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "OpenParsecGestures",
	targets: [
		.target(name: "OpenParsecGestures", path: "OpenParsec/Gestures"),
		.testTarget(name: "OpenParsecGesturesTests", dependencies: ["OpenParsecGestures"], path: "Tests/Gestures")
	]
)
