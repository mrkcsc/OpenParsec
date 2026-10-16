import XCTest
@testable import OpenParsecGestures

final class KeyboardViewportTests: XCTestCase {
	private let portrait = CGSize(width: 400, height: 900)
	private let desktop = CGSize(width: 1920, height: 1080)

	private func layout(top: CGFloat, offset: CGPoint = .zero, previousShift: CGFloat = 0,
						zoom: CGFloat = 1, tap: CGPoint? = nil) -> KeyboardViewport {
		KeyboardViewport.avoiding(CGRect(x: 0, y: top, width: 400, height: 900 - top),
			viewportSize: portrait, contentSize: portrait, streamSize: desktop,
			zoom: zoom, offset: offset, previousShift: previousShift, tapPoint: tap)
	}

	func testKeyboardEntirelyInsideBlackBorderDoesNotMoveStream() {
		let result = layout(top: 600)
		XCTAssertEqual(result.offset, .zero)
		XCTAssertEqual(result.shift, 0)
		XCTAssertEqual(result.bottomInset, 300)
	}

	func testOnlyActualStreamOverlapIsRemoved() {
		// The fitted desktop ends at y=562.5, leaving 337.5 points of black border.
		let result = layout(top: 500)
		XCTAssertEqual(result.offset.y, 62.5)
		XCTAssertEqual(result.shift, 62.5)
	}

	func testVisibleTapAllowsKeyboardToCoverLowerPartOfStream() {
		let result = layout(top: 500, tap: CGPoint(x: 200, y: 450))
		XCTAssertEqual(result.offset, .zero)
	}

	func testCoveredTapGetsOnlyEnoughRoomPlusSmallMargin() {
		let result = layout(top: 500, tap: CGPoint(x: 200, y: 535))
		XCTAssertEqual(result.offset.y, 51)
		XCTAssertLessThan(result.shift, layout(top: 500).shift)
	}

	func testTapInBlackBorderDoesNotOverrideStreamBounds() {
		XCTAssertEqual(layout(top: 500, tap: CGPoint(x: 200, y: 700)).offset.y, 62.5)
	}

	func testRepeatedKeyboardNotificationsDoNotAccumulateMovement() {
		let first = layout(top: 500)
		let repeated = layout(top: 500, offset: first.offset, previousShift: first.shift)
		XCTAssertEqual(repeated.offset, first.offset)
		let taller = layout(top: 450, offset: repeated.offset, previousShift: repeated.shift)
		XCTAssertEqual(taller.offset.y, 112.5)
		let shorter = layout(top: 600, offset: taller.offset, previousShift: taller.shift)
		XCTAssertEqual(shorter.offset, .zero)
	}

	func testZoomedTapUsesContentCoordinatesAndPreservesHorizontalPan() {
		let result = layout(top: 600, offset: CGPoint(x: 100, y: 300), zoom: 2,
			tap: CGPoint(x: 200, y: 475))
		XCTAssertEqual(result.offset, CGPoint(x: 100, y: 366))
		XCTAssertEqual(result.shift, 66)
	}

	func testDismissalRestoresOriginalOffsetInBothOrientations() {
		for size in [portrait, CGSize(width: 900, height: 400)] {
			let original = CGPoint(x: 100, y: 200)
			let shown = KeyboardViewport.avoiding(CGRect(x: 0, y: size.height - 250, width: size.width, height: 250),
				viewportSize: size, contentSize: size, streamSize: desktop,
				zoom: 2, offset: original, previousShift: 0, tapPoint: nil)
			let hidden = KeyboardViewport.avoiding(.null, viewportSize: size, contentSize: size, streamSize: desktop,
				zoom: 2, offset: shown.offset, previousShift: shown.shift, tapPoint: nil)
			XCTAssertEqual(hidden.offset, original)
			XCTAssertEqual(hidden.bottomInset, 0)
		}
	}

	func testManualPanWhileKeyboardOpenIsPreservedOnDismissal() {
		let hidden = KeyboardViewport.avoiding(.null, viewportSize: portrait, contentSize: portrait,
			streamSize: desktop, zoom: 2, offset: CGPoint(x: 100, y: 400), previousShift: 0, tapPoint: nil)
		XCTAssertEqual(hidden.offset, CGPoint(x: 100, y: 400))
	}

	func testDismissalClampsOnlyOffsetOutsideNormalContentBounds() {
		let hidden = KeyboardViewport.avoiding(.null, viewportSize: portrait, contentSize: portrait,
			streamSize: desktop, zoom: 1, offset: CGPoint(x: 0, y: 200), previousShift: 0, tapPoint: nil)
		XCTAssertEqual(hidden.offset, .zero)
	}

	func testFloatingKeyboardOnlyMovesAnOverlappingTarget() {
		let keyboard = CGRect(x: 200, y: 600, width: 200, height: 200)
		let clear = KeyboardViewport.avoiding(keyboard, viewportSize: portrait, contentSize: portrait,
			streamSize: portrait, zoom: 1, offset: .zero, previousShift: 0, tapPoint: CGPoint(x: 100, y: 650))
		XCTAssertEqual(clear.offset, .zero)
		let covered = KeyboardViewport.avoiding(keyboard, viewportSize: portrait, contentSize: portrait,
			streamSize: portrait, zoom: 1, offset: .zero, previousShift: 0, tapPoint: CGPoint(x: 300, y: 650))
		XCTAssertEqual(covered.shift, 66)
		XCTAssertEqual(covered.bottomInset, 66)
		XCTAssertEqual(covered.coveredBottom, 0)
	}

	func testUnknownStreamSizeFallsBackToContentBounds() {
		XCTAssertEqual(KeyboardViewport.streamRect(streamSize: .zero, contentSize: portrait),
			CGRect(origin: .zero, size: portrait))
	}
}
