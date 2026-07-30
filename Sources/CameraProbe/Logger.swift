import OSLog

let logger = Logger(
    subsystem: cameraProbeLabel,
    category: "CameraMonitor"
)

func printStartupBanner() {
    logger.info("""
    ----------------------------------------
    Camera Activity Monitor
    Relay: \(relayHost):\(relayPort)
    Home Assistant: \(homeAssistantHost):\(homeAssistantPort)
    Relay enabled: \(enableRelay)
    Home Assistant enabled: \(enableHomeAssistant)
    Watching camera state...
    ----------------------------------------
    """)
}
