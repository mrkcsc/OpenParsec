# <p align="center">![icon_transparent.png](OpenParsec/Assets.xcassets/IconTransparent.imageset/icon_transparent.png) ![OpenParsec](OpenParsec/Assets.xcassets/LogoShadow.imageset/logo_shadow.png)</p>

OpenParsec is a simple, open-source Parsec client for iOS/iPadOS written in Swift using the SwiftUI framework and the Parsec SDK.

This project is still a major WIP, so apologies for the currently lackluster documentation. I'm also very new to both Swift and SwiftUI so I'm sure there are many places for improvement.

Before building, make sure you have the Parsec SDK framework symlinked or copied to the `Frameworks` folder. Build with Xcode 27.1 or later; the app supports iOS 15 and later. The iOS 27.1 SDK enables [edge-to-edge layouts on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/), including when folding or unfolding during a stream. Older SDKs put the app in a smaller compatibility window.

## Downloads
<a href="https://stikstore.app/altdirect/?url=https://github.com/hugeBlack/OpenParsec/releases/download/nightly/altstore.json" target="_blank">
   <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/AltSource_Blue.png" alt="Add AltSource" width="200">
</a>
<a href="https://github.com/hugeBlack/OpenParsec/releases/download/nightly/OpenParsec.ipa" target="_blank">
   <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/Download_Blue.png" alt="Download .ipa" width="200">
</a>

## Touch Control
The horizontal control bar stays inside the phone's safe area. Its matching icons open the session menu, show or hide the keyboard, and toggle Mission Control on a Mac host using Control–Up Arrow.

Connection statistics appear in a matching panel at the bottom of the safe area, with centered text that wraps to fit the screen.

Turn on **Tap to click** in the session menu to move the mouse to the spot you tap and click there, including while zoomed in. Hold and move one finger to drag. Turn it off to use **Touchpad** mode, where dragging moves the mouse and tapping clicks at its current position.

You can also choose either mode under **Settings → Touch Mode**. Your choice is remembered between sessions.

Enable **Auto keyboard** in the session menu or settings to open the keyboard when a tap leaves the mouse over a text-entry cursor. This optional cursor-shape heuristic can also trigger over selectable text and may miss custom cursors. It never closes the keyboard automatically; the keyboard button and three-finger tap remain available.

When streaming, you can tap with 3 fingers to bring up the on-screen keyboard.

The keyboard uses any black border below the stream before moving the view. When a recent tap identifies the likely input location, only that area is kept above the keyboard; otherwise the view moves just enough to uncover the stream. Dismissing the keyboard undoes its automatic shift without resetting your zoom.

Pinch with two fingers to zoom in or out around the point between your fingers. Once a pinch starts, move both fingers to pan the zoomed view. To pan without starting another pinch, drag with three fingers. Panning keeps the zoom level unchanged and does not open the keyboard. Zooming and panning do not move the remote mouse.

Move two fingers together without pinching to scroll on the remote computer at any zoom level. Tap with two fingers to right-click. The overlay menu's **Reset zoom** button returns to the full view.

Gesture recognition and viewport geometry tests run locally with `swift test`.

## Mouse & keyboard
USB mouse & keyboard are supported. 

## Copy & paste
Use **Copy** and **Paste** at the top of the session menu or keyboard accessory bar. Select text on the remote computer, then tap **Copy** to copy it to your phone. Text copied using the host's own Copy command also reaches the phone while the session is active. Tap **Paste** to send the phone's text clipboard and paste it into the focused remote app.

The buttons default to Mac shortcuts (⌘C / ⌘V). For a Windows or Linux host, choose **Shortcuts → Windows / Linux** in the session menu. Clipboard sharing must be enabled on the host and permitted for the connection; Parsec normally permits it on connections to your own computers. This supports plain text, including Unicode and multiple lines, up to 1 MB; images and files are not transferred.

The phone's clipboard is read only when you request a paste. Clipboard contents are not saved or logged, and received text is kept out of Universal Clipboard to avoid sending it back to the host. Pending pastes are cancelled if the connection changes.

The text transport uses Parsec user-data message 7, as implemented by [VDI Stream Client](https://github.com/mbroemme/vdi-stream-client/blob/849b25d65636b491ec8a4e121b34e17711cdb945/src/parsec.h#L60). Host clipboard settings are described in [Parsec's configuration reference](https://support.parsec.app/hc/en-us/articles/32381443626516-All-Advanced-Configuration-Options).

## Game Controllers
When streaming, press any trigger button in your controller and parsec will recognize it. Make sure to configure the host properly (install virtual USB driver etc.) before using game controllers.

## Lag / Low Bitrate Issue
If you encounter lags from nowhere or your bitrate hardly goes over 10 Mbps, download Steam Link and do a network test. If you see constant lag spike in the graph, then it's a problem with Apple and there's little we can do to solve this problem. See [here](https://github.com/moonlight-stream/moonlight-ios/issues/627) for more disscussion. 

If you can't change your wireless router's channel to 149 like me, my personal experience is that you can try to power off the device you are using to stream as well as any nearby Apple devices, especially Mac, then only power on the device you are using to stream and do the aforementioned network test again. You can turn on other devices if the lag spike is gone and it may sustain for couple hours or days.
