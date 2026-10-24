import SwiftUI
import UIKit
import ParsecSDK

extension Notification.Name {
	static let parsecClipboardReceived = Notification.Name("ParsecClipboardReceived")
}

final class StreamClipboardController: UIResponder, ObservableObject {
	@Published private(set) var message: String?
	@Published private(set) var isPasting = false
	@Published var usesCommand: Bool {
		didSet { UserDefaults.standard.set(usesCommand, forKey: "clipboardUsesCommand") }
	}
	private let service: ParsecService
	private let shortcut: (ParsecKeycode, Bool) -> Void
	private var observer: NSObjectProtocol?
	private var backgroundObserver: NSObjectProtocol?
	private var pasteRequest = UUID()

	init(service: ParsecService, shortcut: @escaping (ParsecKeycode, Bool) -> Void) {
		self.service = service
		self.shortcut = shortcut
		usesCommand = UserDefaults.standard.object(forKey: "clipboardUsesCommand") as? Bool ?? true
		super.init()
		pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
		observer = NotificationCenter.default.addObserver(forName: .parsecClipboardReceived,
			object: nil, queue: .main) { [weak self] note in
			guard let self, self.isActive,
				  (note.object as AnyObject?) === self.service,
				  note.userInfo?["generation"] as? Int == self.service.connectionGeneration,
				  let text = note.userInfo?["text"] as? String, !text.isEmpty else { return }
			// Keep remote copies on this device; Universal Clipboard could otherwise echo them to the host.
			UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
			self.message = "Copied from host"
		}
		backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
			object: nil, queue: .main) { [weak self] _ in
			self?.pasteRequest = UUID()
			self?.isPasting = false
		}
	}

	deinit {
		if let observer { NotificationCenter.default.removeObserver(observer) }
		if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
	}

	private var isActive: Bool {
		UIApplication.shared.applicationState == .active && CParsec.parsecImpl === service &&
			service.getStatus() == PARSEC_OK && !DataManager.model.isBlocked
	}

	func copySelection() {
		guard !isPasting else { return }
		guard isActive else { message = "Connect to the host to copy text."; return }
		message = "Copy requested"
		shortcut(KEY_C, usesCommand)
	}

	override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
		!isPasting && itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
	}

	override func paste(itemProviders: [NSItemProvider]) {
		guard !isPasting, isActive,
			  let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
		let generation = service.connectionGeneration
		let request = UUID()
		pasteRequest = request
		isPasting = true
		message = nil
		provider.loadObject(ofClass: NSString.self) { [weak self] object, error in
			DispatchQueue.main.async {
				guard let self, self.pasteRequest == request else { return }
				guard error == nil, let text = object as? String else {
					self.isPasting = false
					self.message = "Could not read clipboard text."
					return
				}
				self.send(text, generation: generation, request: request)
			}
		}
	}

	override func paste(_ sender: Any?) {
		guard !isPasting, isActive else { return }
		guard let text = UIPasteboard.general.string else { message = "Copy some text first."; return }
		pasteRequest = UUID()
		isPasting = true
		send(text, generation: service.connectionGeneration, request: pasteRequest)
	}

	private func send(_ text: String, generation: Int, request: UUID) {
		guard isActive, generation == service.connectionGeneration else {
			isPasting = false
			message = "Connection changed. Tap Paste again."
			return
		}
		if let error = ClipboardText.validationError(text) {
			isPasting = false
			message = error
			return
		}
		guard !text.isEmpty else { isPasting = false; message = "Copy some text first."; return }
		guard service.sendClipboardText(text) == PARSEC_OK else {
			isPasting = false
			message = "Could not send the clipboard. Try again."
			return
		}
		let command = usesCommand
		// Clipboard updates and keyboard input take separate paths through the host.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
			guard let self, self.pasteRequest == request else { return }
			self.isPasting = false
			guard self.isActive, generation == self.service.connectionGeneration else {
				self.message = "Connection changed. Tap Paste again."
				return
			}
			self.shortcut(KEY_V, command)
			self.message = "Paste sent"
		}
	}

	func makePasteControl() -> UIView {
		if #available(iOS 16.0, *) {
			let config = UIPasteControl.Configuration()
			config.displayMode = .iconAndLabel
			config.baseForegroundColor = .white
			config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.8)
			config.cornerRadius = 8
			let control = UIPasteControl(configuration: config)
			control.target = self
			control.accessibilityHint = "Paste text from this device into the host"
			return control
		}
		let button = UIButton(type: .system)
		button.setTitle("Paste", for: .normal)
		button.setTitleColor(.white, for: .normal)
		button.addTarget(self, action: #selector(paste(_:)), for: .touchUpInside)
		return button
	}
}

struct StreamClipboardControls: View {
	@ObservedObject var clipboard: StreamClipboardController
	let enabled: Bool

	var body: some View {
		VStack(spacing: 4) {
			HStack(spacing: 4) {
				Button(action: clipboard.copySelection) {
					Label("Copy", systemImage: "doc.on.doc")
						.font(.system(size: 14, weight: .medium))
						.frame(maxWidth: .infinity, minHeight: 44)
				}
				.accessibilityLabel("Copy selected text from host")
				StreamPasteButton(clipboard: clipboard)
					.frame(width: 90, height: 44)
			}
			.disabled(!enabled || clipboard.isPasting)
			Menu {
				Button("Mac (⌘C / ⌘V)") { clipboard.usesCommand = true }
				Button("Windows / Linux (Ctrl+C / Ctrl+V)") { clipboard.usesCommand = false }
			} label: {
				Text("Shortcuts: \(clipboard.usesCommand ? "Mac ⌘" : "Ctrl")")
					.font(.caption)
					.frame(maxWidth: .infinity, minHeight: 32)
			}
			if let message = clipboard.message {
				Text(message)
					.font(.caption2)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(.horizontal, 6)
		.padding(.bottom, 6)
	}
}

private struct StreamPasteButton: UIViewRepresentable {
	let clipboard: StreamClipboardController
	func makeUIView(context: Context) -> UIView { clipboard.makePasteControl() }
	func updateUIView(_ uiView: UIView, context: Context) {
		uiView.isUserInteractionEnabled = context.environment.isEnabled
	}
}
