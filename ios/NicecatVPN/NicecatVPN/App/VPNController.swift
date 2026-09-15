import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid

    private let tunnelBundleIdentifier = "com.nicecatvpn.ios.NicecatTunnel"
    private var manager: NETunnelProviderManager?

    init() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.status = self?.manager?.connection.status ?? .invalid
            }
        }
    }

    func load() async {
        do {
            manager = try await loadOrCreateManager()
            status = manager?.connection.status ?? .invalid
        } catch {
            status = .invalid
        }
    }

    func start(configs: [String], nodeNames: [String], nodeTags: [String]) async throws {
        let manager = try await loadOrCreateManager()
        self.manager = manager
        try await save(manager)
        guard let configContent = configs.first else {
            throw VPNError.missingConfiguration
        }
        let options: [String: NSObject] = [
            "configContent": configContent as NSString,
            "configs": try encode(configs) as NSObject,
            "nodeNames": try encode(nodeNames) as NSObject,
            "nodeTags": try encode(nodeTags) as NSObject
        ]
        try manager.connection.startVPNTunnel(options: options)
        status = manager.connection.status
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleIdentifier }) {
            configure(existing)
            return existing
        }
        let created = NETunnelProviderManager()
        configure(created)
        return created
    }

    private func configure(_ manager: NETunnelProviderManager) {
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleIdentifier
        proto.serverAddress = AppConstants.appName
        proto.disconnectOnSleep = false
        manager.protocolConfiguration = proto
        manager.localizedDescription = AppConstants.appName
        manager.isEnabled = true
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await manager.savePreferencesAsync()
        try await manager.loadPreferencesAsync()
    }

    private func encode(_ value: [String]) throws -> NSString {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return NSString(string: String(data: data, encoding: .utf8) ?? "[]")
    }
}

private enum VPNError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        "缺少 VPN 配置"
    }
}

private extension NETunnelProviderManager {
    static func loadAllFromPreferences() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    func savePreferencesAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func loadPreferencesAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
