#if canImport(Libbox)
import Foundation
import Libbox
import Network
import NetworkExtension
import UserNotifications

final class SingBoxPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private let tunnel: PacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?
    private var lastNetworkPath: String?

    init(tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTunAsync(options, ret0_)
        }
    }

    private func openTunAsync(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw makeError("Nil tun options")
        }
        guard let ret0_ else {
            throw makeError("Nil tun file descriptor return pointer")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())
            configureDNS(options, settings: settings)
            try configureIPv4(options, settings: settings)
            try configureIPv6(options, settings: settings)
        }
        if options.isHTTPProxyEnabled() {
            configureHTTPProxy(options, settings: settings)
        }

        networkSettings = settings
        try await tunnel.applyTunnelNetworkSettings(settings)

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }
        let tunFd = LibboxGetTunnelFileDescriptor()
        guard tunFd != -1 else {
            throw makeError("Missing tunnel file descriptor")
        }
        ret0_.pointee = tunFd
    }

    private func configureDNS(_ options: LibboxTunOptionsProtocol, settings: NEPacketTunnelNetworkSettings) {
        guard options.getDNSMode()?.value != LibboxDNSModeDisabled,
              let iterator = try? options.getDNSServerAddress() else {
            return
        }
        var servers: [String] = []
        while iterator.hasNext() {
            servers.append(iterator.next())
        }
        guard !servers.isEmpty else {
            return
        }
        let dnsSettings = NEDNSSettings(servers: servers)
        dnsSettings.matchDomains = [""]
        dnsSettings.matchDomainsNoSearch = true
        settings.dnsSettings = dnsSettings
    }

    private func configureIPv4(_ options: LibboxTunOptionsProtocol, settings: NEPacketTunnelNetworkSettings) throws {
        var addresses: [String] = []
        var masks: [String] = []
        let addressIterator = options.getInet4Address()
        while addressIterator?.hasNext() == true {
            guard let prefix = addressIterator?.next() else { continue }
            addresses.append(prefix.address())
            masks.append(prefix.mask())
        }
        guard !addresses.isEmpty else {
            return
        }
        let ipv4 = NEIPv4Settings(addresses: addresses, subnetMasks: masks)
        var routes: [NEIPv4Route] = []
        let routeIterator = options.getInet4RouteAddress()
        while routeIterator?.hasNext() == true {
            guard let prefix = routeIterator?.next() else { continue }
            routes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
        }
        if routes.isEmpty {
            routes.append(.default())
        }
        var excludedRoutes: [NEIPv4Route] = []
        let excludeIterator = options.getInet4RouteExcludeAddress()
        while excludeIterator?.hasNext() == true {
            guard let prefix = excludeIterator?.next() else { continue }
            excludedRoutes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
        }
        ipv4.includedRoutes = routes
        ipv4.excludedRoutes = excludedRoutes
        settings.ipv4Settings = ipv4
    }

    private func configureIPv6(_ options: LibboxTunOptionsProtocol, settings: NEPacketTunnelNetworkSettings) throws {
        var addresses: [String] = []
        var prefixes: [NSNumber] = []
        let addressIterator = options.getInet6Address()
        while addressIterator?.hasNext() == true {
            guard let prefix = addressIterator?.next() else { continue }
            addresses.append(prefix.address())
            prefixes.append(NSNumber(value: prefix.prefix()))
        }
        guard !addresses.isEmpty else {
            return
        }
        let ipv6 = NEIPv6Settings(addresses: addresses, networkPrefixLengths: prefixes)
        var routes: [NEIPv6Route] = []
        let routeIterator = options.getInet6RouteAddress()
        while routeIterator?.hasNext() == true {
            guard let prefix = routeIterator?.next() else { continue }
            routes.append(NEIPv6Route(destinationAddress: prefix.address(), networkPrefixLength: NSNumber(value: prefix.prefix())))
        }
        if routes.isEmpty {
            routes.append(.default())
        }
        var excludedRoutes: [NEIPv6Route] = []
        let excludeIterator = options.getInet6RouteExcludeAddress()
        while excludeIterator?.hasNext() == true {
            guard let prefix = excludeIterator?.next() else { continue }
            excludedRoutes.append(NEIPv6Route(destinationAddress: prefix.address(), networkPrefixLength: NSNumber(value: prefix.prefix())))
        }
        ipv6.includedRoutes = routes
        ipv6.excludedRoutes = excludedRoutes
        settings.ipv6Settings = ipv6
    }

    private func configureHTTPProxy(_ options: LibboxTunOptionsProtocol, settings: NEPacketTunnelNetworkSettings) {
        let proxy = NEProxySettings()
        let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
        proxy.httpServer = server
        proxy.httpsServer = server
        proxy.httpEnabled = true
        proxy.httpsEnabled = true

        if let iterator = options.getHTTPProxyBypassDomain() {
            var domains: [String] = []
            while iterator.hasNext() {
                domains.append(iterator.next())
            }
            if !domains.isEmpty {
                proxy.exceptionList = domains
            }
        }
        if let iterator = options.getHTTPProxyMatchDomain() {
            var domains: [String] = []
            while iterator.hasNext() {
                domains.append(iterator.next())
            }
            if !domains.isEmpty {
                proxy.matchDomains = domains
            }
        }
        settings.proxySettings = proxy
    }

    func usePlatformAutoDetectControl() -> Bool {
        false
    }

    func autoDetectControl(_: Int32) throws {}

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw makeError("Connection owner lookup is not available on iOS")
    }

    func useProcFS() -> Bool {
        false
    }

    func writeLog(_ message: String?) {
        guard let message else { return }
        tunnel.writeMessage(message)
    }

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onUpdateDefaultInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.onUpdateDefaultInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        semaphore.wait()
    }

    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
        lastNetworkPath = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            throw makeError("NWPathMonitor is not started")
        }
        let path = nwMonitor.currentPath
        guard path.status != .unsatisfied else {
            return NetworkInterfaceArray([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for item in path.availableInterfaces {
            let networkInterface = LibboxNetworkInterface()
            networkInterface.name = item.name
            networkInterface.index = Int32(item.index)
            switch item.type {
            case .wifi:
                networkInterface.type = LibboxInterfaceTypeWIFI
            case .cellular:
                networkInterface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                networkInterface.type = LibboxInterfaceTypeEthernet
            default:
                networkInterface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(networkInterface)
        }
        return NetworkInterfaceArray(interfaces)
    }

    func underNetworkExtension() -> Bool {
        true
    }

    func includeAllNetworks() -> Bool {
        false
    }

    func clearDNSCache() {
        guard let networkSettings else { return }
        runBlocking {
            self.tunnel.reasserting = true
            defer { self.tunnel.reasserting = false }
            try? await self.tunnel.applyTunnelNetworkSettings(nil)
            try? await self.tunnel.applyTunnelNetworkSettings(networkSettings)
        }
    }

    func readWIFIState() -> LibboxWIFIState? {
        let network = runBlocking {
            await NEHotspotNetwork.fetchCurrent()
        }
        guard let network else {
            return nil
        }
        return LibboxWIFIState(network.ssid, wifiBSSID: network.bssid)
    }

    func readWIFISSID() -> String? {
        runBlocking {
            await NEHotspotNetwork.fetchCurrent()?.ssid
        }
    }

    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw makeError("SSH agent forwarding is not supported on iOS")
    }

    func serviceStop() throws {
        tunnel.stopLibboxService()
    }

    func serviceReload() throws {
        try runBlocking { [self] in
            try await tunnel.reloadLibboxService()
        }
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        guard let proxy = networkSettings?.proxySettings, proxy.httpServer != nil else {
            return status
        }
        status.available = true
        status.enabled = proxy.httpEnabled
        return status
    }

    func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard let settings = networkSettings,
              let proxy = settings.proxySettings,
              proxy.httpServer != nil,
              proxy.httpEnabled != isEnabled else {
            return
        }
        proxy.httpEnabled = isEnabled
        proxy.httpsEnabled = isEnabled
        settings.proxySettings = proxy
        try runBlocking {
            try await self.tunnel.applyTunnelNetworkSettings(settings)
        }
    }

    func triggerNativeCrash() throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            fatalError("debug native crash")
        }
    }

    func writeDebugMessage(_ message: String?) {
        guard let message else { return }
        NSLog("[sing-box] %@", message)
    }

    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
        lastNetworkPath = nil
    }

    func send(_ notification: LibboxNotification?) throws {
        guard let notification else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        try runBlocking {
            try await UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelNotification(_ identifier: String?, typeID _: Int32) throws {
        guard let identifier else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}

    func registerMyInterface(_ name: String?) {}

    func closeNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {}

    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? {
        nil
    }

    func systemCertificates() -> (any LibboxStringIteratorProtocol)? {
        nil
    }

    func usePlatformShell() -> Bool {
        false
    }

    func checkPlatformShell() throws {
        throw makeError("Platform shell is not supported on iOS")
    }

    func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: (any LibboxStringIteratorProtocol)?, term: String?, rows: Int32, cols: Int32) throws -> any LibboxShellSessionProtocol {
        throw makeError("Shell sessions are not supported on iOS")
    }

    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String {
        error?.pointee = makeError("System SSH host key is not available on iOS") as NSError
        return ""
    }

    func lookupSFTPServer(_ error: NSErrorPointer) -> String {
        error?.pointee = makeError("SFTP server lookup is not available on iOS") as NSError
        return ""
    }

    func tailscaleHostname() -> String {
        "NicecatVPN-iOS"
    }

    func usePlatformBridge() -> Bool {
        false
    }

    func createBridge(_ options: LibboxBridgeOptions?) throws -> any LibboxBridgeSessionProtocol {
        throw makeError("Bridge mode is not supported on iOS")
    }

    func usePlatformAutoRedirect() -> Bool {
        false
    }

    func createAutoRedirect(_: Data?, handler _: (any LibboxAutoRedirectHandlerProtocol)?) throws -> any LibboxAutoRedirectSessionProtocol {
        throw makeError("Auto redirect is not supported on iOS")
    }

    func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
        throw makeError("User lookup is not supported on iOS")
    }

    private func onUpdateDefaultInterface(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: NWPath) {
        let networkPath = describeNetworkPath(path)
        listener.updateNetworkPath(networkPath)
        guard networkPath != lastNetworkPath else {
            return
        }
        lastNetworkPath = networkPath
        guard path.status != .unsatisfied, let defaultInterface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(defaultInterface.name, interfaceIndex: Int32(defaultInterface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    private func describeNetworkPath(_ path: NWPath) -> String {
        var parts: [String] = []
        switch path.status {
        case .satisfied:
            parts.append("satisfied")
        case .unsatisfied:
            parts.append("unsatisfied")
        case .requiresConnection:
            parts.append("requiresConnection")
        @unknown default:
            parts.append("unknown")
        }
        if !path.availableInterfaces.isEmpty {
            parts.append("interfaces=" + path.availableInterfaces.map { "\($0.name)#\($0.index)/\($0.type)" }.joined(separator: ","))
        }
        if path.supportsIPv4 {
            parts.append("ipv4")
        }
        if path.supportsIPv6 {
            parts.append("ipv6")
        }
        if path.supportsDNS {
            parts.append("dns")
        }
        if path.isExpensive {
            parts.append("expensive")
        }
        if path.isConstrained {
            parts.append("constrained")
        }
        return parts.joined(separator: " ")
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "NicecatSingBoxPlatform", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class NetworkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private let interfaces: [LibboxNetworkInterface]
    private var index = 0
    private var nextValue: LibboxNetworkInterface?

    init(_ interfaces: [LibboxNetworkInterface]) {
        self.interfaces = interfaces
    }

    func hasNext() -> Bool {
        guard index < interfaces.count else {
            nextValue = nil
            return false
        }
        nextValue = interfaces[index]
        index += 1
        return true
    }

    func next() -> LibboxNetworkInterface? {
        nextValue
    }
}
#endif
