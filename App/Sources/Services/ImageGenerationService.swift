import Foundation
import os.log

// MARK: - ImageGenerationService
//
// Generates images via OpenRouter's `/v1/images/generations` endpoint, which
// proxies DALL-E 3 and other image-generation models under the same OpenRouter
// API key the user already has configured. Returns the raw PNG/JPEG data so
// the caller can upload to Blossom and attach the resulting URL to a podcast.

protocol ImageGenerating: Sendable {
    func generate(prompt: String, model: String) async throws -> Data
}

struct ImageGenerationService: ImageGenerating {

    private static let logger = Logger.app("ImageGenerationService")
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/images/generations")!

    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func generate(prompt: String, model: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "response_format": "b64_json",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImageGenerationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let reason = String(data: responseData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ImageGenerationError.serverError(reason)
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first else {
            throw ImageGenerationError.malformedResponse
        }

        if let b64 = first["b64_json"] as? String, let data = Data(base64Encoded: b64) {
            return data
        }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (imageData, _) = try await session.data(from: url)
            return imageData
        }
        throw ImageGenerationError.malformedResponse
    }
}

enum ImageGenerationError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case serverError(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenRouter API key configured."
        case .invalidResponse: return "Image generation server did not respond."
        case .serverError(let msg): return "Image generation failed: \(msg)"
        case .malformedResponse: return "Image generation returned unexpected data."
        }
    }
}
