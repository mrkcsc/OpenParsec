import Foundation
import CoreGraphics

enum TextCursorDetector {
	static func matches(_ image: CGImage, hotspot: CGPoint) -> Bool {
		let width = image.width
		let height = image.height
		guard (1...512).contains(width), (1...512).contains(height) else { return false }
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
				bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard rendered else { return false }

		// Use the opaque silhouette so cursor colour and transparent canvas padding don't matter.
		var left = [Int](repeating: width, count: height)
		var right = [Int](repeating: -1, count: height)
		for y in 0..<height {
			for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 64 {
				left[y] = min(left[y], x)
				right[y] = max(right[y], x)
			}
		}
		guard let top = right.firstIndex(where: { $0 >= 0 }),
			  let bottom = right.lastIndex(where: { $0 >= 0 }),
			  let minX = left.min(), let maxX = right.max() else { return false }
		let w = CGFloat(maxX - minX + 1)
		let h = CGFloat(bottom - top + 1)
		let centerX = CGFloat(minX + maxX) / 2
		let centerY = CGFloat(top + bottom) / 2
		guard w >= 3, h >= 10, h >= w * 1.5, h <= w * 8,
			  abs(hotspot.x - centerX) <= max(2, w * 0.3),
			  abs(hotspot.y - centerY) <= h * 0.3 else { return false }

		// An I-beam has wide caps at both ends and a narrow, centred stem. The end-cap
		// check distinguishes it from a vertical resize arrow with a similar aspect ratio.
		func span(_ y: Int) -> CGFloat { CGFloat(max(0, right[y] - left[y] + 1)) }
		let capDepth = max(1, Int(h * 0.15))
		let topCap = (top..<(top + capDepth)).map(span).max() ?? 0
		let bottomCap = ((bottom - capDepth + 1)...bottom).map(span).max() ?? 0
		guard topCap >= w * 0.75, bottomCap >= w * 0.75 else { return false }
		let stemRows = (top + Int(h * 0.3))...(top + Int(h * 0.7))
		return stemRows.allSatisfy { y in
			span(y) > 0 && span(y) <= w * 0.65 &&
				abs(CGFloat(left[y] + right[y]) / 2 - centerX) <= max(1, w * 0.15)
		}
	}
}

struct AutoKeyboardTrigger {
	private var tappedAt: TimeInterval?
	private var textCursorSince: TimeInterval?
	var isPending: Bool { tappedAt != nil }

	mutating func arm(at time: TimeInterval) {
		tappedAt = time
		textCursorSince = nil
	}

	mutating func cancel() {
		tappedAt = nil
		textCursorSince = nil
	}

	mutating func shouldOpen(at time: TimeInterval, textCursor: Bool) -> Bool {
		guard let tappedAt else { return false }
		guard time <= tappedAt + 1.2 else { cancel(); return false }
		// Allow the host to respond to the click, then require a stable text cursor.
		guard time >= tappedAt + 0.2 else { return false }
		guard textCursor else { textCursorSince = nil; return false }
		guard let textCursorSince else { self.textCursorSince = time; return false }
		guard time - textCursorSince >= 0.1 else { return false }
		cancel()
		return true
	}
}
