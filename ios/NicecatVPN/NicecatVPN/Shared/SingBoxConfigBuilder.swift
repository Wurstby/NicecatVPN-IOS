import Foundation

enum SingBoxConfigBuilder {
    private static let fakeIPCIDR = "198.18.0.0/15"

    static func build(nodes: [NodeProfile], selectedTag: String, routeMode: RouteMode) throws -> String {
        let target = selectedTag == AppConstants.autoTag ? "auto" : selectedTag
        let root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "experimental": ["cache_file": ["enabled": true]],
            "dns": buildDNS(routeMode: routeMode, target: target),
            "inbounds": buildInbounds(),
            "outbounds": try buildOutbounds(nodes: nodes, target: target),
            "route": buildRoute(routeMode: routeMode, target: target)
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func buildDNS(routeMode: RouteMode, target: String) -> [String: Any] {
        var rules: [[String: Any]] = [
            [
                "domain_suffix": [".onion"],
                "action": "route",
                "server": "fakeip",
                "disable_cache": true
            ]
        ]
        if routeMode == .rule {
            rules.append(["rule_set": "geosite-geolocation-cn", "action": "route", "server": "local"])
            rules.append(["rule_set": "geosite-geolocation-!cn", "action": "route", "server": "fakeip"])
            rules.append([
                "type": "logical",
                "mode": "and",
                "rules": [
                    ["rule_set": "geosite-geolocation-!cn", "invert": true],
                    ["rule_set": "geoip-cn"]
                ],
                "action": "route",
                "server": "local"
            ])
        }
        return [
            "servers": [
                ["tag": "fakeip", "type": "fakeip", "inet4_range": fakeIPCIDR],
                ["tag": "google", "type": "tls", "server": "8.8.8.8", "detour": target],
                ["tag": "local", "type": "udp", "server": "223.5.5.5"]
            ],
            "rules": rules,
            "final": "local",
            "strategy": "ipv4_only",
            "reverse_mapping": true
        ]
    }

    private static func buildInbounds() -> [[String: Any]] {
        [
            [
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30"],
                "auto_route": true,
                "strict_route": false,
                "stack": "gvisor",
                "mtu": 1500
            ],
            [
                "type": "mixed",
                "tag": "check-in",
                "listen": "127.0.0.1",
                "listen_port": AppConstants.proxyPort
            ]
        ]
    }

    private static func buildOutbounds(nodes: [NodeProfile], target: String) throws -> [[String: Any]] {
        var outbounds: [[String: Any]] = []
        var outboundTags: [String] = []
        for node in nodes {
            guard target == "auto" || node.tag == target else {
                continue
            }
            var outbound = node.outbound
            outbound["domain_resolver"] = "local"
            outbounds.append(outbound)
            outboundTags.append(node.tag)
        }
        guard !outboundTags.isEmpty else {
            throw ConfigError.selectedNodeNotFound
        }
        if target == "auto" {
            outbounds.append([
                "type": "urltest",
                "tag": "auto",
                "outbounds": outboundTags,
                "url": "https://www.gstatic.com/generate_204",
                "interval": "3m",
                "tolerance": 50,
                "interrupt_exist_connections": true
            ])
        }
        outbounds.append(["type": "direct", "tag": "direct"])
        return outbounds
    }

    private static func buildRoute(routeMode: RouteMode, target: String) -> [String: Any] {
        var routeRules: [[String: Any]] = [
            ["inbound": "check-in", "action": "route", "outbound": target],
            ["inbound": "tun-in", "port": 53, "action": "hijack-dns"],
            ["inbound": "tun-in", "port": 853, "action": "reject"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["domain_suffix": [".onion"], "action": "route", "outbound": target],
            ["ip_cidr": [fakeIPCIDR], "action": "route", "outbound": target]
        ]
        var ruleSets: [[String: Any]] = []
        if routeMode == .rule {
            routeRules.append(["ip_is_private": true, "action": "route", "outbound": "direct"])
            routeRules.append([
                "type": "logical",
                "mode": "or",
                "rules": [
                    ["network": "udp", "port": 443],
                    ["protocol": "stun"]
                ],
                "action": "reject"
            ])
            routeRules.append(["rule_set": "geosite-geolocation-cn", "action": "route", "outbound": "direct"])
            routeRules.append([
                "type": "logical",
                "mode": "and",
                "rules": [
                    ["rule_set": "geoip-cn"],
                    ["rule_set": "geosite-geolocation-!cn", "invert": true]
                ],
                "action": "route",
                "outbound": "direct"
            ])
            ruleSets = [
                ruleSet("geoip-cn", fileName: "geoip-cn"),
                ruleSet("geosite-geolocation-cn", fileName: "geosite-geolocation-cn"),
                ruleSet("geosite-geolocation-!cn", fileName: "geosite-geolocation-not-cn")
            ]
        }
        routeRules.append(["action": "sniff"])
        return [
            "rules": routeRules,
            "rule_set": ruleSets,
            "final": target,
            "default_domain_resolver": "local"
        ]
    }

    private static func ruleSet(_ tag: String, fileName: String) -> [String: Any] {
        let path = Bundle.main.path(forResource: fileName, ofType: "srs", inDirectory: "rules") ?? "\(fileName).srs"
        return [
            "type": "local",
            "tag": tag,
            "format": "binary",
            "path": path
        ]
    }

    enum ConfigError: Error {
        case selectedNodeNotFound
    }
}
