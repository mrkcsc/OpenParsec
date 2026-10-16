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
		.modifier(StreamPanelStyle())
		.accessibilityElement(children: .contain)
	}

	private func control(_ symbol: String, label: String, isActive: Bool = false,
						 action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: symbol)
				.font(.system(size: 20, weight: .medium))
				.frame(width: 44, height: 44)
				.background(RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(Color.white.opacity(isActive ? 0.18 : 0)))
				.contentShape(Rectangle())
		}
		.buttonStyle(PlainButtonStyle())
		.accessibilityLabel(Text(label))
	}
}

struct StreamStatsPanel: View {
	let info: String

	var body: some View {
		Text(info.components(separatedBy: "    ")
			.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
			.joined(separator: "    "))
			.font(.system(size: 11, design: .monospaced))
			.multilineTextAlignment(.center)
			.lineSpacing(3)
			.lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.modifier(StreamPanelStyle())
	}
}

struct StreamMenuPanel<Content: View>: View {
	let content: Content
	@State private var contentHeight: CGFloat?

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		ScrollView {
			content
				.padding(.vertical, 6)
				.background(GeometryReader { geometry in
					Color.clear
						.onAppear { contentHeight = geometry.size.height }
						.onChange(of: geometry.size.height) { contentHeight = $0 }
				})
		}
		.frame(maxHeight: contentHeight)
		.modifier(StreamPanelStyle())
	}
}

private struct StreamPanelStyle: ViewModifier {
	func body(content: Content) -> some View {
		content
			.foregroundColor(.white)
			.background(Color.black.opacity(0.72))
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
			.shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
	}
}
