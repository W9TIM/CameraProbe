import Foundation

// MARK: - Identity
//
// Shared with the LaunchAgent label used by install.sh/uninstall.sh and
// the OSLog subsystem in Logger.swift, so there's one source of truth
// instead of the same string typed in three places.

let cameraProbeLabel = "com.tim.cameraprobe"
let appVersion = "1.0.0"

// MARK: - Configuration file schema
//
// Mirrors config.example.json at the project root:
//
// {
//   "relay": {
//     "enabled": true,
//     "host": "onair.local",
//     "port": 80
//   },
//   "homeAssistant": {
//     "enabled": true,
//     "host": "homeassistant.local",
//     "port": 8123
//   }
// }
//
// Every field is optional in the file itself - anything omitted falls
// back to the same defaults CameraProbe shipped with before this file
// existed, so a partial config.json (e.g. just overriding relay.host)
// is valid.

struct RelayConfig: Decodable {
    var enabled: Bool
    var host: String
    var port: Int

    enum CodingKeys: String, CodingKey {
        case enabled, host, port
    }

    init(enabled: Bool = true, host: String = "onair.local", port: Int = 80) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "onair.local"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 80
    }
}

struct HomeAssistantConfig: Decodable {
    var enabled: Bool
    var host: String
    var port: Int

    enum CodingKeys: String, CodingKey {
        case enabled, host, port
    }

    init(enabled: Bool = true, host: String = "homeassistant.local", port: Int = 8123) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "homeassistant.local"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8123
    }
}

struct AppConfig: Decodable {
    var relay: RelayConfig
    var homeAssistant: HomeAssistantConfig

    enum CodingKeys: String, CodingKey {
        case relay, homeAssistant
    }

    init(relay: RelayConfig = RelayConfig(), homeAssistant: HomeAssistantConfig = HomeAssistantConfig()) {
        self.relay = relay
        self.homeAssistant = homeAssistant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relay = try container.decodeIfPresent(RelayConfig.self, forKey: .relay) ?? RelayConfig()
        homeAssistant = try container.decodeIfPresent(HomeAssistantConfig.self, forKey: .homeAssistant) ?? HomeAssistantConfig()
    }
}

// MARK: - Loading

let configFilePath = "/Library/Application Support/CameraProbe/config.json"

func loadConfiguration() -> AppConfig {
    guard FileManager.default.fileExists(atPath: configFilePath) else {
        print("No config file at \(configFilePath); using built-in defaults")
        return AppConfig()
    }

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        print("Loaded configuration from \(configFilePath)")
        return config
    } catch {
        // A bad config file should never take the monitor down - fall back
        // to defaults and make the failure loud instead.
        print("Warning: failed to parse \(configFilePath): \(error.localizedDescription). Using built-in defaults.")
        logger.error("Failed to parse \(configFilePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return AppConfig()
    }
}

let appConfig = loadConfiguration()

// MARK: - Flattened accessors
//
// Everything else in the codebase (Relay.swift, HomeAssistant.swift,
// Logger.swift, main.swift) references these same names, so switching
// from hardcoded constants to a config file didn't require touching
// any other file.

let relayHost = appConfig.relay.host
let relayPort = appConfig.relay.port
let enableRelay = appConfig.relay.enabled

let homeAssistantHost = appConfig.homeAssistant.host
let homeAssistantPort = appConfig.homeAssistant.port
let enableHomeAssistant = appConfig.homeAssistant.enabled

// How long to wait after the camera turns on before asking macOS which
// app is frontmost. NSWorkspace.frontmostApplication is not necessarily
// the app that grabbed the camera, and it can take a moment to become
// accurate after a video call starts.
let activeApplicationDetectionDelay: TimeInterval = 3.0

// MARK: - Shared networking
//
// One shared session with sane timeouts, reused by both the relay and
// Home Assistant calls, instead of spinning up a fresh URLSession per
// request.

let networkSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 5
    return URLSession(configuration: configuration)
}()
