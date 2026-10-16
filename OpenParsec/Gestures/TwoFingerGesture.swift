import Foundation

struct TwoFingerGesture {
	enum Mode { case undecided, zoom, scroll }

	struct Update {
		let mode: Mode
		let scaleFactor: CGFloat
		let previousMidpoint: CGPoint
		let midpoint: CGPoint
	}

	private struct Sample {
		let first: CGPoint
		let second: CGPoint
		var distance: CGFloat { hypot(second.x - first.x, second.y - first.y) }
		var midpoint: CGPoint { CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2) }
	}

	private let origin: Sample
	private var previous: Sample
	private(set) var mode: Mode = .undecided

	init(first: CGPoint, second: CGPoint) {
		let sample = Sample(first: first, second: second)
		origin = sample
		previous = sample
	}

	mutating func update(first: CGPoint, second: CGPoint) -> Update {
		let sample = Sample(first: first, second: second)
		if mode == .undecided {
			let separation = abs(sample.distance - origin.distance)
			let translation = hypot(sample.midpoint.x - origin.midpoint.x, sample.midpoint.y - origin.midpoint.y)
			let firstDelta = CGPoint(x: first.x - origin.first.x, y: first.y - origin.first.y)
			let secondDelta = CGPoint(x: second.x - origin.second.x, y: second.y - origin.second.y)
			let movingTogether = firstDelta.x * secondDelta.x + firstDelta.y * secondDelta.y > 0
			let pinchThreshold = max(10, min(18, origin.distance * 0.06))

			if separation >= pinchThreshold && separation > translation * 0.75 {
				mode = .zoom
			} else if translation >= 12 && separation < translation * 0.6 && movingTogether {
				mode = .scroll
			}
		}

		let update = Update(mode: mode,
							scaleFactor: previous.distance > 0 ? sample.distance / previous.distance : 1,
							previousMidpoint: previous.midpoint, midpoint: sample.midpoint)
		// Retain the initial movement until a gesture wins, then lock that choice until lift.
		if mode != .undecided { previous = sample }
		return update
	}
}

struct ZoomViewport {
	let scale: CGFloat
	let offset: CGPoint

	func pinching(by factor: CGFloat, from previousAnchor: CGPoint, to anchor: CGPoint,
				  contentSize: CGSize, viewportSize: CGSize, bottomInset: CGFloat,
				  scaleRange: ClosedRange<CGFloat>) -> ZoomViewport {
		guard factor.isFinite, factor > 0, scale > 0 else { return self }
		let nextScale = min(max(scale * factor, scaleRange.lowerBound), scaleRange.upperBound)
		let contentAnchor = CGPoint(x: (offset.x + previousAnchor.x) / scale,
									y: (offset.y + previousAnchor.y) / scale)
		let maxX = max(0, contentSize.width * nextScale - viewportSize.width)
		let maxY = max(0, contentSize.height * nextScale - viewportSize.height + bottomInset)
		let nextOffset = CGPoint(x: min(max(0, contentAnchor.x * nextScale - anchor.x), maxX),
								 y: min(max(0, contentAnchor.y * nextScale - anchor.y), maxY))
		return ZoomViewport(scale: nextScale, offset: nextOffset)
	}
}
