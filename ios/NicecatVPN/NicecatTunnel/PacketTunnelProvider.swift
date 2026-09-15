import Foundation
import NetworkExtension
#if canImport(Libbox)
import Libbox
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var configs: [String] = []
    private var nodeNames: [String] = []
    private var nodeTags: [String] = []
    private var selectedIndex = 0
    #if canImport(Libbox)
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = SingBoxPlatformInterface(tunnel: self)
    private var activeConfig = ""
    #endif

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
        activeConfig = (options?["configContent"] as? String).map(normalizeRulePaths) ?? configs[0]
        startSingBoxTunnel(completionHandler: completionHandler)
        #else
        startPlaceholderTunnel(completionHandler: completionHandler)
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        #if canImport(Libbox)
        Task {
            await stopSingBoxTunnel(reason: reason)
            completionHandler()
        }
        #else
        completionHandler()
        #endif
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
        Task {
            do {
                try await startSingBoxTunnel()
                completionHandler(nil)
            } catch {
                await stopSingBoxTunnel(reason: .none)
                completionHandler(error)
            }
        }
    }

    private func startSingBoxTunnel() async throws {
        let paths = try makeRuntimePaths()
        let options = LibboxSetupOptions()
        options.basePath = paths.base.path
        options.workingPath = paths.working.path
        options.tempPath = paths.temporary.path
        options.logMaxLines = 1000
        options.debug = false
        options.crashReportSource = "NetworkExtension"
        options.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        options.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
        options.platformMetadata = "{}"
        options.oomKillerEnabled = true
        options.powerReportEnabled = false

        var setupError: NSError?
        LibboxSetup(options, &setupError)
        if let setupError {
            throw TunnelError.libboxStartup("setup: \(setupError.localizedDescription)")
        }

        var serverError: NSError?
        guard let server = LibboxNewCommandServer(platformInterface, platformInterface, &serverError) else {
            throw TunnelError.libboxStartup(serverError?.localizedDescription ?? "无法创建命令服务")
        }
        commandServer = server

        do {
            try server.start()
            try server.startOrReloadService(activeConfig, options: LibboxOverrideOptions())
        } catch {
            server.close()
            commandServer = nil
            throw TunnelError.libboxStartup(error.localizedDescription)
        }
    }

    private func stopSingBoxTunnel(reason: NEProviderStopReason) async {
        writeMessage("(packet-tunnel) stopping, reason: \(reason.rawValue)")
        stopLibboxService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100_000_000)
            server.close()
            commandServer = nil
        }
    }

    func reloadLibboxService() async throws {
        guard let commandServer else {
            throw TunnelError.libboxStartup("命令服务未启动")
        }
        reasserting = true
        defer { reasserting = false }
        try commandServer.startOrReloadService(activeConfig, options: LibboxOverrideOptions())
    }

    func stopLibboxService() {
        do {
            try commandServer?.closeService()
        } catch {
            writeMessage("(packet-tunnel) stop service: \(error.localizedDescription)")
        }
        platformInterface.reset()
    }

    func writeMessage(_ message: String, level: Int32 = 3) {
        commandServer?.writeMessage(level, message: message)
    }

    func applyTunnelNetworkSettings(_ settings: NEPacketTunnelNetworkSettings?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setTunnelNetworkSettings(settings) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func makeRuntimePaths() throws -> (base: URL, working: URL, temporary: URL) {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/NicecatTunnel", isDirectory: true)
        let working = base.appendingPathComponent("Working", isDirectory: true)
        let temporary = base.appendingPathComponent("Temp", isDirectory: true)
        for url in [base, working, temporary] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (base, working, temporary)
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
        case libboxStartup(String)

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "缺少 VPN 配置"
            case let .libboxStartup(reason):
                return "sing-box 启动失败: \(reason)"
            }
        }
    }
}
