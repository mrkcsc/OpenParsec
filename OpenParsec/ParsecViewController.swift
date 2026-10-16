import Foundation
import UIKit
import ParsecSDK
import QuartzCore

protocol ParsecPlayground {
	init(viewController: UIViewController, updateImage: @escaping () -> Void)
	func viewDidLoad()
	func cleanUp()
	func updateSize(width: CGFloat, height: CGFloat)
}

class ParsecViewController: UIViewController, UIScrollViewDelegate, ParsecTouchInputDelegate {
	var glkView: ParsecPlayground!
	var gamePadController: GamepadController!
	var touchController: TouchController!
	var u: UIImageView?
	var lastImg: CGImage?
    var lastMouseX: Int32 = -1
    var lastMouseY: Int32 = -1
    var lastCursorHidden: Bool = false
	private var pendingDirectPress: DispatchWorkItem?
	private var directPressActive = false
	private var directTouchWasPressed = false
	var appliedRenderScale: CGFloat = 0       // last contentScaleFactor applied (avoids redundant reallocations)
	let maxRenderScale: CGFloat = 6.0         // cap on drawable density
	var clickHoldActive = false        // left button held via long-press (file drag)
	// Flick-to-glide momentum (tuned constants, not user settings).
	var momentumLink: CADisplayLink?
	var cursorMomentumActive = false
	var scrollMomentumActive = false
	var edgeScrollActive = false
	var edgeScrollPoint: CGPoint = .zero
	var edgeScrollLastTick: CFTimeInterval = 0
	let edgeScrollMargin: CGFloat = 44.0
	let edgeScrollMaxSpeed: CGFloat = 900.0
	var cursorVelocity: CGPoint = .zero     // content points / sec
	var scrollVelocity: Float = 0.0         // wheel units / sec
	var lastCursorMoveTime: CFTimeInterval = 0
	var lastScrollMoveTime: CFTimeInterval = 0
	let flingMinSpeed: CGFloat = 80.0       // min release speed (content pts/sec) to start a cursor glide
	let cursorStopSpeed: CGFloat = 40.0     // end the glide below this speed (lower = gentler, less abrupt)
	let cursorDecayPerSec: Double = 0.08    // fraction of speed left after 1s (bigger = longer glide)
	let scrollStartSpeed: Float = 800.0     // min release speed (wheel units/sec) to start a scroll glide
	let scrollStopSpeed: Float = 200.0
	let scrollDecayPerSec: Double = 0.004
	// A left click fires only if the finger barely moved (else it's a cursor nudge).
	var cursorDidMoveThisTouch = false
	var singleTouchStartScreen: CGPoint = .zero
	let tapMoveSlop: CGFloat = 4.0          // finger movement (pts) above which a touch is a drag, not a tap
	var twoFingerDidMove = false            // true once a 2-finger gesture became a pinch/scroll (suppresses right-click)

	var mouseSensitivity: Float = Float(SettingsHandler.mouseSensitivity)
	// Two-finger scroll-wheel accumulation, kept separate from cursor movement.
	var lastScrollTranslation: CGPoint = .zero
	var accumulatedScrollY: Float = 0.0
	var scrollWheelSpeed: Float { Float(SettingsHandler.scrollSensitivity) * 2.3 }

	// Input-driven cursor + viewport state (manual touch handling via TouchOverlayView).
	var touchOverlay: TouchOverlayView!
	var cursorContentPos: CGPoint = .zero
	var isDragging = false
	var twoFingerResidual = false       // leftover finger after a 2-finger gesture; inert until full lift
	var activeTouches: [UITouch] = []   // ordered; first two drive pinch / scroll
	private var twoFingerGesture: TwoFingerGesture?
	private var threeFingerGesture: ThreeFingerPanGesture?
	private var threeFingerDidMove = false

	var keyboardAccessoriesView: UIView?
	var keyboardHeight: CGFloat = 0.0
	var keyboardVisible: Bool = false
	private var keyboardFrameInScreen = CGRect.null
	private var keyboardViewportShift: CGFloat = 0
	private var lastTapContentPoint: CGPoint?
	private var autoKeyboardTimer: Timer?
	private var autoKeyboardTrigger = AutoKeyboardTrigger()
	var onKeyboardVisibilityChanged: ((Bool) -> Void)?
	var scrollView: UIScrollView!
	var contentView: UIView!
	var lastLaidOutWidth: CGFloat = 0
	var lastLaidOutHeight: CGFloat = 0

	override var prefersPointerLocked: Bool {
		return true
	}

	override var prefersHomeIndicatorAutoHidden: Bool {
		return true
	}

	init() {
		super.init(nibName: nil, bundle: nil)

		self.glkView = ParsecGLKViewController(viewController: self, updateImage: { [weak self] in self?.updateImage() })

		self.gamePadController = GamepadController()
		self.touchController = TouchController()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func computeRenderScale() -> CGFloat {
		let nativeScale = UIScreen.main.nativeScale
		guard scrollView.zoomScale > 1.01, let glk = glkView as? ParsecGLKViewController else { return nativeScale }
		let vw = glk.glkView.frame.size.width
		let vh = glk.glkView.frame.size.height
		let sw = CGFloat(CParsec.hostWidth)
		let sh = CGFloat(CParsec.hostHeight)
		guard vw > 0, vh > 0, sw > 0, sh > 0 else { return nativeScale }
		// Match the drawable to the source so zoom stays crisp without rendering wasted pixels.
		let needed = max(sw / vw, sh / vh)
		return min(maxRenderScale, max(nativeScale, needed))
	}

	func updateRenderScale() {
		let target = computeRenderScale()
		if abs(target - appliedRenderScale) > 0.01 {
			appliedRenderScale = target
			DispatchQueue.main.async { [weak self] in
				(self?.glkView as? ParsecGLKViewController)?.glkView.contentScaleFactor = target
			}
		}
	}

	func updateImage() {
		updateRenderScale()
        // Optimization: Snap current valus
        let currentMouseX = CParsec.mouseInfo.mouseX
        let currentMouseY = CParsec.mouseInfo.mouseY
        let currentHidden = CParsec.mouseInfo.cursorHidden
        let currentImg = CParsec.mouseInfo.cursorImg

        // Skip if nothing changed
		let hostCursorMoved = currentMouseX != lastMouseX || currentMouseY != lastMouseY
		if currentMouseX == lastMouseX &&
           currentMouseY == lastMouseY &&
           currentHidden == lastCursorHidden &&
           currentImg == lastImg {
            return
        }

        lastMouseX = currentMouseX
        lastMouseY = currentMouseY
        lastCursorHidden = currentHidden

		if currentImg != nil && !currentHidden {
			u?.isHidden = false
			if lastImg != currentImg {
				u!.image = UIImage(cgImage: currentImg!)
				lastImg = currentImg!
			}

			// While dragging, the touch handler owns the cursor position and viewport (smooth,
			// input-driven). When idle, follow the host's reported cursor so host- or keyboard-
			// driven moves are reflected and any prediction drift is corrected.
			if !isDragging && !clickHoldActive && !cursorMomentumActive && activeTouches.isEmpty {
				let fingerSet = SettingsHandler.cursorMode == .direct
					&& abs(cursorContentPos.x - CGFloat(currentMouseX)) < 1
					&& abs(cursorContentPos.y - CGFloat(currentMouseY)) < 1
				cursorContentPos = CGPoint(x: CGFloat(currentMouseX), y: CGFloat(currentMouseY))
				positionCursorOverlay()
				if scrollView.zoomScale > 1.0 {
					if hostCursorMoved && !fingerSet {
						keepCursorVisible()
						positionCursorOverlay()
					}
				}
			}
		} else {
			u?.isHidden = true
		}
	}

	override func viewDidLoad() {
		// ScrollView Setup
		scrollView = UIScrollView(frame: view.bounds)
		scrollView.delegate = self
		scrollView.minimumZoomScale = 1.0
		scrollView.maximumZoomScale = 5.0
		scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		// The scroll view is a programmatically-driven zoom/pan container only. Every touch is
		// owned by touchOverlay (created below); the scroll view's own gestures are disabled so
		// they can never race with or swallow our cursor / pinch / scroll handling.
		scrollView.panGestureRecognizer.isEnabled = false
		scrollView.pinchGestureRecognizer?.isEnabled = false
		scrollView.isScrollEnabled = false
		scrollView.bouncesZoom = false
		scrollView.contentInsetAdjustmentBehavior = .never
		view.addSubview(scrollView)

        // ContentView
		contentView = UIView(frame: view.bounds)
		scrollView.addSubview(contentView)
		scrollView.contentSize = view.bounds.size

        // Initialize GLKView
		glkView.viewDidLoad()

		// Move GLKView to ContentView
		// glkView.viewDidLoad() adds the view to 'view', we need to move it.
		if let parsecGLK = glkView as? ParsecGLKViewController {
			parsecGLK.glkView.removeFromSuperview()
			contentView.addSubview(parsecGLK.glkView)
		} else {
			// Fallback if type check fails, try to find the last subview added?
			// Assumption: glkView.viewDidLoad() adds a subview.
		}

		if #available(iOS 15.0, *) {
			if SettingsHandler.enablePiP,
			   let parsecGLK = glkView as? ParsecGLKViewController,
			   let eaglContext = parsecGLK.eaglContext {
				PictureInPictureManager.shared.setup(sourceView: view, glContext: eaglContext, glkViewController: parsecGLK.glkViewController)
			}
		}

		touchController.viewDidLoad()
		gamePadController.viewDidLoad()

		// Touch overlay: a transparent sibling ON TOP of the scroll view (and above the gamepad /
		// touch controllers) that captures every raw touch and routes it deterministically
		// (1 finger = cursor, 2 fingers = pinch / scroll, 3 fingers = pan). Added before the cursor
		// image and the keyboard toolbar so those stay on top of it.
		touchOverlay = TouchOverlayView(frame: view.bounds)
		touchOverlay.backgroundColor = .clear
		touchOverlay.isMultipleTouchEnabled = true
		touchOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		touchOverlay.inputDelegate = self
		view.addSubview(touchOverlay)

		// Cursor is a screen-space overlay ON TOP of everything (not inside the scroll view), so the
		// zoom transform never scales it - keeping it crisp and a constant on-screen size.
		u = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
		u!.isUserInteractionEnabled = false
		view.addSubview(u!)

		setNeedsUpdateOfPrefersPointerLocked()

		let pointerInteraction = UIPointerInteraction(delegate: self)
		view.addInteraction(pointerInteraction)

		view.isMultipleTouchEnabled = true
		view.isUserInteractionEnabled = true

		// Continuous gestures (cursor, pinch-zoom, two-finger scroll, three-finger pan) are handled in the
		// ParsecTouchInputDelegate methods below, driven by touchOverlay's raw touches.

		// Add tap gesture recognizer for single-finger touch
		let singleFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleFingerTap(_:)))
		singleFingerTapGestureRecognizer.numberOfTouchesRequired = 1
		singleFingerTapGestureRecognizer.allowedTouchTypes = [0, 2]
		// Let the overlay see the real touch end so no phantom finger lingers.
		singleFingerTapGestureRecognizer.cancelsTouchesInView = false
		singleFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(singleFingerTapGestureRecognizer)

		// Add tap gesture recognizer for two-finger touch
		let twoFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
		twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
		twoFingerTapGestureRecognizer.allowedTouchTypes = [0]
		twoFingerTapGestureRecognizer.cancelsTouchesInView = false
		twoFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(twoFingerTapGestureRecognizer)
		//		view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
		//		view.backgroundColor = UIColor(red: 0x66, green: 0xcc, blue: 0xff, alpha: 1.0)

		let threeFingerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleThreeFinderTap(_:)))
		threeFingerTapGestureRecognizer.numberOfTouchesRequired = 3
		threeFingerTapGestureRecognizer.allowedTouchTypes = [0]
		threeFingerTapGestureRecognizer.cancelsTouchesInView = false
		threeFingerTapGestureRecognizer.delaysTouchesEnded = false
		view.addGestureRecognizer(threeFingerTapGestureRecognizer)

		let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
		longPressGestureRecognizer.numberOfTouchesRequired = 1
		longPressGestureRecognizer.allowedTouchTypes = [0, 2]
		longPressGestureRecognizer.allowableMovement = 40
		// Don't cancel the overlay's touch, so the click-hold button can be released on lift.
		longPressGestureRecognizer.cancelsTouchesInView = false
		view.addGestureRecognizer(longPressGestureRecognizer)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillChangeFrame),
			name: UIResponder.keyboardWillChangeFrameNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(inputWasReleased),
			name: NSNotification.Name("ParsecInputReleased"),
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillHide),
			name: UIResponder.keyboardWillHideNotification,
			object: nil
		)

		// Backgrounding / Control Center / system alerts can orphan touches; flush on resign.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillResignActive),
			name: UIApplication.willResignActiveNotification,
			object: nil
		)

	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		flushAllTouches()
		keyboardViewportShift = 0

		let h = size.height
		let w = size.width

		// Reset zoom on rotation
		scrollView.zoomScale = 1.0
		scrollView.contentOffset = .zero

		self.glkView.updateSize(width: w, height: h)
		contentView.frame.size = CGSize(width: w, height: h)
		scrollView.contentSize = CGSize(width: w, height: h)
		CParsec.setFrame(w, h, UIScreen.main.scale)

        // Reset accessory view to ensure correct width in new orientation
        clearToolbarModifiers(sendToHost: true)
        keyboardAccessoriesView = nil
        if keyboardVisible {
            reloadInputViews()
        }
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// glkView/contentView get sized from possibly-stale bounds in viewDidLoad and have no
		// autoresizing, so the stream renders in a corner until a rotation re-applies the size.
		// re-apply once layout settles; skip while zoomed so we dont stomp pan/zoom.
		guard scrollView != nil, scrollView.zoomScale == 1.0 else { return }
		let w = view.bounds.width
		let h = view.bounds.height
		guard w > 0, h > 0, w != lastLaidOutWidth || h != lastLaidOutHeight else { return }
		lastLaidOutWidth = w
		lastLaidOutHeight = h
		glkView.updateSize(width: w, height: h)
		contentView.frame.size = CGSize(width: w, height: h)
		scrollView.contentSize = CGSize(width: w, height: h)
		CParsec.setFrame(w, h, UIScreen.main.scale)
		if !keyboardFrameInScreen.isNull { updateKeyboardViewport() }
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		UIApplication.shared.isIdleTimerDisabled = true
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(self)
			parent.setChildViewControllerForPointerLock(self)
		}
		if keyboardVisible {
			becomeFirstResponder()
		}
		// (Pinch-to-zoom is driven manually via touchOverlay; the scroll view's pinch stays off.)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		UIApplication.shared.isIdleTimerDisabled = false
		flushAllTouches()
		if let parent = parent {
			parent.setChildForHomeIndicatorAutoHidden(nil)
			parent.setChildViewControllerForPointerLock(nil)
		}
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
		NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
	}
	
	
	private var repeatTimer: Timer?
	private var repeatKeyCode: Int = -1
	private var optCmdRemapActive = false
	private var altKeyHeld = false

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = true
			}

			if SettingsHandler.optionAsCommand && !isModifierKey(key.keyCode) && (altKeyHeld || key.modifierFlags.contains(.alternate)) {
				if !optCmdRemapActive {
					CParsec.sendKeyboardMessage(keyCode: 226, pressed: false)
					CParsec.sendKeyboardMessage(keyCode: 230, pressed: false)
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: true)
					optCmdRemapActive = true
				}
				let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
				CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: true)
				startKeyRepeat(keyCode: code)
				continue
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: true))

			if !isModifierKey(key.keyCode) {
				startKeyRepeat(keyCode: KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode))
			}
		}
	}

	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			guard let key = press.key else { continue }

			if optCmdRemapActive {
				if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
					altKeyHeld = false
					CParsec.sendKeyboardMessage(keyCode: 227, pressed: false)
					optCmdRemapActive = false
					continue
				}
				if !isModifierKey(key.keyCode) {
					let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
					CParsec.sendKeyboardMessage(keyCode: UInt32(code), pressed: false)
					if code == repeatKeyCode { stopKeyRepeat() }
					continue
				}
			}

			if key.keyCode == .keyboardLeftAlt || key.keyCode == .keyboardRightAlt {
				altKeyHeld = false
			}

			CParsec.sendKeyboardMessage(event:KeyBoardKeyEvent(input: press.key, isPressBegin: false))

			let code = KeyCodeTranslators.uiKeyCodeToInt(key: key.keyCode)
			if code == repeatKeyCode {
				stopKeyRepeat()
			}
		}
	}

	override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		// iOS sends this instead of pressesEnded when a press is interrupted (e.g. backgrounding
		// mid-hold) — without cleanup the host keeps keys held (stuck paste, stuck modifier).
		CParsec.sendReleaseMessage()
		resetKeyState()
	}

	private func startKeyRepeat(keyCode: Int) {
		stopKeyRepeat()
		repeatKeyCode = keyCode

		repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
			guard let self = self else { return }
			self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
				guard let self = self else { return }
				CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: false)
				CParsec.sendKeyboardMessage(keyCode: UInt32(self.repeatKeyCode), pressed: true)
			}
		}
	}

	private func stopKeyRepeat() {
		repeatTimer?.invalidate()
		repeatTimer = nil
		repeatKeyCode = -1
	}

	func resetKeyState() {
		stopKeyRepeat()
		optCmdRemapActive = false
		altKeyHeld = false
	}

	private func isModifierKey(_ keyCode: UIKeyboardHIDUsage) -> Bool {
		switch keyCode {
		case .keyboardLeftControl, .keyboardLeftShift, .keyboardLeftAlt, .keyboardLeftGUI,
			 .keyboardRightControl, .keyboardRightShift, .keyboardRightAlt, .keyboardRightGUI,
			 .keyboardCapsLock:
			return true
		default:
			return false
		}
	}

	@objc func keyboardWillChangeFrame(notification: NSNotification) {
		guard let window = viewIfLoaded?.window,
			  let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
		if let screen = notification.object as? UIScreen, screen != window.screen { return }
		cancelAutoKeyboard()
		keyboardFrameInScreen = frame
		updateKeyboardViewport(notification: notification)
		onKeyboardVisibilityChanged?(keyboardVisible)
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		cancelAutoKeyboard()
		keyboardFrameInScreen = .null
		updateKeyboardViewport(notification: notification)
		onKeyboardVisibilityChanged?(false)
	}

	private func updateKeyboardViewport(notification: NSNotification? = nil) {
		guard let window = viewIfLoaded?.window, scrollView != nil else { return }
		let keyboard: CGRect
		if keyboardFrameInScreen.isNull {
			keyboard = .null
		} else {
			let frameInWindow = window.convert(keyboardFrameInScreen, from: window.screen.coordinateSpace)
			keyboard = view.convert(frameInWindow, from: window)
		}
		let intersection = view.bounds.intersection(keyboard)
		keyboardVisible = !intersection.isNull && !intersection.isEmpty
		let layout = KeyboardViewport.avoiding(keyboard, viewportSize: view.bounds.size,
			contentSize: contentView.bounds.size,
			streamSize: CGSize(width: CGFloat(CParsec.hostWidth), height: CGFloat(CParsec.hostHeight)),
			zoom: scrollView.zoomScale, offset: scrollView.contentOffset,
			previousShift: keyboardViewportShift, tapPoint: lastTapContentPoint)
		keyboardHeight = layout.coveredBottom
		keyboardViewportShift = layout.shift
		let changes = {
			self.scrollView.contentInset.bottom = layout.bottomInset
			self.scrollView.setContentOffset(layout.offset, animated: false)
			self.positionCursorOverlay()
		}
		let duration = (notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
		let curve = (notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
		guard duration > 0 else { changes(); return }
		UIView.animate(withDuration: duration, delay: 0,
			options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction],
			animations: changes)
	}

}

extension ParsecViewController: UIGestureRecognizerDelegate {

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
	}

	// MARK: - Manual touch handling (ParsecTouchInputDelegate)
	// touchOverlay delivers raw touches here. One finger drives the mouse cursor; two fingers are
	// classified once per gesture into either pinch-zoom or host scroll-wheel (never both), so the
	// gestures never fight. No UIScrollView gesture recognizer is in the loop.

	func parsecTouchesUpdated(_ touches: Set<UITouch>, moved: Bool) {
		let oldCount = activeTouches.count
		let oldTouches = activeTouches
		// Rebuild from the event each time (keeping order) so a cancelled touch can't leave a stale one.
		var ordered = activeTouches.filter { touches.contains($0) }
		for t in touches where !ordered.contains(t) {
			ordered.append(t)
		}
		activeTouches = ordered
		if activeTouches.count != oldCount {
			handleTouchCountChange(old: oldCount, new: activeTouches.count)
		} else if activeTouches.count == 2 && oldTouches != activeTouches {
			beginTwoFinger()
		} else if activeTouches.count == 3 && oldTouches != activeTouches {
			beginThreeFinger()
		}
		if moved { handleActiveTouchesMoved() }
	}

	func parsecTouchesCancelled() {
		flushAllTouches()
		cursorDidMoveThisTouch = true
		twoFingerDidMove = true
	}

	private func handleTouchCountChange(old: Int, new: Int) {
		edgeScrollActive = false
		threeFingerGesture = nil
		if old == 0 { threeFingerDidMove = false }
		if new > 3 { threeFingerDidMove = true }
		if new > old {
			stopMomentum()   // any new finger cancels an in-progress glide
			cancelAutoKeyboard()
		}
		if new == 0 {
			let flingCursor = (old == 1) && isDragging && !twoFingerResidual && !clickHoldActive
			let flingScroll = (old == 2) && (twoFingerGesture?.mode == .scroll)
			releaseClickHoldIfNeeded()   // defensive: the left button must never stay stuck down
			endCursorIfNeeded()
			isDragging = false
			twoFingerResidual = false
			twoFingerGesture = nil
			if flingCursor { startCursorMomentum() }
			if flingScroll { startScrollMomentum() }
		} else if new == 1 {
			if old >= 2 {
				// Leftover finger after a two-finger gesture: stay inert until full lift so it
				// doesn't jump the cursor.
				if twoFingerGesture?.mode == .scroll { startScrollMomentum() }
				twoFingerResidual = true
				twoFingerGesture = nil
			} else if old == 0 {
				startCursor()
			}
		} else if new >= 2 {
			releaseClickHoldIfNeeded()   // can't keep the button held during a two-finger gesture
			endCursorIfNeeded()
			isDragging = false
			cursorDidMoveThisTouch = true
			if new == 2 && old < 2 {
				beginTwoFinger()
			} else {
				twoFingerGesture = nil
				twoFingerDidMove = true
				if new == 3 { beginThreeFinger() }
			}
		}
	}

	private func releaseClickHoldIfNeeded() {
		if clickHoldActive {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false)
			clickHoldActive = false
		}
	}

	@objc private func appWillResignActive() { flushAllTouches() }

	// Drop all touch state and release any held button so nothing sticks when backgrounded.
	private func flushAllTouches() {
		cancelAutoKeyboard()
		lastTapContentPoint = nil
		stopMomentum()
		releaseClickHoldIfNeeded()
		endCursorIfNeeded()
		isDragging = false
		twoFingerResidual = false
		twoFingerGesture = nil
		threeFingerGesture = nil
		threeFingerDidMove = true
		activeTouches = []
	}

	private func startCursor() {
		isDragging = true
		twoFingerResidual = false
		cursorDidMoveThisTouch = false
		twoFingerDidMove = false
		directTouchWasPressed = false
		singleTouchStartScreen = activeTouches.first?.location(in: view) ?? .zero
		if SettingsHandler.cursorMode == .direct {
			// Give the second finger time to land before a direct touch presses the host mouse.
			let press = DispatchWorkItem { [weak self] in self?.beginDirectPress() }
			pendingDirectPress = press
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: press)
		}
	}

	private func beginDirectPress() {
		pendingDirectPress?.cancel()
		pendingDirectPress = nil
		guard isDragging, activeTouches.count == 1, !directPressActive,
			  let touch = activeTouches.first else { return }
		cursorContentPos = clampToContent(contentView.convert(touch.location(in: view), from: view))
		CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
		CParsec.sendMouseClickMessage(ParsecMouseButton(rawValue: 1), true)
		directPressActive = true
		directTouchWasPressed = true
		positionCursorOverlay()
	}

	private func endCursorIfNeeded() {
		pendingDirectPress?.cancel()
		pendingDirectPress = nil
		if directPressActive {
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), false)
			directPressActive = false
		}
	}

	private func beginTwoFinger() {
		guard activeTouches.count == 2 else { return }
		twoFingerResidual = false
		twoFingerDidMove = false
		accumulatedScrollY = 0.0
		twoFingerGesture = TwoFingerGesture(first: activeTouches[0].location(in: view),
										  second: activeTouches[1].location(in: view))
	}

	private func beginThreeFinger() {
		guard activeTouches.count == 3 else { return }
		threeFingerGesture = ThreeFingerPanGesture(first: activeTouches[0].location(in: view),
			second: activeTouches[1].location(in: view), third: activeTouches[2].location(in: view))
	}

	private func handleActiveTouchesMoved() {
		if (isDragging || clickHoldActive), !twoFingerResidual, activeTouches.count == 1, let t = activeTouches.first {
			moveCursor(with: t)
		} else if activeTouches.count == 2 {
			handleTwoFinger()
		} else if activeTouches.count == 3 {
			handleThreeFinger()
		}
	}

	private func handleThreeFinger() {
		guard let update = threeFingerGesture?.update(first: activeTouches[0].location(in: view),
			second: activeTouches[1].location(in: view), third: activeTouches[2].location(in: view)) else { return }
		threeFingerDidMove = true
		applyViewportChange(scaleFactor: 1, from: update.previousMidpoint, to: update.midpoint)
	}

	private func moveCursor(with t: UITouch) {
		let zoom = scrollView.zoomScale
		let loc = t.location(in: view)
		let prev = t.previousLocation(in: view)
		if hypot(loc.x - singleTouchStartScreen.x, loc.y - singleTouchStartScreen.y) > tapMoveSlop {
			cursorDidMoveThisTouch = true
			lastTapContentPoint = nil
		}
		if SettingsHandler.cursorMode == .direct && !directPressActive {
			guard cursorDidMoveThisTouch else { return }
			beginDirectPress()
		} else if SettingsHandler.cursorMode == .touchpad {
			prepareTouchpadCursor()
		}

		if CParsec.mouseInfo.mousePositionRelative {
			// Host has captured the pointer (e.g. a game): send true relative motion instead.
			let s = CGFloat(mouseSensitivity) / zoom
			CParsec.sendMouseDelta(Int32((loc.x - prev.x) * s), Int32((loc.y - prev.y) * s))
			return
		}

		if SettingsHandler.cursorMode == .direct {
			cursorContentPos = clampToContent(contentView.convert(loc, from: view))
		} else {
			// Relative finger movement, predicted locally; sensitivity scales down with zoom so the
			// cursor tracks the visible finger.
			let s = CGFloat(mouseSensitivity) / zoom
			let dcx = (loc.x - prev.x) * s
			let dcy = (loc.y - prev.y) * s
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + dcx, y: cursorContentPos.y + dcy))
			// Smoothed velocity so a quick flick keeps gliding after the finger lifts.
			let now = CACurrentMediaTime()
			let dt = CGFloat(now - lastCursorMoveTime)
			if dt > 0.0005 && dt < 0.1 {
				cursorVelocity = CGPoint(x: cursorVelocity.x * 0.4 + (dcx / dt) * 0.6,
										 y: cursorVelocity.y * 0.4 + (dcy / dt) * 0.6)
			}
			lastCursorMoveTime = now
		}
		// Command the host to the ABSOLUTE predicted position (not a delta) so the host cursor can't
		// crawl behind network round-trips - clicks always land where the cursor is drawn.
		CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
		if SettingsHandler.cursorMode == .direct {
			edgeScrollPoint = loc
			if cursorDidMoveThisTouch && edgeScrollVelocity(at: loc) != .zero {
				if !edgeScrollActive { edgeScrollLastTick = 0 }
				edgeScrollActive = true
				ensureMomentumLink()
			}
		} else {
			keepCursorVisible()
		}
		positionCursorOverlay()
	}

	private func handleTwoFinger() {
		guard let update = twoFingerGesture?.update(first: activeTouches[0].location(in: view),
													second: activeTouches[1].location(in: view)) else { return }
		if update.mode != .undecided { twoFingerDidMove = true }
		switch update.mode {
		case .zoom:
			applyViewportChange(scaleFactor: update.scaleFactor, from: update.previousMidpoint, to: update.midpoint)
		case .scroll:
			lastTapContentPoint = nil
			let deltaY = Float(update.midpoint.y - update.previousMidpoint.y)
			let direction: Float = SettingsHandler.reverseScrollDirection ? -1.0 : 1.0
			let contribution = deltaY * scrollWheelSpeed * direction
			accumulatedScrollY += contribution
			let intScrollY = Int32(accumulatedScrollY)
			if intScrollY != 0 {
				CParsec.sendWheelMsg(x: 0, y: intScrollY)
				accumulatedScrollY -= Float(intScrollY)
			}
			// Track scroll velocity for a little post-flick momentum.
			let snow = CACurrentMediaTime()
			let sdt = Float(snow - lastScrollMoveTime)
			if sdt > 0.0005 && sdt < 0.1 {
				scrollVelocity = scrollVelocity * 0.4 + (contribution / sdt) * 0.6
			}
			lastScrollMoveTime = snow
		case .undecided:
			break
		}
	}

	private func startCursorMomentum() {
		guard SettingsHandler.cursorMode == .touchpad, !CParsec.mouseInfo.mousePositionRelative else { return }
		guard CACurrentMediaTime() - lastCursorMoveTime < 0.06 else { return }   // finger was still moving at release
		guard hypot(cursorVelocity.x, cursorVelocity.y) > flingMinSpeed else { return }
		// Less glide when zoomed out: at 1x the cursor crosses the screen instead of panning the view.
		let glideScale = min(1.0, 0.3 + 0.7 * (scrollView.zoomScale - 1.0))
		cursorVelocity.x *= glideScale
		cursorVelocity.y *= glideScale
		cursorMomentumActive = true
		ensureMomentumLink()
	}

	private func startScrollMomentum() {
		guard CACurrentMediaTime() - lastScrollMoveTime < 0.06 else { return }
		guard abs(scrollVelocity) > scrollStartSpeed else { return }
		scrollMomentumActive = true
		ensureMomentumLink()
	}

	private func ensureMomentumLink() {
		if momentumLink == nil {
			let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
			link.add(to: .main, forMode: .common)
			momentumLink = link
		}
	}

	func stopMomentum() {
		cursorMomentumActive = false
		scrollMomentumActive = false
		edgeScrollActive = false
		cursorVelocity = .zero
		scrollVelocity = 0
		momentumLink?.invalidate()
		momentumLink = nil
	}

	@objc func momentumTick(_ link: CADisplayLink) {
		let dt = CGFloat(link.targetTimestamp - link.timestamp)
		if dt <= 0 { return }
		var stillActive = false

		if cursorMomentumActive {
			let decay = CGFloat(pow(cursorDecayPerSec, Double(dt)))
			cursorVelocity.x *= decay
			cursorVelocity.y *= decay
			let before = cursorContentPos
			cursorContentPos = clampToContent(CGPoint(x: cursorContentPos.x + cursorVelocity.x * dt,
													  y: cursorContentPos.y + cursorVelocity.y * dt))
			if !CParsec.mouseInfo.mousePositionRelative {
				CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
			}
			keepCursorVisible()
			positionCursorOverlay()
			let stalled = abs(cursorContentPos.x - before.x) < 0.05 && abs(cursorContentPos.y - before.y) < 0.05
			if hypot(cursorVelocity.x, cursorVelocity.y) < cursorStopSpeed || stalled {
				cursorMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if scrollMomentumActive {
			scrollVelocity *= Float(pow(scrollDecayPerSec, Double(dt)))
			accumulatedScrollY += scrollVelocity * Float(dt)
			let i = Int32(accumulatedScrollY)
			if i != 0 {
				CParsec.sendWheelMsg(x: 0, y: i)
				accumulatedScrollY -= Float(i)
			}
			if abs(scrollVelocity) < scrollStopSpeed {
				scrollMomentumActive = false
			} else {
				stillActive = true
			}
		}

		if edgeScrollActive {
			let elapsed = edgeScrollLastTick > 0 ? min(CGFloat(link.timestamp - edgeScrollLastTick), 0.1) : dt
			edgeScrollLastTick = link.timestamp
			if stepEdgeScroll(elapsed) {
				stillActive = true
			} else {
				edgeScrollActive = false
			}
		}

		if !stillActive { stopMomentum() }
	}

	private func applyViewportChange(scaleFactor: CGFloat, from previousAnchor: CGPoint, to anchor: CGPoint) {
		// A user-chosen viewport should survive keyboard dismissal.
		keyboardViewportShift = 0
		let viewport = ZoomViewport(scale: scrollView.zoomScale, offset: scrollView.contentOffset)
		let next = viewport.pinching(by: scaleFactor, from: previousAnchor, to: anchor,
			contentSize: contentView.bounds.size, viewportSize: scrollView.bounds.size,
			bottomInset: scrollView.contentInset.bottom,
			scaleRange: scrollView.minimumZoomScale...scrollView.maximumZoomScale)
		scrollView.zoomScale = next.scale
		scrollView.setContentOffset(next.offset, animated: false)
		positionCursorOverlay()
	}

	@discardableResult
	private func prepareTouchpadCursor() -> Bool {
		guard scrollView.zoomScale > 1, !CParsec.mouseInfo.mousePositionRelative else { return false }
		let visible = CGRect(x: 0, y: 0, width: view.bounds.width,
							 height: max(1, view.bounds.height - scrollView.contentInset.bottom))
		let visibleContent = contentView.convert(visible, from: view)
		guard !visibleContent.contains(cursorContentPos) else { return false }
		// A pinch can leave the cursor offscreen. Reposition it only when mouse input resumes.
		cursorContentPos = clampToContent(CGPoint(x: visibleContent.midX, y: visibleContent.midY))
		return true
	}

	private func clampToContent(_ p: CGPoint) -> CGPoint {
		let w = view.bounds.width
		let h = view.bounds.height
		return CGPoint(x: min(max(0, p.x), w), y: min(max(0, p.y), h))
	}

	// Places the cursor overlay at the cursor's content position projected into screen space,
	// drawn at full Cursor Scale (no zoom division) so it stays crisp and constant-sized.
	func positionCursorOverlay() {
		guard let u = u else { return }
		let zoom = scrollView.zoomScale
		let off = scrollView.contentOffset
		let screenX = cursorContentPos.x * zoom - off.x
		let screenY = cursorContentPos.y * zoom - off.y
		let cs = CGFloat(SettingsHandler.cursorScale)
		let hotX = CGFloat(CParsec.mouseInfo.cursorHotX) * cs
		let hotY = CGFloat(CParsec.mouseInfo.cursorHotY) * cs
		let w = CGFloat(CParsec.mouseInfo.cursorWidth) * cs
		let h = CGFloat(CParsec.mouseInfo.cursorHeight) * cs
		u.frame = CGRect(x: screenX - hotX, y: screenY - hotY, width: w, height: h)
	}

	@objc func handleSingleFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		// Only click if the finger stayed put; a moved finger was a cursor nudge, not a tap.
		if cursorDidMoveThisTouch { return }
		if SettingsHandler.cursorMode == .direct && directTouchWasPressed {
			lastTapContentPoint = CParsec.mouseInfo.mousePositionRelative ? nil : cursorContentPos
			requestAutoKeyboard()
			return
		}
		let location = gestureRecognizer.location(in: gestureRecognizer.view)
		if SettingsHandler.cursorMode == .touchpad && prepareTouchpadCursor() {
			CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
			positionCursorOverlay()
		}
		tapMouse(button: 1, at: location)
		lastTapContentPoint = CParsec.mouseInfo.mousePositionRelative ? nil : cursorContentPos
		requestAutoKeyboard()
	}

	@objc func handleTwoFingerTap(_ gestureRecognizer: UITapGestureRecognizer) {
		// A two-finger TAP is a right click; if the fingers moved (pinch/scroll) it wasn't a tap.
		if twoFingerDidMove { return }
		// dont leak a right-click to the host while backgrounding (app switch) or after a disconnect
		guard UIApplication.shared.applicationState == .active,
			  ParsecBackgroundManager.shared.hasActiveConnection else { return }

		let location: CGPoint
		switch SettingsHandler.rightClickPosition {
		case .firstFinger:
			location = gestureRecognizer.location(ofTouch: 0, in: gestureRecognizer.view)
			case .secondFinger:
			location = gestureRecognizer.location(ofTouch: 1, in: gestureRecognizer.view)
		default:
			location = gestureRecognizer.location(in: gestureRecognizer.view)
		}

		tapMouse(button: 3, at: location)
		lastTapContentPoint = nil
	}

	private func tapMouse(button: Int, at location: CGPoint) {
		let contentLocation = clampToContent(contentView.convert(location, from: view))
		if SettingsHandler.cursorMode == .direct {
			// Match the click locally so the host's cursor echo doesn't pan the zoomed view.
			cursorContentPos = contentLocation
			positionCursorOverlay()
		}
		touchController.onTap(typeOfTap: button, location: contentLocation)
	}

	@objc func handleThreeFinderTap(_ gestureRecognizer: UITapGestureRecognizer) {
		guard !threeFingerDidMove else { return }
		showKeyboard()
	}

	@objc func handleLongPress(_ gestureRecognizer: UIGestureRecognizer) {
		if SettingsHandler.cursorMode != .touchpad {
			return
		}
		switch gestureRecognizer.state {
		case .began:
			guard activeTouches.count == 1, !twoFingerResidual else { return }
			// Click-and-hold (file drag): hold the left button; the overlay keeps moving the cursor.
			clickHoldActive = true
			CParsec.sendMouseClickMessage(ParsecMouseButton.init(rawValue: 1), true)
		case .ended, .cancelled, .failed:
			releaseClickHoldIfNeeded()
		default:
			break
		}
	}

    // UIScrollViewDelegate
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return contentView
	}

	// Pan only near the edges so mouse movement preserves the region chosen by a pinch.
	func keepCursorVisible() {
		guard scrollView.zoomScale > 1.0 else { return }
		let zoom = scrollView.zoomScale
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let visibleWidth = view.bounds.width
		let visibleHeight = view.bounds.height - bottomInset
		let cursorX = cursorContentPos.x * zoom
		let cursorY = cursorContentPos.y * zoom
		let marginX = min(44, visibleWidth / 4)
		let marginY = min(44, visibleHeight / 4)
		var targetX = scrollView.contentOffset.x
		var targetY = scrollView.contentOffset.y
		targetX = min(max(targetX, cursorX - visibleWidth + marginX), cursorX - marginX)
		targetY = min(max(targetY, cursorY - visibleHeight + marginY), cursorY - marginY)
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
		targetX = min(max(0, targetX), maxX)
		targetY = min(max(0, targetY), maxY)
		if abs(targetY - scrollView.contentOffset.y) > 0.01 { keyboardViewportShift = 0 }
		scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
	}

	private func edgeScrollVelocity(at p: CGPoint) -> CGPoint {
		guard scrollView.zoomScale > 1.0 else { return .zero }
		let visibleHeight = view.bounds.height - (keyboardVisible ? keyboardHeight : 0.0)
		func axis(_ v: CGFloat, _ length: CGFloat) -> CGFloat {
			if v < edgeScrollMargin {
				return -min(1, (edgeScrollMargin - v) / edgeScrollMargin) * edgeScrollMaxSpeed
			}
			if v > length - edgeScrollMargin {
				return min(1, (v - (length - edgeScrollMargin)) / edgeScrollMargin) * edgeScrollMaxSpeed
			}
			return 0
		}
		return CGPoint(x: axis(p.x, view.bounds.width), y: axis(p.y, visibleHeight))
	}

	private func stepEdgeScroll(_ dt: CGFloat) -> Bool {
		let v = edgeScrollVelocity(at: edgeScrollPoint)
		guard v != .zero, !CParsec.mouseInfo.mousePositionRelative else { return false }
		let bottomInset = keyboardVisible ? keyboardHeight : 0.0
		let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
		let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + bottomInset)
		let off = scrollView.contentOffset
		let next = CGPoint(x: min(max(0, off.x + v.x * dt), maxX), y: min(max(0, off.y + v.y * dt), maxY))
		guard next != off else { return false }
		keyboardViewportShift = 0
		scrollView.setContentOffset(next, animated: false)
		cursorContentPos = clampToContent(contentView.convert(edgeScrollPoint, from: view))
		CParsec.sendMousePosition(Int32(cursorContentPos.x), Int32(cursorContentPos.y))
		positionCursorOverlay()
		return true
	}

	func setCursorMode(_ mode: CursorMode) {
		guard SettingsHandler.cursorMode != mode else { return }
		flushAllTouches()
		cursorDidMoveThisTouch = true
		twoFingerDidMove = true
		SettingsHandler.cursorMode = mode
	}

	func setAutoKeyboardEnabled(_ enabled: Bool) {
		cancelAutoKeyboard()
		SettingsHandler.autoKeyboard = enabled
	}

	private func requestAutoKeyboard() {
		cancelAutoKeyboard()
		guard SettingsHandler.autoKeyboard, !keyboardVisible else { return }
		autoKeyboardTrigger.arm(at: CACurrentMediaTime())
		let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self else { timer.invalidate(); return }
			self.checkAutoKeyboard()
		}
		autoKeyboardTimer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	private func checkAutoKeyboard() {
		guard SettingsHandler.autoKeyboard, !keyboardVisible, activeTouches.isEmpty,
			  viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active,
			  ParsecBackgroundManager.shared.hasActiveConnection,
			  !ParsecBackgroundManager.shared.isMarkedForReconnect else {
			cancelAutoKeyboard()
			return
		}
		let mouse = CParsec.mouseInfo
		let textCursor = !mouse.cursorHidden && !mouse.mousePositionRelative &&
			mouse.cursorImg.map { TextCursorDetector.matches($0,
				hotspot: CGPoint(x: mouse.cursorHotX, y: mouse.cursorHotY)) } == true
		if autoKeyboardTrigger.shouldOpen(at: CACurrentMediaTime(), textCursor: textCursor) {
			cancelAutoKeyboard()
			setKeyboardVisible(true)
		} else if !autoKeyboardTrigger.isPending {
			cancelAutoKeyboard()
		}
	}

	private func cancelAutoKeyboard() {
		autoKeyboardTimer?.invalidate()
		autoKeyboardTimer = nil
		autoKeyboardTrigger.cancel()
	}

	func resetZoom() {
		flushAllTouches()
		keyboardViewportShift = 0
		UIView.animate(withDuration: 0.25, animations: {
			self.scrollView.zoomScale = 1.0
			self.scrollView.contentOffset = .zero
			if self.keyboardVisible { self.updateKeyboardViewport() }
		}, completion: { _ in
			self.positionCursorOverlay()
		})
	}

}

extension ParsecViewController: UIPointerInteractionDelegate {
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
		return UIPointerStyle.hidden()
	}

	func pointerInteraction(_ inter: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
		let loc = request.location
		if let iv = view!.hitTest(loc, with: nil) {
			let rect = view!.convert(iv.bounds, from: iv)
			let region = UIPointerRegion(rect: rect, identifier: iv.tag)
			return region
		}
		return nil
	}

}

class KeyboardButton: UIButton {
	let keyText: String
	let isToggleable: Bool
	var isOn = false

	required init(keyText: String, isToggleable: Bool) {
		self.keyText = keyText
		self.isToggleable = isToggleable
		super.init(frame: .zero)
		addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
		addTarget(self, action: #selector(handleTouchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])

	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// Add a press-down animation for feedback
	@objc private func handleTouchDown() {
		self.alpha = 0.5
	}

	// Restore to normal state when touch ends
	@objc private func handleTouchUp() {
		UIView.animate(withDuration: 0.2) {
			self.alpha = 1.0
		}
	}
}

// MARK: - Virtual Keyboard
extension ParsecViewController: UIKeyInput, UITextInputTraits {
	var hasText: Bool {
		return true
	}

	var keyboardType: UIKeyboardType {
		get {
			return .asciiCapable
		}
		set {

		}
	}

	// passthrough keyboard: send raw input, dont let iOS autocorrect / smart-substitute / inject text
	var autocorrectionType: UITextAutocorrectionType {
		get { .no }
		set { }
	}
	var spellCheckingType: UITextSpellCheckingType {
		get { .no }
		set { }
	}
	var smartQuotesType: UITextSmartQuotesType {
		get { .no }
		set { }
	}
	var smartDashesType: UITextSmartDashesType {
		get { .no }
		set { }
	}
	var smartInsertDeleteType: UITextSmartInsertDeleteType {
		get { .no }
		set { }
	}
	var autocapitalizationType: UITextAutocapitalizationType {
		get { .none }
		set { }
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	func insertText(_ text: String) {
		CParsec.sendVirtualKeyboardInput(text: text)
	}

	func deleteBackward() {
		CParsec.sendVirtualKeyboardInput(text: "BACKSPACE")
	}

    // copied from moonlight https://github.com/moonlight-stream/moonlight-ios/blob/022352c1667788d8626b659d984a290aa5c25e17/Limelight/Input/StreamView.m#L393
	override var inputAccessoryView: UIView? {

		if let keyboardAccessoriesView {
			return keyboardAccessoriesView
		}
        // Refactored to UIView with autoresizing mask for better landscape support
        // Using frame-based layout for the container to avoid constraint conflicts with keyboard
		let containerView = UIView(frame: CGRect(x: 0, y: 0, width: self.view.bounds.width, height: 94))
        containerView.autoresizingMask = [.flexibleWidth]
        containerView.backgroundColor = .clear

		// Use a simple UIView instead of UIToolbar to avoid constraint conflicts
		let toolbarBackground = UIView(frame: CGRect(x: 0, y: 50, width: containerView.bounds.width, height: 44))
		toolbarBackground.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
		toolbarBackground.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)

		let scrollView = UIScrollView(frame: CGRect(x: 8, y: 0, width: toolbarBackground.bounds.width - 80, height: 44))
		scrollView.autoresizingMask = [.flexibleWidth]
		scrollView.showsHorizontalScrollIndicator = false

		let buttonStackView = UIStackView()
		buttonStackView.axis = .horizontal
		buttonStackView.distribution = .equalSpacing
		buttonStackView.alignment = .center
		buttonStackView.spacing = 8
		buttonStackView.translatesAutoresizingMaskIntoConstraints = false

		let shiftBarButton = createKeyboardButton(displayText: "⇧", keyText: "SHIFT", isToggleable: true)
		let windowsBarButton = createKeyboardButton(displayText: "⌘", keyText: "LGUI", isToggleable: true)
		let tabBarButton = createKeyboardButton(displayText: "⇥", keyText: "TAB", isToggleable: false)
		let escapeBarButton = createKeyboardButton(displayText: "⎋", keyText: "UIKeyInputEscape", isToggleable: false)
		let controlBarButton = createKeyboardButton(displayText: "⌃", keyText: "CONTROL", isToggleable: true)
		let altBarButton = createKeyboardButton(displayText: "⌥", keyText: "LALT", isToggleable: true)
		let deleteBarButton = createKeyboardButton(displayText: "Del", keyText: "DELETE", isToggleable: false)
		let f1Button = createKeyboardButton(displayText: "F1", keyText: "F1", isToggleable: false)
		let f2Button = createKeyboardButton(displayText: "F2", keyText: "F2", isToggleable: false)
		let f3Button = createKeyboardButton(displayText: "F3", keyText: "F3", isToggleable: false)
		let f4Button = createKeyboardButton(displayText: "F4", keyText: "F4", isToggleable: false)
		let f5Button = createKeyboardButton(displayText: "F5", keyText: "F5", isToggleable: false)
		let f6Button = createKeyboardButton(displayText: "F6", keyText: "F6", isToggleable: false)
		let f7Button = createKeyboardButton(displayText: "F7", keyText: "F7", isToggleable: false)
		let f8Button = createKeyboardButton(displayText: "F8", keyText: "F8", isToggleable: false)
		let f9Button = createKeyboardButton(displayText: "F9", keyText: "F9", isToggleable: false)
		let f10Button = createKeyboardButton(displayText: "F10", keyText: "F10", isToggleable: false)
		let f11Button = createKeyboardButton(displayText: "F11", keyText: "F11", isToggleable: false)
		let f12Button = createKeyboardButton(displayText: "F12", keyText: "F12", isToggleable: false)
		let upButton = createKeyboardButton(displayText: "↑", keyText: "UP", isToggleable: false)
		let downButton = createKeyboardButton(displayText: "↓", keyText: "DOWN", isToggleable: false)
		let leftButton = createKeyboardButton(displayText: "←", keyText: "LEFT", isToggleable: false)
		let rightButton = createKeyboardButton(displayText: "→", keyText: "RIGHT", isToggleable: false)

		let buttons = [tabBarButton, shiftBarButton, controlBarButton, altBarButton, windowsBarButton, escapeBarButton, f1Button, f2Button, f3Button, f4Button, f5Button, f6Button, f7Button, f8Button, f9Button, f10Button, f11Button, f12Button, deleteBarButton, upButton, downButton, leftButton, rightButton]

		for button in buttons {
			buttonStackView.addArrangedSubview(button)
		}

		scrollView.addSubview(buttonStackView)

		// Set constraints for the stack view inside the scroll view
		NSLayoutConstraint.activate([
			buttonStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			buttonStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			buttonStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			buttonStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			buttonStackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
		])

		// Done button with frame-based layout
		let doneButton = UIButton(type: .system)
		doneButton.frame = CGRect(x: toolbarBackground.bounds.width - 70, y: 0, width: 60, height: 44)
		doneButton.autoresizingMask = [.flexibleLeftMargin]
		doneButton.setTitle("Done", for: .normal)
		doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

		toolbarBackground.addSubview(scrollView)
		toolbarBackground.addSubview(doneButton)

		containerView.addSubview(toolbarBackground)

		keyboardAccessoriesView = containerView
		return containerView
	}

	func createKeyboardButton(displayText: String, keyText: String, isToggleable: Bool) -> UIButton {
		let button = KeyboardButton(keyText: keyText, isToggleable: isToggleable)

		// Set the image and button properties
		button.setTitle(displayText, for: .normal)
		button.titleLabel?.font = .systemFont(ofSize: 10)
		button.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
		button.titleLabel?.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
		if let label = button.titleLabel {
			label.textAlignment = .center
		}
		button.backgroundColor = .black
		button.layer.cornerRadius = 3.0

		button.titleLabel?.contentMode = .scaleAspectFit

		// Set target and action for button
		button.addTarget(self, action: #selector(toolbarButtonClicked(_:)), for: .touchUpInside)

		return button
	}

	@objc private func inputWasReleased() {
		cancelAutoKeyboard()
		clearToolbarModifiers(sendToHost: false)
	}

	private func clearToolbarModifiers(sendToHost: Bool) {
		guard let bar = keyboardAccessoriesView else { return }
		for button in toolbarButtons(in: bar) where button.isOn {
			button.isOn = false
			button.backgroundColor = .black
			if sendToHost {
				CParsec.sendVirtualKeyboardInput(text: button.keyText, isOn: false)
			}
		}
	}

	private func toolbarButtons(in view: UIView) -> [KeyboardButton] {
		let own = (view as? KeyboardButton).map { [$0] } ?? []
		return own + view.subviews.flatMap { toolbarButtons(in: $0) }
	}

	@objc func toolbarButtonClicked(_ sender: KeyboardButton) {
		let isToggleable = sender.isToggleable
		var isOn = sender.isOn

		if isToggleable {
			isOn.toggle()
			if isOn {
				sender.backgroundColor = .lightGray
			} else {
				sender.backgroundColor = .black
			}
		}

		sender.isOn = isOn
		let keyText = sender.keyText

		if isToggleable {
			if isOn {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: true)
			} else {
				CParsec.sendVirtualKeyboardInput(text: keyText, isOn: false)
			}
		} else {
			CParsec.sendVirtualKeyboardInput(text: keyText)
		}

	}

	@objc func doneTapped() {
		cancelAutoKeyboard()
		// Resign first responder to dismiss the keyboard
		resignFirstResponder()
	}

	@objc func showKeyboard() {
		cancelAutoKeyboard()
		becomeFirstResponder()
	}

	// CRITICAL: This is the robust way to show the keyboard.
    // 1. Dispatch async to ensure view is attached to window.
    // 2. call reloadInputViews() to ensure updated accessory view (especially for rotation).
    // 3. call becomeFirstResponder().
    // 4. Do NOT simplify this to a synchronous call, or it will fail in some race conditions.
	func setKeyboardVisible(_ visible: Bool) {
		cancelAutoKeyboard()
		keyboardVisible = visible
		if visible {
            DispatchQueue.main.async {
                self.reloadInputViews()
                let success = self.becomeFirstResponder()
                if !success {
                   // Fallback: try again? or just log (can't log).
                   // Maybe ensure user interaction is on on window?
                }
            }
		} else {
			resignFirstResponder()
		}
	}

}

protocol ParsecTouchInputDelegate: AnyObject {
	// Called on every touch change with the authoritative set of currently-active touches.
	func parsecTouchesUpdated(_ activeTouches: Set<UITouch>, moved: Bool)
	func parsecTouchesCancelled()
}

// A transparent overlay that owns every raw touch and forwards it to the controller. Sitting on
// top of (not inside) the scroll view, it gives deterministic, unfiltered touch delivery with no
// UIScrollView gesture races - the controller routes cursor, pinch / scroll, and three-finger pan.
class TouchOverlayView: UIView {
	weak var inputDelegate: ParsecTouchInputDelegate?

	// Forward the live touch set (excluding ended/cancelled) on every event. External mouse /
	// trackpad input arrives as indirect-pointer touches but is handled entirely by GCMouse, so it's
	// dropped here — otherwise it warps the direct-mode cursor and fights touchpad-mode drags.
	private func forward(_ event: UIEvent?, moved: Bool) {
		let active = (event?.allTouches ?? []).filter { touch in
			guard touch.view === self else { return false }
			guard touch.phase != .ended && touch.phase != .cancelled else { return false }
			if #available(iOS 13.4, *), touch.type == .indirectPointer { return false }
			return true
		}
		inputDelegate?.parsecTouchesUpdated(active, moved: moved)
	}
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: true) }
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { forward(event, moved: false) }
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		inputDelegate?.parsecTouchesCancelled()
	}
}
