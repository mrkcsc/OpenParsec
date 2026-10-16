# <p align="center">![icon_transparent.png](OpenParsec/Assets.xcassets/IconTransparent.imageset/icon_transparent.png) ![OpenParsec](OpenParsec/Assets.xcassets/LogoShadow.imageset/logo_shadow.png)</p>

OpenParsec is a simple, open-source Parsec client for iOS/iPadOS written in Swift using the SwiftUI framework and the Parsec SDK.

This project is still a major WIP, so apologies for the currently lackluster documentation. I'm also very new to both Swift and SwiftUI so I'm sure there are many places for improvement.

Before building, make sure you have the Parsec SDK framework symlinked or copied to the `Frameworks` folder. Builds were tested on Xcode Version 12.5.

## Downloads
<a href="https://stikstore.app/altdirect/?url=https://github.com/hugeBlack/OpenParsec/releases/download/nightly/altstore.json" target="_blank">
   <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/AltSource_Blue.png" alt="Add AltSource" width="200">
</a>
<a href="https://github.com/hugeBlack/OpenParsec/releases/download/nightly/OpenParsec.ipa" target="_blank">
   <img src="https://raw.githubusercontent.com/StikStore/altdirect/refs/heads/main/assets/png/Download_Blue.png" alt="Download .ipa" width="200">
</a>

## Touch Control
Turn on **Tap to click** in the session menu to move the mouse to the spot you tap and click there, including while zoomed in. Hold and move one finger to drag. Turn it off to use **Touchpad** mode, where dragging moves the mouse and tapping clicks at its current position.

You can also choose either mode under **Settings → Touch Mode**. Your choice is remembered between sessions.

Enable **Auto keyboard** in the session menu or settings to open the keyboard when a tap leaves the mouse over a text-entry cursor. This optional cursor-shape heuristic can also trigger over selectable text and may miss custom cursors. It never closes the keyboard automatically; the keyboard button and three-finger tap remain available.

When streaming, you can tap with 3 fingers to bring up the on-screen keyboard.

Pinch with two fingers to zoom in or out around the point between your fingers. Once a pinch starts, move both fingers to pan the zoomed view. Zooming does not move the remote mouse.

Move two fingers together without pinching to scroll on the remote computer. Tap with two fingers to right-click. The overlay menu's **Reset zoom** button returns to the full view.

Gesture recognition and viewport geometry tests run locally with `swift test`.

## Mouse & keyboard
USB mouse & keyboard are supported. 

## Game Controllers
When streaming, press any trigger button in your controller and parsec will recognize it. Make sure to configure the host properly (install virtual USB driver etc.) before using game controllers.

## Lag / Low Bitrate Issue
If you encounter lags from nowhere or your bitrate hardly goes over 10 Mbps, download Steam Link and do a network test. If you see constant lag spike in the graph, then it's a problem with Apple and there's little we can do to solve this problem. See [here](https://github.com/moonlight-stream/moonlight-ios/issues/627) for more disscussion. 

If you can't change your wireless router's channel to 149 like me, my personal experience is that you can try to power off the device you are using to stream as well as any nearby Apple devices, especially Mac, then only power on the device you are using to stream and do the aforementioned network test again. You can turn on other devices if the lag spike is gone and it may sustain for couple hours or days.
