import Foundation

struct SavedViewport: Codable, Equatable {
	let scale: CGFloat
	let center: CGPoint

	var isValid: Bool {
		scale.isFinite && scale > 0 && center.x.isFinite && center.y.isFinite
	}

	init?(viewport: ZoomViewport, contentSize: CGSize, viewportSize: CGSize,
		  streamSize: CGSize, keyboardShift: CGFloat = 0) {
		guard Self.validSizes(contentSize, viewportSize, streamSize),
			  viewport.scale.isFinite, viewport.scale > 0,
			  viewport.offset.x.isFinite, viewport.offset.y.isFinite, keyboardShift.isFinite else { return nil }
		scale = viewport.scale
		let stream = KeyboardViewport.streamRect(streamSize: streamSize, contentSize: contentSize)
		let maxX = max(0, contentSize.width * scale - viewportSize.width)
		let maxY = max(0, contentSize.height * scale - viewportSize.height)
		let offset = CGPoint(x: min(maxX, max(0, viewport.offset.x)),
			y: min(maxY, max(0, viewport.offset.y - keyboardShift)))
		// Store the center relative to the remote desktop, independent of letterboxing.
		center = CGPoint(x: ((offset.x + viewportSize.width / 2) / scale - stream.minX) / stream.width,
			y: ((offset.y + viewportSize.height / 2) / scale - stream.minY) / stream.height)
	}

	func restored(contentSize: CGSize, viewportSize: CGSize, streamSize: CGSize,
				  scaleRange: ClosedRange<CGFloat>) -> ZoomViewport? {
		guard isValid, Self.validSizes(contentSize, viewportSize, streamSize) else { return nil }
		let zoom = min(scaleRange.upperBound, max(scaleRange.lowerBound, scale))
		let stream = KeyboardViewport.streamRect(streamSize: streamSize, contentSize: contentSize)
		let maxX = max(0, contentSize.width * zoom - viewportSize.width)
		let maxY = max(0, contentSize.height * zoom - viewportSize.height)
		return ZoomViewport(scale: zoom, offset: CGPoint(
			x: min(maxX, max(0, (stream.minX + center.x * stream.width) * zoom - viewportSize.width / 2)),
			y: min(maxY, max(0, (stream.minY + center.y * stream.height) * zoom - viewportSize.height / 2))))
	}

	private static func validSizes(_ sizes: CGSize...) -> Bool {
		sizes.allSatisfy { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }
	}
}

struct HostViewportStore {
	var defaults: UserDefaults = .standard
	private func key(for hostID: String) -> String { "hostViewport.v1.\(hostID)" }

	func load(for hostID: String) -> SavedViewport? {
		guard !hostID.isEmpty, let data = defaults.data(forKey: key(for: hostID)),
			  let viewport = try? JSONDecoder().decode(SavedViewport.self, from: data),
			  viewport.isValid else { return nil }
		return viewport
	}

	func save(_ viewport: SavedViewport, for hostID: String) {
		guard !hostID.isEmpty, viewport.isValid, let data = try? JSONEncoder().encode(viewport) else { return }
		defaults.set(data, forKey: key(for: hostID))
	}

	func remove(for hostID: String) {
		defaults.removeObject(forKey: key(for: hostID))
	}
}
