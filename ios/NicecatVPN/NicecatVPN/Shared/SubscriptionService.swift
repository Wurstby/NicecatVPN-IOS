import Foundation

final class SubscriptionService {
    private let cacheURL: URL

    init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = directory.appendingPathComponent("nicecat_nodes.cache")
    }

    func fetchNodes() async throws -> [NodeProfile] {
        let url = try CryptoService.subscriptionURL()
        var request = URLRequest(url: url)
        request.setValue("NicecatVPN-iOS/\(AppConstants.versionName)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (encrypted, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubscriptionError.http(http.statusCode)
        }
        let plain = try CryptoService.decryptBase64Payload(String(data: encrypted, encoding: .utf8) ?? "")
        let text = String(data: plain, encoding: .utf8) ?? ""
        let nodes = LinkParser.parseLinks(text)
        try saveCache(nodes)
        return nodes
    }

    func loadCachedNodes() -> [NodeProfile] {
        guard let encrypted = try? Data(contentsOf: cacheURL),
              let text = String(data: encrypted, encoding: .utf8),
              let plain = try? CryptoService.decryptBase64Payload(text),
              let plainText = String(data: plain, encoding: .utf8) else {
            return []
        }
        return LinkParser.parseLinks(plainText)
    }

    private func saveCache(_ nodes: [NodeProfile]) throws {
        let text = nodes.map(\.link).filter { !$0.isEmpty }.joined(separator: "\n")
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            return
        }
        let encrypted = try CryptoService.encryptToBase64Payload(data)
        try encrypted.data(using: .utf8)?.write(to: cacheURL, options: [.atomic])
    }

    enum SubscriptionError: Error {
        case http(Int)
    }
}
