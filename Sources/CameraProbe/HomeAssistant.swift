import Foundation

func sendHomeAssistantEvent(_ event: String, data: String = "") {
    guard enableHomeAssistant else {
        return
    }

    guard let url = URL(string:
        "http://\(homeAssistantHost):\(homeAssistantPort)/api/webhook/\(event)"
    ) else {
        logger.error("Bad Home Assistant URL")
        return
    }

    print("Sending Home Assistant \(event) -> \(url.absoluteString)")
    logger.info("Sending Home Assistant -> \(url.absoluteString, privacy: .public)")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    if !data.isEmpty {
        let payload = "application=\(data.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? data)"
        request.httpBody = payload.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
    }

    networkSession.dataTask(with: request) { responseData, response, error in
        if let error = error {
            print("Home Assistant Error:", error.localizedDescription)
            logger.error("Home Assistant Error: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let http = response as? HTTPURLResponse {
            print("Home Assistant HTTP Status:", http.statusCode)
            logger.info("Home Assistant Status: \(http.statusCode)")
        }

        if let responseData = responseData,
           let reply = String(data: responseData, encoding: .utf8),
           !reply.isEmpty {
            print("Home Assistant Reply:", reply)
        }
    }.resume()
}
