import Foundation

/// Mirrors the object `pipeline._finish` returns. Coding keys are explicit so a
/// rename on either side fails loudly instead of decoding to nil.
struct RecognitionResult: Codable, Equatable {
    let type: PassType
    let typeLabel: String
    let fields: PassFields
    let errors: [String]
    let warnings: [String]
    let fallbackUsed: Bool
    let imageSha256: String
    let modelCalls: Int
    let tokens: [String: Int]
    let elapsedMs: Int
    let cacheHit: Bool
    let ok: Bool

    private enum CodingKeys: String, CodingKey {
        case type
        case typeLabel = "type_label"
        case fields
        case errors
        case warnings
        case fallbackUsed = "fallback_used"
        case imageSha256 = "image_sha256"
        case modelCalls = "model_calls"
        case tokens
        case elapsedMs = "elapsed_ms"
        case cacheHit = "cache_hit"
        case ok
    }

    /// Ark's `usage` object carries `total_tokens` next to its parts, and
    /// `ark.py` passes every key through, so summing the dictionary would count
    /// the total twice. Only fall back to the sum when it is absent.
    var totalTokens: Int {
        tokens["total_tokens"] ?? tokens.values.reduce(0, +)
    }
}

enum RecognitionError: LocalizedError {
    case serverNotSet
    case unreachable(String)
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .serverNotSet:
            return "还没有填写后端地址。到「设置」里填 http://<这台电脑的局域网IP>:8787"
        case .unreachable(let detail):
            return "连不上后端：\(detail)\n\n检查三件事：后端进程在跑、手机和电脑同一个 Wi-Fi、Windows 防火墙放行了该端口。"
        case .http(let status, let message):
            return "后端返回 \(status)：\(message)"
        case .decoding(let detail):
            return "后端响应无法解析：\(detail)"
        }
    }
}

struct RecognitionClient {
    let baseURL: URL
    /// Two model calls plus a possible repair round; the upstream model is the
    /// slow part, not the network.
    var timeout: TimeInterval = 90

    init(baseURL: URL, timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    static func current() throws -> RecognitionClient {
        guard let url = AppSettings.shared.serverURL else {
            throw RecognitionError.serverNotSet
        }
        return RecognitionClient(baseURL: url)
    }

    func recognize(_ image: PreparedImage) async throws -> RecognitionResult {
        let request = makeRequest(path: "recognize") { req in
            req.httpMethod = "POST"
            req.setValue(image.mime, forHTTPHeaderField: "Content-Type")
            req.httpBody = image.data
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw RecognitionError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RecognitionError.decoding("响应不是 HTTP")
        }

        // 422 carries a normal result body whose `ok` is false: the pass type was
        // read but some required field was missing. That is still usable.
        if http.statusCode == 200 || http.statusCode == 422 {
            do {
                return try JSONDecoder().decode(RecognitionResult.self, from: data)
            } catch {
                throw RecognitionError.decoding(String(decoding: data.prefix(400), as: UTF8.self))
            }
        }

        throw RecognitionError.http(status: http.statusCode, message: serverMessage(data))
    }

    /// `GET /healthz` — used by the settings screen's connection test so a wrong
    /// address is caught before a paid recognition call.
    func checkHealth() async throws -> String {
        let request = makeRequest(path: "healthz") { $0.httpMethod = "GET" }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw RecognitionError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RecognitionError.http(status: status, message: serverMessage(data))
        }

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let model = payload["model"] as? String {
            return model
        }
        return "已连接"
    }

    private func makeRequest(path: String, configure: (inout URLRequest) -> Void) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        configure(&request)
        return request
    }

    private func serverMessage(_ data: Data) -> String {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = payload["error"] as? String {
            return message
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "（空响应）" : text
    }
}
