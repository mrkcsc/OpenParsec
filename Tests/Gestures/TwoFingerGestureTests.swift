import XCTest
@testable import OpenParsecGestures

final class TwoFingerGestureTests: XCTestCase {
	private func gesture() -> TwoFingerGesture {
		TwoFingerGesture(first: CGPoint(x: 100, y: 200), second: CGPoint(x: 200, y: 200))
	}

	func testTapJitterDoesNotRecognizeAGesture() {
		var gesture = gesture()
		for delta in [2.0, -3, 1, 0] {
			let update = gesture.update(first: CGPoint(x: 100 + delta, y: 200), second: CGPoint(x: 200, y: 201))
			XCTAssertEqual(update.mode, .undecided)
		}
	}

	func testPinchKeepsMovementAccumulatedBeforeRecognition() {
		var gesture = gesture()
		XCTAssertEqual(gesture.update(first: CGPoint(x: 97, y: 200), second: CGPoint(x: 203, y: 200)).mode, .undecided)
		let update = gesture.update(first: CGPoint(x: 90, y: 200), second: CGPoint(x: 210, y: 200))
		XCTAssertEqual(update.mode, .zoom)
		XCTAssertEqual(update.scaleFactor, 1.2, accuracy: 0.0001)
	}

	func testPinchWithOneStationaryFinger() {
		var gesture = gesture()
		let update = gesture.update(first: CGPoint(x: 100, y: 200), second: CGPoint(x: 240, y: 200))
		XCTAssertEqual(update.mode, .zoom)
		XCTAssertEqual(update.scaleFactor, 1.4, accuracy: 0.0001)
	}

	func testPinchInAndDiagonalPinch() {
		var inward = gesture()
		XCTAssertEqual(inward.update(first: CGPoint(x: 120, y: 200), second: CGPoint(x: 180, y: 200)).mode, .zoom)
		var diagonal = TwoFingerGesture(first: CGPoint(x: 100, y: 100), second: CGPoint(x: 200, y: 200))
		let update = diagonal.update(first: CGPoint(x: 80, y: 80), second: CGPoint(x: 220, y: 220))
		XCTAssertEqual(update.mode, .zoom)
		XCTAssertEqual(update.scaleFactor, 1.4, accuracy: 0.0001)
	}

	func testParallelMovementScrollsDespiteSmallSeparationNoise() {
		var gesture = gesture()
		let update = gesture.update(first: CGPoint(x: 101, y: 220), second: CGPoint(x: 199, y: 224))
		XCTAssertEqual(update.mode, .scroll)
		XCTAssertEqual(update.midpoint.y - update.previousMidpoint.y, 22, accuracy: 0.0001)
	}

	func testScrollDoesNotSwitchToZoomMidGesture() {
		var gesture = gesture()
		_ = gesture.update(first: CGPoint(x: 100, y: 220), second: CGPoint(x: 200, y: 220))
		XCTAssertEqual(gesture.update(first: CGPoint(x: 50, y: 225), second: CGPoint(x: 250, y: 225)).mode, .scroll)
	}

	func testRecognizedPinchCanPanWithoutScrollingTheHost() {
		var gesture = gesture()
		_ = gesture.update(first: CGPoint(x: 90, y: 200), second: CGPoint(x: 210, y: 200))
		let update = gesture.update(first: CGPoint(x: 110, y: 240), second: CGPoint(x: 230, y: 240))
		XCTAssertEqual(update.mode, .zoom)
		XCTAssertEqual(update.scaleFactor, 1)
		XCTAssertEqual(update.previousMidpoint, CGPoint(x: 150, y: 200))
		XCTAssertEqual(update.midpoint, CGPoint(x: 170, y: 240))
	}

	func testRotationAloneDoesNotZoomOrScroll() {
		var gesture = gesture()
		let update = gesture.update(first: CGPoint(x: 150, y: 150), second: CGPoint(x: 150, y: 250))
		XCTAssertEqual(update.mode, .undecided)
	}

	func testCoincidentTouchesDoNotProduceInfiniteScale() {
		var gesture = TwoFingerGesture(first: .zero, second: .zero)
		let update = gesture.update(first: .zero, second: CGPoint(x: 30, y: 0))
		XCTAssertTrue(update.scaleFactor.isFinite)
	}
}

final class ZoomViewportTests: XCTestCase {
	private let size = CGSize(width: 400, height: 800)

	private func pinch(_ viewport: ZoomViewport, factor: CGFloat,
					   from: CGPoint = CGPoint(x: 200, y: 400), to: CGPoint = CGPoint(x: 200, y: 400),
					   bottomInset: CGFloat = 0) -> ZoomViewport {
		viewport.pinching(by: factor, from: from, to: to, contentSize: size, viewportSize: size,
			bottomInset: bottomInset, scaleRange: 1...5)
	}

	func testContentUnderFingersStaysAnchoredWhilePinchingAndPanning() {
		let before = ZoomViewport(scale: 2, offset: CGPoint(x: 100, y: 200))
		let from = CGPoint(x: 150, y: 300)
		let to = CGPoint(x: 170, y: 340)
		let after = pinch(before, factor: 1.5, from: from, to: to)
		XCTAssertEqual((before.offset.x + from.x) / before.scale, (after.offset.x + to.x) / after.scale, accuracy: 0.0001)
		XCTAssertEqual((before.offset.y + from.y) / before.scale, (after.offset.y + to.y) / after.scale, accuracy: 0.0001)
	}

	func testPinchingOutAndBackDoesNotDrift() {
		let original = ZoomViewport(scale: 1, offset: .zero)
		let zoomed = pinch(original, factor: 3)
		let restored = pinch(zoomed, factor: 1.0 / 3)
		XCTAssertEqual(restored.scale, 1, accuracy: 0.0001)
		XCTAssertEqual(restored.offset, .zero)
	}

	func testZoomLimitsAndImmediateReversalAtMaximum() {
		let maxZoom = pinch(ZoomViewport(scale: 4, offset: CGPoint(x: 600, y: 1200)), factor: 10)
		XCTAssertEqual(maxZoom.scale, 5)
		XCTAssertEqual(pinch(maxZoom, factor: 0.9).scale, 4.5)
		let minimum = pinch(maxZoom, factor: 0.01)
		XCTAssertEqual(minimum.scale, 1)
		XCTAssertEqual(minimum.offset, .zero)
	}

	func testPanningAtMaximumZoomStillWorks() {
		let before = ZoomViewport(scale: 5, offset: CGPoint(x: 600, y: 1200))
		let after = pinch(before, factor: 1.1, to: CGPoint(x: 220, y: 430))
		XCTAssertEqual(after.scale, 5)
		XCTAssertEqual(after.offset, CGPoint(x: 580, y: 1170))
	}

	func testPanningClampsAtAllEdges() {
		let viewport = ZoomViewport(scale: 2, offset: CGPoint(x: 200, y: 400))
		let upperLeft = pinch(viewport, factor: 1, to: CGPoint(x: 2000, y: 2000))
		XCTAssertEqual(upperLeft.offset, .zero)
		let lowerRight = pinch(viewport, factor: 1, to: CGPoint(x: -2000, y: -2000))
		XCTAssertEqual(lowerRight.offset, CGPoint(x: 400, y: 800))
	}

	func testKeyboardInsetAllowsAccessToBottomOfContent() {
		let viewport = ZoomViewport(scale: 2, offset: CGPoint(x: 0, y: 800))
		let after = pinch(viewport, factor: 1, to: CGPoint(x: 200, y: -1000), bottomInset: 300)
		XCTAssertEqual(after.offset.y, 1100)
	}

	func testInvalidScaleDoesNotCorruptViewport() {
		let viewport = ZoomViewport(scale: 2, offset: CGPoint(x: 50, y: 100))
		for factor in [CGFloat.nan, .infinity, 0, -1] {
			let after = pinch(viewport, factor: factor)
			XCTAssertEqual(after.scale, viewport.scale)
			XCTAssertEqual(after.offset, viewport.offset)
		}
	}
}
