import SwiftUI

struct StreamControlBar: View {
	let showMenu: Bool
	let showKeyboard: Bool
	let keyboardButtonVisible: Bool
	let missionControlEnabled: Bool
	let onMenu: () -> Void
	let onKeyboard: () -> Void
	let onMissionControl: () -> Void

	var body: some View {
		HStack(spacing: 4) {
			control("slider.horizontal.3", label: showMenu ? "Close session menu" : "Session menu",
				isActive: showMenu, action: onMenu)
			if keyboardButtonVisible {
				control("keyboard", label: showKeyboard ? "Hide keyboard" : "Show keyboard",
					isActive: showKeyboard, action: onKeyboard)
			}
			control("rectangle.3.group", label: "Mission Control", action: onMissionControl)
				.disabled(!missionControlEnabled)
				.opacity(missionControlEnabled ? 1 : 0.4)
		}
		.padding(6)
		.background(Color.black.opacity(0.72))
		.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
			.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
		.shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
		.accessibilityElement(children: .contain)
	}

	private func control(_ symbol: String, label: String, isActive: Bool = false,
						 action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: symbol)
				.font(.system(size: 20, weight: .medium))
				.foregroundColor(.white)
				.frame(width: 44, height: 44)
				.background(RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(Color.white.opacity(isActive ? 0.18 : 0)))
				.contentShape(Rectangle())
		}
		.buttonStyle(PlainButtonStyle())
		.accessibilityLabel(Text(label))
	}
}
