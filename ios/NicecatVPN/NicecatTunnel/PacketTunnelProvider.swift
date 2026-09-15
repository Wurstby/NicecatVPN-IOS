import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var configs: [String] = []
    private var nodeNames: [String] = []
    private var nodeTags: [String] = []
    private var selectedIndex = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        configs = decodeArray(options?["configs"]).map(normalizeRulePaths)
        nodeNames = decodeArray(options?["nodeNames"])
        nodeTags = decodeArray(options?["nodeTags"])
        selectedIndex = 0

        guard !configs.isEmpty else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        #if canImport(Libbox)
        startSingBoxTunnel(completionHandler: completionHandler)
        #else
        startPlaceholderTunnel(completionHandler: completionHandler)
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        #if canImport(Libbox)
        stopSingBoxTunnel()
        #endif
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let payload: [String: Any] = [
            "node": currentNodeName,
            "tag": currentNodeTag,
            "libbox": isLibboxAvailable
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        completionHandler?(data)
    }

    private func startPlaceholderTunnel(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500
        settings.ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "8.8.8.8"])
        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
        }
    }

    #if canImport(Libbox)
    private func startSingBoxTunnel(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(TunnelError.libboxHookNotImplemented)
    }

    private func stopSingBoxTunnel() {
    }
    #endif

    private var currentNodeName: String {
        guard selectedIndex >= 0, selectedIndex < nodeNames.count else {
            return "豪猫加速器"
        }
        return nodeNames[selectedIndex]
    }

    private var currentNodeTag: String {
        guard selectedIndex >= 0, selectedIndex < nodeTags.count else {
            return ""
        }
        return nodeTags[selectedIndex]
    }

    private var isLibboxAvailable: Bool {
        #if canImport(Libbox)
        true
        #else
        false
        #endif
    }

    private func decodeArray(_ object: NSObject?) -> [String] {
        guard let string = object as? String, let data = string.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }

    private func normalizeRulePaths(_ config: String) -> String {
        guard let data = config.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var route = root["route"] as? [String: Any],
              var ruleSets = route["rule_set"] as? [[String: Any]] else {
            return config
        }
        for index in ruleSets.indices {
            guard let path = ruleSets[index]["path"] as? String else {
                continue
            }
            let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let bundlePath = Bundle.main.path(forResource: fileName, ofType: "srs", inDirectory: "rules") {
                ruleSets[index]["path"] = bundlePath
            }
        }
        route["rule_set"] = ruleSets
        root["route"] = route
        guard let normalizedData = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return config
        }
        return String(data: normalizedData, encoding: .utf8) ?? config
    }

    private enum TunnelError: LocalizedError {
        case missingConfiguration
        case libboxHookNotImplemented

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "缺少 VPN 配置"
            case .libboxHookNotImplemented:
                return "已检测到 Libbox，但还需要接入 iOS 版 sing-box 启动代码"
            }
        }
    }
}
