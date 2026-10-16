import XCTest
@testable import OpenParsecGestures

final class ThreeFingerPanGestureTests: XCTestCase {
	private let first = CGPoint(x: 100, y: 200)
	private let second = CGPoint(x: 200, y: 200)
	private let third = CGPoint(x: 150, y: 300)

	private func gesture() -> ThreeFingerPanGesture {
		ThreeFingerPanGesture(first: first, second: second, third: third)
	}

	private func translated(_ point: CGPoint, by delta: CGPoint) -> CGPoint {
		CGPoint(x: point.x + delta.x, y: point.y + delta.y)
	}

	private func move(_ gesture: inout ThreeFingerPanGesture, by delta: CGPoint) -> ThreeFingerPanGesture.Update? {
		gesture.update(first: translated(first, by: delta), second: translated(second, by: delta),
			third: translated(third, by: delta))
	}

	func testTapJitterDoesNotPan() {
		var gesture = gesture()
		for delta in [CGPoint(x: 2, y: 1), CGPoint(x: -3, y: 2), .zero] {
			XCTAssertNil(move(&gesture, by: delta))
		}
	}

	func testDragStartsWithoutPinchingInAnyDirection() throws {
		for delta in [CGPoint(x: 20, y: 0), CGPoint(x: 0, y: -20), CGPoint(x: -20, y: 30)] {
			var gesture = gesture()
			let update = try XCTUnwrap(move(&gesture, by: delta))
			XCTAssertEqual(update.midpoint.x - update.previousMidpoint.x, delta.x, accuracy: 0.0001)
			XCTAssertEqual(update.midpoint.y - update.previousMidpoint.y, delta.y, accuracy: 0.0001)
		}
	}

	func testRecognitionPreservesInitialMovementAndTracksSmallReversals() throws {
		var gesture = gesture()
		XCTAssertNil(move(&gesture, by: CGPoint(x: 4, y: 0)))
		let start = try XCTUnwrap(move(&gesture, by: CGPoint(x: 10, y: 0)))
		XCTAssertEqual(start.midpoint.x - start.previousMidpoint.x, 10)
		let reversal = try XCTUnwrap(move(&gesture, by: CGPoint(x: 8, y: 0)))
		XCTAssertEqual(reversal.previousMidpoint, start.midpoint)
		XCTAssertEqual(reversal.midpoint.x - reversal.previousMidpoint.x, -2)
	}

	func testSpreadingFingersWithoutMovingTheirCenterDoesNotPan() {
		var gesture = gesture()
		XCTAssertNil(gesture.update(first: CGPoint(x: 60, y: 200), second: CGPoint(x: 240, y: 200), third: third))
	}

	func testDragMovesViewportWithoutChangingZoom() throws {
		var gesture = gesture()
		let update = try XCTUnwrap(move(&gesture, by: CGPoint(x: 20, y: 30)))
		for scale in [CGFloat(1), 2, 5] {
			let before = ZoomViewport(scale: scale, offset: scale == 1 ? .zero : CGPoint(x: 200, y: 400))
			let after = before.pinching(by: 1, from: update.previousMidpoint, to: update.midpoint,
				contentSize: CGSize(width: 400, height: 800), viewportSize: CGSize(width: 400, height: 800),
				bottomInset: 0, scaleRange: 1...5)
			XCTAssertEqual(after.scale, scale)
			XCTAssertEqual(after.offset.x, scale == 1 ? 0 : 180, accuracy: 0.0001)
			XCTAssertEqual(after.offset.y, scale == 1 ? 0 : 370, accuracy: 0.0001)
		}
	}
}
