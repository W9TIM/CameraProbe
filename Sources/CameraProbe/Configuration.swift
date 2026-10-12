import Foundation

// MARK: - Identity

let cameraProbeLabel = "com.tim.cameraprobe"
let appVersion = "2.0.0"

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
//   },
//   "ignoredApplications": ["Photo Booth"]
// }
//
// Every field is optional in the file itself - anything omitted falls
// back to a default, so a partial config.json (e.g. just overriding
// relay.host) is valid. Codable (not just Decodable) so the Preferences
// window can write changes back out, not just read them.

struct RelayConfig: Codable {
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

struct HomeAssistantConfig: Codable {
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

struct AppConfig: Codable {
    var relay: RelayConfig
    var homeAssistant: HomeAssistantConfig
    var ignoredApplications: [String]

    enum CodingKeys: String, CodingKey {
        case relay, homeAssistant, ignoredApplications
    }

    init(
        relay: RelayConfig = RelayConfig(),
        homeAssistant: HomeAssistantConfig = HomeAssistantConfig(),
        ignoredApplications: [String] = []
    ) {
        self.relay = relay
        self.homeAssistant = homeAssistant
        self.ignoredApplications = ignoredApplications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relay = try container.decodeIfPresent(RelayConfig.self, forKey: .relay) ?? RelayConfig()
        homeAssistant = try container.decodeIfPresent(HomeAssistantConfig.self, forKey: .homeAssistant) ?? HomeAssistantConfig()
        ignoredApplications = try container.decodeIfPresent([String].self, forKey: .ignoredApplications) ?? []
    }
}

// MARK: - Config file location
//
// Per-user (~/Library/Application Support), not system-wide
// (/Library/Application Support) - this is a GUI app the user configures
// themselves via the Preferences window, so it reads/writes its own
// config with no sudo/admin prompt ever required.

let configFilePath: String = {
    FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CameraProbe/config.json")
        .path
}()

// MARK: - Config Store
//
// Holds the current config in memory behind a lock, so the Preferences
// window can update it and have every part of the app (Relay.swift,
// HomeAssistant.swift, CameraMonitor.swift, etc.) see the new values
// immediately, without an app restart. Everything else in the codebase
// still just reads the plain global names below (relayHost, relayPort,
// ...) - those are now computed properties backed by this store instead
// of one-time-loaded constants, so no call site needed to change.

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    private let lock = NSLock()
    private var _config: AppConfig

    private init() {
        _config = ConfigStore.loadFromDisk()
    }

    var config: AppConfig {
        lock.lock(); defer { lock.unlock() }
        return _config
    }

    /// Writes `newConfig` to disk and, only on success, updates the
    /// in-memory config that the rest of the app reads from.
    func save(_ newConfig: AppConfig) throws {
        let directory = (configFilePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(newConfig)
        try data.write(to: URL(fileURLWithPath: configFilePath), options: .atomic)

        lock.lock()
        _config = newConfig
        lock.unlock()

        print("Saved configuration to \(configFilePath)")
        logger.info("Configuration updated from Preferences and saved to \(configFilePath, privacy: .public)")
    }

    private static func loadFromDisk() -> AppConfig {
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
            return AppConfig()
        }
    }
}

// MARK: - Flattened accessors
//
// Computed, not stored, so they always reflect whatever is currently in
// ConfigStore - including right after a Preferences window save.

var relayHost: String { ConfigStore.shared.config.relay.host }
var relayPort: Int { ConfigStore.shared.config.relay.port }
var enableRelay: Bool { ConfigStore.shared.config.relay.enabled }

var homeAssistantHost: String { ConfigStore.shared.config.homeAssistant.host }
var homeAssistantPort: Int { ConfigStore.shared.config.homeAssistant.port }
var enableHomeAssistant: Bool { ConfigStore.shared.config.homeAssistant.enabled }

// Apps in this list are still detected internally (camera state tracking
// keeps working correctly for whatever runs next), but never trigger a
// relay/Home Assistant notification - useful for privacy (e.g. Photo
// Booth) or gameplay capture apps you don't want broadcasting "on air".
// Matching is case-insensitive.
var ignoredApplications: [String] { ConfigStore.shared.config.ignoredApplications }

func isApplicationIgnored(_ application: String) -> Bool {
    ignoredApplications.contains { $0.caseInsensitiveCompare(application) == .orderedSame }
}

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
