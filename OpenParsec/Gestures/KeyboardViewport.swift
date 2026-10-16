import Foundation

struct KeyboardViewport {
	let offset: CGPoint
	let bottomInset: CGFloat
	let shift: CGFloat
	let coveredBottom: CGFloat

	static func streamRect(streamSize: CGSize, contentSize: CGSize) -> CGRect {
		guard streamSize.width > 0, streamSize.height > 0 else {
			return CGRect(origin: .zero, size: contentSize)
		}
		let scale = min(contentSize.width / streamSize.width, contentSize.height / streamSize.height)
		let size = CGSize(width: streamSize.width * scale, height: streamSize.height * scale)
		return CGRect(x: (contentSize.width - size.width) / 2,
					  y: (contentSize.height - size.height) / 2, width: size.width, height: size.height)
	}

	static func avoiding(_ keyboard: CGRect, viewportSize: CGSize, contentSize: CGSize,
						 streamSize: CGSize, zoom: CGFloat, offset: CGPoint,
						 previousShift: CGFloat, tapPoint: CGPoint?) -> KeyboardViewport {
		let viewport = CGRect(origin: .zero, size: viewportSize)
		let occlusion = viewport.intersection(keyboard)
		let maxX = max(0, contentSize.width * zoom - viewportSize.width)
		let maxY = max(0, contentSize.height * zoom - viewportSize.height)
		var base = CGPoint(x: min(maxX, max(0, offset.x)), y: max(0, offset.y - previousShift))
		guard !occlusion.isNull, !occlusion.isEmpty else {
			base.y = min(base.y, maxY)
			return KeyboardViewport(offset: base, bottomInset: 0, shift: 0, coveredBottom: 0)
		}

		let stream = streamRect(streamSize: streamSize, contentSize: contentSize)
		let visibleStream = CGRect(x: stream.minX * zoom - base.x, y: stream.minY * zoom - base.y,
			width: stream.width * zoom, height: stream.height * zoom).intersection(viewport)
		var target = visibleStream
		if let tapPoint, stream.contains(tapPoint) {
			let screenPoint = CGPoint(x: tapPoint.x * zoom - base.x, y: tapPoint.y * zoom - base.y)
			if visibleStream.contains(screenPoint) {
				// A click is a hint for the input location, not knowledge of the host's focused field.
				target = CGRect(x: screenPoint.x - 16, y: screenPoint.y - 16, width: 32, height: 32)
					.intersection(visibleStream)
			}
		}
		let overlap = target.intersection(occlusion)
		let shift = overlap.isNull || overlap.isEmpty ? 0 : max(0, target.maxY - occlusion.minY)
		let coversBottom = occlusion.maxY >= viewport.maxY - 1 &&
			occlusion.minX <= viewport.minX && occlusion.maxX >= viewport.maxX
		let coveredBottom = coversBottom ? occlusion.height : 0
		let next = CGPoint(x: base.x, y: base.y + shift)
		return KeyboardViewport(offset: next, bottomInset: max(coveredBottom, next.y - maxY),
			shift: shift, coveredBottom: coveredBottom)
	}
}
