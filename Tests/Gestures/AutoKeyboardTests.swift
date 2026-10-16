import XCTest
import CoreGraphics
@testable import OpenParsecGestures
#if os(macOS)
import AppKit
#endif

final class TextCursorDetectorTests: XCTestCase {
	private let beam = [
		"#######", "...#...", "...#...", "...#...", "...#...", "...#...", "...#...",
		"...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "#######"
	]

	private func image(_ rows: [String], scale: Int = 1, padding: Int = 0, white: Bool = false) -> CGImage {
		let width = rows[0].count * scale + padding * 2
		let height = rows.count * scale + padding * 3
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		for (y, row) in rows.enumerated() {
			for (x, cell) in row.enumerated() where cell == "#" {
				for dy in 0..<scale {
					for dx in 0..<scale {
						let offset = ((y * scale + dy + padding) * width + x * scale + dx + padding) * 4
						for channel in 0..<3 { pixels[offset + channel] = white ? 255 : 0 }
						pixels[offset + 3] = 255
					}
				}
			}
		}
		return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
			bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
			provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
			shouldInterpolate: false, intent: .defaultIntent)!
	}

	func testIBeamAcrossScalesColoursAndTransparentPadding() {
		for scale in [1, 2, 3] {
			for padding in [0, 8] {
				for white in [false, true] {
					XCTAssertTrue(TextCursorDetector.matches(image(beam, scale: scale, padding: padding, white: white),
						hotspot: CGPoint(x: 3 * scale + padding, y: 7 * scale + padding)))
				}
			}
		}
	}

	func testOutlinedIBeam() {
		let rows = ["###...###", "#########"] + Array(repeating: "...###...", count: 17) + ["#########", "###...###"]
		XCTAssertTrue(TextCursorDetector.matches(image(rows), hotspot: CGPoint(x: 4, y: 10)))
	}

	func testArrowAndVerticalResizeAreNotTextCursors() {
		let arrow = ["#......", "##.....", "###....", "####...", "#####..", "######.", "#######",
			"####...", "#.##...", "..##...", "...##..", "...##..", ".......", "......."]
		let resize = ["...#...", "..###..", ".#####.", "#######"] + Array(repeating: "...#...", count: 13) +
			["#######", ".#####.", "..###..", "...#..."]
		XCTAssertFalse(TextCursorDetector.matches(image(arrow), hotspot: .zero))
		XCTAssertFalse(TextCursorDetector.matches(image(resize), hotspot: CGPoint(x: 3, y: 10)))
	}

	func testBlankImageSolidBarAndIncorrectHotspotAreRejected() {
		XCTAssertFalse(TextCursorDetector.matches(image(Array(repeating: ".......", count: 14)), hotspot: CGPoint(x: 3, y: 7)))
		XCTAssertFalse(TextCursorDetector.matches(image(Array(repeating: "...#...", count: 14)), hotspot: CGPoint(x: 3, y: 7)))
		XCTAssertFalse(TextCursorDetector.matches(image(beam), hotspot: .zero))
	}

	#if os(macOS)
	func testSystemTextCursorAndCommonNonTextCursors() {
		for (cursor, expected) in [(NSCursor.iBeam, true), (.arrow, false), (.pointingHand, false),
			(.crosshair, false), (.resizeUpDown, false), (.resizeLeftRight, false)] {
			let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
			let hotspot = CGPoint(x: cursor.hotSpot.x * CGFloat(image.width) / cursor.image.size.width,
				y: cursor.hotSpot.y * CGFloat(image.height) / cursor.image.size.height)
			XCTAssertEqual(TextCursorDetector.matches(image, hotspot: hotspot), expected, "\(cursor)")
		}
	}
	#endif
}

final class AutoKeyboardTriggerTests: XCTestCase {
	func testHoverWithoutTapNeverOpensKeyboard() {
		var trigger = AutoKeyboardTrigger()
		XCTAssertFalse(trigger.shouldOpen(at: 10, textCursor: true))
	}

	func testWaitsForHostResponseAndStableCursorThenOpensOnlyOnce() {
		var trigger = AutoKeyboardTrigger()
		trigger.arm(at: 10)
		XCTAssertFalse(trigger.shouldOpen(at: 10.1, textCursor: true))
		XCTAssertFalse(trigger.shouldOpen(at: 10.25, textCursor: true))
		XCTAssertFalse(trigger.shouldOpen(at: 10.3, textCursor: true))
		XCTAssertTrue(trigger.shouldOpen(at: 10.4, textCursor: true))
		XCTAssertFalse(trigger.isPending)
		XCTAssertFalse(trigger.shouldOpen(at: 10.6, textCursor: true))
	}

	func testCursorChangeResetsStabilityAndAllowsDelayedResponse() {
		var trigger = AutoKeyboardTrigger()
		trigger.arm(at: 10)
		XCTAssertFalse(trigger.shouldOpen(at: 10.25, textCursor: true))
		XCTAssertFalse(trigger.shouldOpen(at: 10.35, textCursor: false))
		XCTAssertFalse(trigger.shouldOpen(at: 10.8, textCursor: true))
		XCTAssertTrue(trigger.shouldOpen(at: 11, textCursor: true))
	}

	func testLateCursorCannotOpenKeyboard() {
		var trigger = AutoKeyboardTrigger()
		trigger.arm(at: 10)
		XCTAssertFalse(trigger.shouldOpen(at: 11.1, textCursor: true))
		XCTAssertFalse(trigger.shouldOpen(at: 11.3, textCursor: true))
		XCTAssertFalse(trigger.isPending)
	}

	func testCancellationPreventsReopeningUntilAnotherTap() {
		var trigger = AutoKeyboardTrigger()
		trigger.arm(at: 10)
		XCTAssertFalse(trigger.shouldOpen(at: 10.25, textCursor: true))
		trigger.cancel()
		XCTAssertFalse(trigger.shouldOpen(at: 10.5, textCursor: true))
		trigger.arm(at: 11)
		XCTAssertFalse(trigger.shouldOpen(at: 11.25, textCursor: true))
		XCTAssertTrue(trigger.shouldOpen(at: 11.5, textCursor: true))
	}

	func testAnotherTapRestartsTheResponseWindow() {
		var trigger = AutoKeyboardTrigger()
		trigger.arm(at: 10)
		XCTAssertFalse(trigger.shouldOpen(at: 10.25, textCursor: true))
		trigger.arm(at: 10.3)
		XCTAssertFalse(trigger.shouldOpen(at: 10.4, textCursor: true))
		XCTAssertFalse(trigger.shouldOpen(at: 10.55, textCursor: true))
		XCTAssertTrue(trigger.shouldOpen(at: 10.7, textCursor: true))
	}
}
