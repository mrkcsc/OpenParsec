import XCTest
@testable import OpenParsecClipboard

final class ClipboardTextTests: XCTestCase {
	func testUnicodeAndMultilineTextRoundTripWithoutChangingContent() {
		let text = "Hello 👋\nCafé — 日本語\t\"quoted\"\r\nSecond line"
		XCTAssertNil(ClipboardText.validationError(text))
		XCTAssertEqual(ClipboardText.decode(Data(text.utf8)), text)
	}

	func testKeyboardWordsRemainLiteralClipboardText() {
		let text = "CONTROL\nBACKSPACE\nLGUI\nDELETE"
		XCTAssertEqual(ClipboardText.decode(Data(text.utf8)), text)
	}

	func testNullCharactersCannotSilentlyTruncatePastes() {
		let text = "before\0after"
		XCTAssertNotNil(ClipboardText.validationError(text))
		XCTAssertNil(ClipboardText.decode(Data(text.utf8)))
	}

	func testInvalidUTF8IsNotReplacedWithDifferentText() {
		XCTAssertNil(ClipboardText.decode(Data([0xC3, 0x28])))
	}

	func testSizeLimitUsesUTF8BytesRatherThanCharacterCount() {
		let atLimit = String(repeating: "🙂", count: ClipboardText.maximumBytes / 4)
		XCTAssertNil(ClipboardText.validationError(atLimit))
		XCTAssertEqual(ClipboardText.decode(Data(atLimit.utf8)), atLimit)
		let overLimit = atLimit + "a"
		XCTAssertNotNil(ClipboardText.validationError(overLimit))
		XCTAssertNil(ClipboardText.decode(Data(overLimit.utf8)))
	}
}
