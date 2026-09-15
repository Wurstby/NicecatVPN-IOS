import Foundation

enum AppConstants {
    static let appName = "豪猫加速器"
    static let subtitle = "Free VPN"
    static let versionName = "0.0.1"
    static let proxyPort = 2080
    static let autoTag = "__auto__"
}

enum RouteMode: String, CaseIterable {
    case rule
    case global

    var title: String {
        switch self {
        case .rule: return "规则模式"
        case .global: return "全局模式"
        }
    }
}

enum ConnectionPhase: Equatable {
    case disconnected
    case testingDelay
    case connecting
    case connected
    case failed(String)

    var pillText: String {
        switch self {
        case .disconnected, .failed:
            return "未连接"
        case .testingDelay:
            return "正在测试延迟"
        case .connecting:
            return "正在连接"
        case .connected:
            return "已连接"
        }
    }

    var centerText: String {
        switch self {
        case .disconnected, .failed:
            return "准备连接"
        case .testingDelay:
            return "正在测速"
        case .connecting:
            return "正在连接"
        case .connected:
            return "连接已建立"
        }
    }

    var buttonText: String {
        switch self {
        case .connected:
            return "断开"
        case .testingDelay, .connecting:
            return "连接中"
        case .disconnected, .failed:
            return "连接"
        }
    }

    var isBusy: Bool {
        self == .testingDelay || self == .connecting
    }
}

struct NodeProfile: Identifiable {
    let id: String
    let name: String
    let tag: String
    let link: String
    let server: String
    let port: Int
    let proto: String
    let flagCode: String?
    let outbound: [String: Any]
    var delayMs: Int?
    var delayTested = false

    init(name: String, tag: String, link: String, server: String, port: Int, proto: String, flagCode: String?, outbound: [String: Any]) {
        self.id = tag
        self.name = name
        self.tag = tag
        self.link = link
        self.server = server
        self.port = port
        self.proto = proto
        self.flagCode = flagCode
        self.outbound = outbound
    }

    var delayText: String {
        if let delayMs {
            return "\(delayMs) ms"
        }
        return delayTested ? "超时" : "未测"
    }

    var protocolTitle: String {
        guard !proto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "节点"
        }
        let value = proto.lowercased()
        return value.prefix(1).uppercased() + value.dropFirst()
    }
}
