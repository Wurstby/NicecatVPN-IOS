import Foundation
import NetworkExtension

@MainActor
final class AppViewModel: ObservableObject {
    @Published var nodes: [NodeProfile] = []
    @Published var selectedTag: String = UserDefaults.standard.string(forKey: "selectedTag") ?? AppConstants.autoTag
    @Published var routeMode: RouteMode = RouteMode(rawValue: UserDefaults.standard.string(forKey: "routeMode") ?? "") ?? .global
    @Published var phase: ConnectionPhase = .disconnected
    @Published var currentPage: Page = .home
    @Published var errorMessage: String?
    @Published var isRefreshingNodes = false
    @Published var isTestingDelays = false
    @Published var downlinkText = "下载 0 B/s"
    @Published var uplinkText = "上传 0 B/s"

    private let subscriptionService = SubscriptionService()
    private let vpnController = VPNController()
    private var autoCandidateTag: String?
    private var connectAfterDelayTest = false

    enum Page {
        case home
        case nodes
    }

    func boot() {
        nodes = subscriptionService.loadCachedNodes()
        normalizeSelectedTag()
        Task {
            await vpnController.load()
            syncVPNStatus()
            await refreshNodes(firstLaunch: true)
        }
    }

    func refreshNodes(firstLaunch: Bool = false) async {
        guard !isRefreshingNodes, !isTestingDelays else {
            return
        }
        isRefreshingNodes = true
        if !firstLaunch {
            phase = .testingDelay
        }
        do {
            let fetched = try await subscriptionService.fetchNodes()
            nodes = fetched
            autoCandidateTag = nil
            normalizeSelectedTag()
            isRefreshingNodes = false
            await testDelays()
        } catch {
            isRefreshingNodes = false
            errorMessage = "刷新节点失败: \(error.localizedDescription)"
            syncVPNStatus()
        }
    }

    func testDelays() async {
        guard !nodes.isEmpty, !isRefreshingNodes, !isTestingDelays else {
            return
        }
        isTestingDelays = true
        autoCandidateTag = nil
        if phase != .connecting && phase != .connected {
            phase = .testingDelay
        }
        for index in nodes.indices {
            nodes[index].delayMs = nil
            nodes[index].delayTested = false
        }
        let results = await DelayTester.test(nodes: nodes)
        for index in nodes.indices {
            if let measured = results[nodes[index].tag] {
                nodes[index].delayMs = measured
            } else {
                nodes[index].delayMs = nil
            }
            nodes[index].delayTested = true
        }
        nodes.sort {
            switch ($0.delayMs, $1.delayMs) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return $0.name.lowercased() < $1.name.lowercased()
            }
        }
        updateAutoCandidate()
        isTestingDelays = false
        let shouldConnect = connectAfterDelayTest && selectedTag == AppConstants.autoTag
        connectAfterDelayTest = false
        if shouldConnect {
            await connect()
        } else {
            syncVPNStatus()
        }
    }

    func connectOrDisconnect() {
        if phase == .connected || phase.isBusy {
            disconnect()
        } else {
            Task { await connect() }
        }
    }

    func connect() async {
        if nodes.isEmpty {
            errorMessage = "节点列表为空，正在刷新"
            await refreshNodes()
            return
        }
        if selectedTag == AppConstants.autoTag && (isTestingDelays || !autoDelayReady) {
            phase = .testingDelay
            connectAfterDelayTest = true
            if !isTestingDelays {
                await testDelays()
            }
            return
        }
        do {
            phase = .connecting
            let order = selectedTag == AppConstants.autoTag ? autoConnectionOrder : [displayNode].compactMap { $0 }
            let configs = try order.map { try SingBoxConfigBuilder.build(nodes: nodes, selectedTag: $0.tag, routeMode: routeMode) }
            guard !configs.isEmpty else {
                throw SingBoxConfigBuilder.ConfigError.selectedNodeNotFound
            }
            try await vpnController.start(
                configs: configs,
                nodeNames: order.map(\.name),
                nodeTags: order.map(\.tag)
            )
            syncVPNStatus()
        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = "连接失败: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        connectAfterDelayTest = false
        vpnController.stop()
        downlinkText = "下载 0 B/s"
        uplinkText = "上传 0 B/s"
        phase = .disconnected
    }

    func selectAuto() {
        selectedTag = AppConstants.autoTag
        persistSelection()
        currentPage = .home
        if phase == .connected || phase.isBusy {
            Task { await connect() }
        }
    }

    func select(_ node: NodeProfile) {
        selectedTag = node.tag
        persistSelection()
        currentPage = .home
        if phase == .connected || phase.isBusy {
            Task { await connect() }
        }
    }

    func setRouteMode(_ mode: RouteMode) {
        routeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "routeMode")
        if phase == .connected || phase.isBusy {
            Task { await connect() }
        }
    }

    var displayNode: NodeProfile? {
        if selectedTag == AppConstants.autoTag {
            return nodes.first { $0.tag == autoCandidateTag }
        }
        return nodes.first { $0.tag == selectedTag }
    }

    var selectedNodeName: String {
        if selectedTag == AppConstants.autoTag {
            return displayNode?.name ?? "自动选择"
        }
        return displayNode?.name ?? "自动选择"
    }

    var selectedNodeMeta: String {
        if selectedTag == AppConstants.autoTag {
            if let node = displayNode {
                return "当前候选: \(node.name)"
            }
            return "自动测试并选择可用节点"
        }
        return displayNode?.protocolTitle ?? "节点"
    }

    var selectedDelayText: String {
        guard let node = displayNode else {
            return selectedTag == AppConstants.autoTag ? "AUTO" : "未测"
        }
        return node.delayText
    }

    private var autoDelayReady: Bool {
        autoCandidateTag.flatMap { tag in nodes.first { $0.tag == tag } } != nil
    }

    private var autoConnectionOrder: [NodeProfile] {
        var order: [NodeProfile] = []
        if let displayNode {
            order.append(displayNode)
        }
        for node in nodes where !order.contains(where: { $0.tag == node.tag }) {
            order.append(node)
        }
        return order
    }

    private func normalizeSelectedTag() {
        if selectedTag != AppConstants.autoTag && !nodes.contains(where: { $0.tag == selectedTag }) {
            selectedTag = AppConstants.autoTag
            persistSelection()
        }
    }

    private func updateAutoCandidate() {
        autoCandidateTag = nodes.first(where: { $0.delayMs != nil })?.tag ?? nodes.first?.tag
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedTag, forKey: "selectedTag")
    }

    private func syncVPNStatus() {
        switch vpnController.status {
        case .connected:
            phase = .connected
        case .connecting, .reasserting:
            phase = .connecting
        default:
            if !isRefreshingNodes && !isTestingDelays {
                phase = .disconnected
            }
        }
    }
}
