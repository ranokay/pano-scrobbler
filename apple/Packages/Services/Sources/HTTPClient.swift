import Foundation

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var data: Data
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body

        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResponse(statusCode: statusCode, data: data)
    }
}

enum FormEncoding {
    static func encode(_ values: [String: String]) -> Data {
        values
            .sorted { $0.key < $1.key }
            .map { "\(percentEscape($0.key))=\(percentEscape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    static func percentEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
