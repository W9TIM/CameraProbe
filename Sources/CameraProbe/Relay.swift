import Foundation

func sendRelayCommand(_ command: String) {
    guard enableRelay else {
        return
    }

    guard let url = URL(string: "http://\(relayHost):\(relayPort)/\(command)") else {
        logger.error("Bad relay URL")
        return
    }

    print("Sending relay \(command) -> \(url.absoluteString)")
    logger.info("Sending relay \(command, privacy: .public) -> \(url.absoluteString, privacy: .public)")

    networkSession.dataTask(with: url) { data, response, error in
        if let error = error {
            logger.error("Relay HTTP Error: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let http = response as? HTTPURLResponse {
            print("Relay HTTP Status:", http.statusCode)
            logger.info("Relay HTTP Status: \(http.statusCode)")
        }

        if let data = data,
           let reply = String(data: data, encoding: .utf8) {
            print("ESP Reply:", reply)
        }
    }.resume()
}
