import Foundation

struct ThreeFingerPanGesture {
	struct Update {
		let previousMidpoint: CGPoint
		let midpoint: CGPoint
	}

	private let origin: CGPoint
	private var previous: CGPoint
	private var isPanning = false

	init(first: CGPoint, second: CGPoint, third: CGPoint) {
		let midpoint = Self.midpoint(first, second, third)
		origin = midpoint
		previous = midpoint
	}

	mutating func update(first: CGPoint, second: CGPoint, third: CGPoint) -> Update? {
		let midpoint = Self.midpoint(first, second, third)
		if !isPanning {
			guard hypot(midpoint.x - origin.x, midpoint.y - origin.y) >= 8 else { return nil }
			isPanning = true
		}
		let update = Update(previousMidpoint: previous, midpoint: midpoint)
		previous = midpoint
		return update
	}

	private static func midpoint(_ first: CGPoint, _ second: CGPoint, _ third: CGPoint) -> CGPoint {
		CGPoint(x: (first.x + second.x + third.x) / 3, y: (first.y + second.y + third.y) / 3)
	}
}
