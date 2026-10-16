import XCTest
@testable import OpenParsecGestures

final class SavedViewportTests: XCTestCase {
	private let portrait = CGSize(width: 400, height: 800)
	private let desktop = CGSize(width: 1920, height: 1080)

	private func saved(scale: CGFloat = 3, offset: CGPoint = CGPoint(x: 400, y: 850),
					   keyboardShift: CGFloat = 0) throws -> SavedViewport {
		try XCTUnwrap(SavedViewport(viewport: ZoomViewport(scale: scale, offset: offset),
			contentSize: portrait, viewportSize: portrait, streamSize: desktop, keyboardShift: keyboardShift))
	}

	private func restore(_ saved: SavedViewport, size: CGSize? = nil,
						 stream: CGSize? = nil, range: ClosedRange<CGFloat> = 1...5) throws -> ZoomViewport {
		try XCTUnwrap(saved.restored(contentSize: size ?? portrait, viewportSize: size ?? portrait,
			streamSize: stream ?? desktop, scaleRange: range))
	}

	func testReconnectRestoresZoomAndPanExactly() throws {
		for offset in [CGPoint.zero, CGPoint(x: 400, y: 850), CGPoint(x: 800, y: 1600)] {
			let restored = try restore(saved(offset: offset))
			XCTAssertEqual(restored.scale, 3)
			XCTAssertEqual(restored.offset.x, offset.x, accuracy: 0.0001)
			XCTAssertEqual(restored.offset.y, offset.y, accuracy: 0.0001)
		}
	}

	func testKeyboardAvoidanceIsNotRemembered() throws {
		let original = try saved()
		let keyboardVisible = try saved(offset: CGPoint(x: 400, y: 1150), keyboardShift: 300)
		XCTAssertEqual(original, keyboardVisible)
		XCTAssertEqual(try restore(keyboardVisible).offset.y, 850, accuracy: 0.0001)
	}

	func testManualPanningIntoKeyboardInsetIsClampedWithoutTheKeyboard() throws {
		let restored = try restore(saved(offset: CGPoint(x: 400, y: 1900)))
		XCTAssertEqual(restored.offset.y, 1600, accuracy: 0.0001)
	}

	func testOrientationChangeKeepsTheSameRemoteDesktopCenter() throws {
		let snapshot = try saved(offset: CGPoint(x: 550, y: 850))
		let landscape = CGSize(width: 800, height: 400)
		let restored = try restore(snapshot, size: landscape)
		let recaptured = try XCTUnwrap(SavedViewport(viewport: restored, contentSize: landscape,
			viewportSize: landscape, streamSize: desktop))
		XCTAssertEqual(recaptured.center.x, snapshot.center.x, accuracy: 0.0001)
		XCTAssertEqual(recaptured.center.y, snapshot.center.y, accuracy: 0.0001)
		XCTAssertEqual(restored.scale, snapshot.scale)
	}

	func testDifferentHostResolutionKeepsRelativePosition() throws {
		let snapshot = try saved()
		let restored = try restore(snapshot, stream: CGSize(width: 2560, height: 1440))
		XCTAssertEqual(restored.offset.x, 400, accuracy: 0.0001)
		XCTAssertEqual(restored.offset.y, 850, accuracy: 0.0001)
	}

	func testLetterboxPositionIsClampedAfterOrientationChange() throws {
		let landscape = CGSize(width: 800, height: 400)
		for (offset, expectedY) in [(CGPoint.zero, CGFloat(0)), (CGPoint(x: 800, y: 1600), CGFloat(800))] {
			let restored = try restore(saved(offset: offset), size: landscape)
			XCTAssertEqual(restored.offset.y, expectedY, accuracy: 0.0001)
			XCTAssertTrue((0...1600).contains(restored.offset.x))
		}
	}

	func testResetZoomRemainsResetOnReconnect() throws {
		let restored = try restore(saved(scale: 1, offset: .zero), size: CGSize(width: 800, height: 400))
		XCTAssertEqual(restored.scale, 1)
		XCTAssertEqual(restored.offset, .zero)
	}

	func testRestoredZoomRespectsCurrentLimits() throws {
		let restored = try restore(saved(scale: 5), range: 1...2)
		XCTAssertEqual(restored.scale, 2)
		XCTAssertTrue((0...400).contains(restored.offset.x))
		XCTAssertTrue((0...800).contains(restored.offset.y))
	}

	func testIncompleteLayoutAndInvalidValuesCannotBeSavedOrRestored() throws {
		let snapshot = try saved()
		for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 800), CGSize(width: 400, height: -1)] {
			XCTAssertNil(snapshot.restored(contentSize: size, viewportSize: portrait,
				streamSize: desktop, scaleRange: 1...5))
			XCTAssertNil(SavedViewport(viewport: ZoomViewport(scale: 2, offset: .zero),
				contentSize: portrait, viewportSize: portrait, streamSize: size))
		}
		for scale in [CGFloat.nan, .infinity, 0, -1] {
			XCTAssertNil(SavedViewport(viewport: ZoomViewport(scale: scale, offset: .zero),
				contentSize: portrait, viewportSize: portrait, streamSize: desktop))
		}
	}

	func testHostsKeepSeparateViewsAcrossStoreInstances() throws {
		let suite = "SavedViewportTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = HostViewportStore(defaults: defaults)
		let first = try saved()
		let second = try saved(scale: 2, offset: CGPoint(x: 150, y: 300))
		store.save(first, for: "host-a")
		store.save(second, for: "host-b")
		let reopened = HostViewportStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
		XCTAssertEqual(reopened.load(for: "host-a"), first)
		XCTAssertEqual(reopened.load(for: "host-b"), second)
		XCTAssertNil(reopened.load(for: "host-c"))
		let reset = try saved(scale: 1, offset: .zero)
		reopened.save(reset, for: "host-a")
		XCTAssertEqual(store.load(for: "host-a"), reset)
		XCTAssertEqual(store.load(for: "host-b"), second)
		reopened.remove(for: "host-a")
		XCTAssertNil(store.load(for: "host-a"))
		XCTAssertEqual(store.load(for: "host-b"), second)
	}

	func testCorruptOrInvalidStoredViewsAreIgnored() throws {
		let suite = "SavedViewportTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = HostViewportStore(defaults: defaults)
		store.save(try saved(), for: "host")
		let key = try XCTUnwrap(defaults.persistentDomain(forName: suite)?.keys.first)
		defaults.set(Data("not JSON".utf8), forKey: key)
		XCTAssertNil(store.load(for: "host"))
		var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved())) as? [String: Any])
		payload["scale"] = -1
		defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: key)
		XCTAssertNil(store.load(for: "host"))
	}
}
