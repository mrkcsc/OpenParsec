import Foundation

enum ClipboardText {
	static let maximumBytes = 1_048_576

	static func validationError(_ text: String) -> String? {
		if text.utf8.contains(0) { return "This text contains a null character and cannot be sent." }
		if text.utf8.count > maximumBytes { return "Clipboard text is too large (maximum 1 MB)." }
		return nil
	}

	static func decode(_ data: Data) -> String? {
		guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8),
			  validationError(text) == nil else { return nil }
		return text
	}
}
