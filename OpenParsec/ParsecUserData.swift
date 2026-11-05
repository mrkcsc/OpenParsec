enum ParsecHostOS: Int {
	case unknown = 0
	case windows = 1
	case macOS = 2

	var windowOverviewLabel: String {
		switch self {
		case .windows: return "Task View"
		case .macOS: return "Mission Control"
		case .unknown: return "Show windows"
		}
	}
}

struct ParsecUserDataVideo: Codable {
	var encoderFPS: Int = 0
	var resolutionX: Int = 0
	var resolutionY: Int = 0
	var fullFPS: Bool = false
	var hostOS: Int? = 0
	var output = "none"
	var encoderMaxBitrate: Int = 50

	var operatingSystem: ParsecHostOS {
		ParsecHostOS(rawValue: hostOS ?? 0) ?? .unknown
	}
}

struct ParsecUserDataVideoConfig: Codable {
	var virtualMicrophone: Int = 0
	var virtualTablet: Int = 0
	var video: [ParsecUserDataVideo] = [
		ParsecUserDataVideo(),
		ParsecUserDataVideo(),
		ParsecUserDataVideo()
	]
}

struct ParsecDisplayConfig: Codable, Hashable {
	var name: String = ""
	var adapterName: String = ""
	var id: String = ""
}

enum ParsecUserDataType: UInt32 {
	case clipboard = 7
	case getVideoConfig = 9
	case getAdapterInfo = 10
	case setVideoConfig = 11
}
