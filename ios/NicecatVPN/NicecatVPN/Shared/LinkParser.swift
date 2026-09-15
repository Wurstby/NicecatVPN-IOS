import Foundation

enum LinkParser {
    private static let supportedSchemes = [
        "vmess://", "vless://", "trojan://", "ss://", "anytls://",
        "hy2://", "hysteria2://", "socks://", "socks5://", "socks4://",
        "socks4a://", "http://", "https://"
    ]

    static func parseLinks(_ text: String) -> [NodeProfile] {
        var nodes: [NodeProfile] = []
        var index = 1
        for rawLine in text.components(separatedBy: .newlines) {
            let link = normalizeShareLine(rawLine)
            guard !link.isEmpty else {
                continue
            }
            if let node = try? parseNode(link, index: index), !node.server.isEmpty, node.port > 0 {
                nodes.append(node)
                index += 1
            }
        }
        return nodes
    }

    private static func normalizeShareLine(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\u{feff}") {
            value = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty else {
            return ""
        }
        let lower = value.lowercased()
        if supportedSchemes.contains(where: { lower.hasPrefix($0) }) {
            return value
        }
        let best = supportedSchemes.compactMap { lower.range(of: $0)?.lowerBound }.min()
        guard let best else {
            return value
        }
        return String(value[best...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseNode(_ link: String, index: Int) throws -> NodeProfile {
        let lower = link.lowercased()
        if lower.hasPrefix("vmess://") {
            return try parseVmess(link, index: index)
        }
        if lower.hasPrefix("vless://") {
            return try parseVless(link, index: index)
        }
        if lower.hasPrefix("trojan://") {
            return try parseTrojan(link, index: index)
        }
        if lower.hasPrefix("ss://") {
            return try parseShadowsocks(link, index: index)
        }
        if lower.hasPrefix("anytls://") {
            return try parseAnyTLS(link, index: index)
        }
        if lower.hasPrefix("hy2://") {
            return try parseHysteria2(link, index: index, prefix: "hy2://")
        }
        if lower.hasPrefix("hysteria2://") {
            return try parseHysteria2(link, index: index, prefix: "hysteria2://")
        }
        if lower.hasPrefix("socks://") {
            return parseSocks(link, index: index, prefix: "socks://", defaultVersion: "5")
        }
        if lower.hasPrefix("socks5://") {
            return parseSocks(link, index: index, prefix: "socks5://", defaultVersion: "5")
        }
        if lower.hasPrefix("socks4://") {
            return parseSocks(link, index: index, prefix: "socks4://", defaultVersion: "4")
        }
        if lower.hasPrefix("socks4a://") {
            return parseSocks(link, index: index, prefix: "socks4a://", defaultVersion: "4a")
        }
        if lower.hasPrefix("http://") {
            return try parseHTTPProxy(link, index: index, prefix: "http://", tlsByScheme: false)
        }
        if lower.hasPrefix("https://") {
            return try parseHTTPProxy(link, index: index, prefix: "https://", tlsByScheme: true)
        }
        throw ParserError.unsupported
    }

    private static func parseVmess(_ link: String, index: Int) throws -> NodeProfile {
        let body = String(link.dropFirst("vmess://".count))
        guard let data = decodeBase64Text(body).data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParserError.invalid
        }
        let tag = "node-\(index)"
        let rawName = string(json["ps"]) ?? string(json["name"]) ?? "VMess \(index)"
        let name = FlagUtil.stripFlagPrefix(rawName)
        let server = string(json["add"]) ?? ""
        let port = parsePort(string(json["port"]), fallback: 443)
        var outbound: [String: Any] = [
            "type": "vmess",
            "tag": tag,
            "server": server,
            "server_port": port,
            "uuid": string(json["id"]) ?? "",
            "security": string(json["scy"]) ?? "auto",
            "alter_id": parsePort(string(json["aid"]), fallback: 0)
        ]
        let tls = string(json["tls"]) ?? ""
        let security = string(json["security"]) ?? ""
        if ["tls", "true", "1"].contains(tls.lowercased()) || security.lowercased() == "tls" {
            outbound["tls"] = buildTLS(server: server, query: [
                "servername": string(json["sni"]) ?? string(json["host"]) ?? ""
            ])
        }
        if let transport = try buildVmessTransport(json) {
            outbound["transport"] = transport
        }
        return NodeProfile(name: name, tag: tag, link: link, server: server, port: port, proto: "vmess", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseVless(_ link: String, index: Int) throws -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: "vless://", defaultPort: 443)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "VLESS \(index)"
        let server = share.host
        var outbound: [String: Any] = [
            "type": "vless",
            "tag": tag,
            "server": server,
            "server_port": share.port,
            "uuid": percentDecode(share.userInfo),
            "packet_encoding": "xudp"
        ]
        if let flow = query["flow"], !flow.isEmpty {
            outbound["flow"] = flow
        }
        if query["security"] == "tls" || query["security"] == "reality" {
            outbound["tls"] = buildTLS(server: server, query: query)
        }
        if let transport = try buildV2RayTransport(query) {
            outbound["transport"] = transport
        }
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: server, port: share.port, proto: "vless", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseTrojan(_ link: String, index: Int) throws -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: "trojan://", defaultPort: 443)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "Trojan \(index)"
        var outbound: [String: Any] = [
            "type": "trojan",
            "tag": tag,
            "server": share.host,
            "server_port": share.port,
            "password": percentDecode(share.userInfo)
        ]
        if (query["security"] ?? "tls") != "none" {
            outbound["tls"] = buildTLS(server: share.host, query: query)
        }
        if let transport = try buildV2RayTransport(query) {
            outbound["transport"] = transport
        }
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: share.host, port: share.port, proto: "trojan", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseShadowsocks(_ link: String, index: Int) throws -> NodeProfile {
        let tag = "node-\(index)"
        let rawName = percentDecode(fragmentOf(link)).nilIfEmpty ?? "Shadowsocks \(index)"
        var body = String(link.dropFirst("ss://".count))
        if let fragment = body.firstIndex(of: "#") {
            body = String(body[..<fragment])
        }
        if let query = body.firstIndex(of: "?") {
            body = String(body[..<query])
        }
        let userInfo: String
        let server: String
        let port: Int
        if let at = body.lastIndex(of: "@") {
            var decodedUser = percentDecode(String(body[..<at]))
            let address = String(body[body.index(after: at)...])
            let parts = splitHostPort(address, defaultPort: 443)
            server = parts.host
            port = parts.port
            if !decodedUser.contains(":") {
                decodedUser = decodeBase64Text(decodedUser)
            }
            userInfo = decodedUser
        } else {
            let decoded = decodeBase64Text(body)
            let pieces = decoded.split(separator: "@", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else {
                throw ParserError.invalid
            }
            userInfo = pieces[0]
            let parts = splitHostPort(pieces[1], defaultPort: 443)
            server = parts.host
            port = parts.port
        }
        let methodPassword = userInfo.split(separator: ":", maxSplits: 1).map(String.init)
        let outbound: [String: Any] = [
            "type": "shadowsocks",
            "tag": tag,
            "server": server,
            "server_port": port,
            "method": methodPassword.first ?? "",
            "password": methodPassword.count > 1 ? methodPassword[1] : ""
        ]
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: server, port: port, proto: "ss", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseAnyTLS(_ link: String, index: Int) throws -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: "anytls://", defaultPort: 443)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "AnyTLS \(index)"
        let outbound: [String: Any] = [
            "type": "anytls",
            "tag": tag,
            "server": share.host,
            "server_port": share.port,
            "password": percentDecode(share.userInfo),
            "tls": buildTLS(server: share.host, query: query)
        ]
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: share.host, port: share.port, proto: "anytls", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseHysteria2(_ link: String, index: Int, prefix: String) throws -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: prefix, defaultPort: 443)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "Hysteria2 \(index)"
        var outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": tag,
            "server": share.host,
            "server_port": share.port,
            "password": percentDecode(share.userInfo).nilIfEmpty ?? first(query, fallback: "", keys: "auth", "password"),
            "tls": buildTLS(server: share.host, query: query)
        ]
        putPositiveInt(&outbound, key: "up_mbps", value: first(query, fallback: "", keys: "up_mbps", "upmbps", "up"))
        putPositiveInt(&outbound, key: "down_mbps", value: first(query, fallback: "", keys: "down_mbps", "downmbps", "down"))
        let obfsType = first(query, fallback: "", keys: "obfs", "obfs_type", "obfs-type")
        let obfsPassword = first(query, fallback: "", keys: "obfs-password", "obfs_password", "obfsPassword", "obfs-param", "obfsParam")
        if !obfsType.isEmpty || !obfsPassword.isEmpty {
            outbound["obfs"] = [
                "type": ["gecko", "salamander"].contains(obfsType) ? obfsType : "salamander",
                "password": obfsPassword
            ]
        }
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: share.host, port: share.port, proto: "hy2", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseSocks(_ link: String, index: Int, prefix: String, defaultVersion: String) -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: prefix, defaultPort: 1080)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "SOCKS \(index)"
        let auth = userPassword(share.userInfo)
        var outbound: [String: Any] = [
            "type": "socks",
            "tag": tag,
            "server": share.host,
            "server_port": share.port,
            "version": first(query, fallback: defaultVersion, keys: "version")
        ]
        if !auth.username.isEmpty {
            outbound["username"] = auth.username
        }
        if !auth.password.isEmpty {
            outbound["password"] = auth.password
        }
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: share.host, port: share.port, proto: "socks", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func parseHTTPProxy(_ link: String, index: Int, prefix: String, tlsByScheme: Bool) throws -> NodeProfile {
        let share = parseAuthorityShare(link, prefix: prefix, defaultPort: tlsByScheme ? 443 : 8080)
        let query = queryMap(share.query)
        let tag = "node-\(index)"
        let rawName = percentDecode(share.fragment).nilIfEmpty ?? "HTTP \(index)"
        let auth = userPassword(share.userInfo)
        var outbound: [String: Any] = [
            "type": "http",
            "tag": tag,
            "server": share.host,
            "server_port": share.port
        ]
        if !auth.username.isEmpty {
            outbound["username"] = auth.username
        }
        if !auth.password.isEmpty {
            outbound["password"] = auth.password
        }
        if let path = query["path"], !path.isEmpty {
            outbound["path"] = path
        }
        let tls = first(query, fallback: "", keys: "tls", "security")
        if tlsByScheme || ["1", "true", "tls"].contains(tls.lowercased()) {
            outbound["tls"] = buildTLS(server: share.host, query: query)
        }
        return NodeProfile(name: FlagUtil.stripFlagPrefix(rawName), tag: tag, link: link, server: share.host, port: share.port, proto: "http", flagCode: FlagUtil.code(fromName: rawName), outbound: outbound)
    }

    private static func buildTLS(server: String, query: [String: String]) -> [String: Any] {
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": first(query, fallback: server, keys: "servername", "sni", "peer")
        ]
        let fingerprint = first(query, fallback: "", keys: "fp", "fingerprint")
        if !fingerprint.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fingerprint]
        }
        if query["security"] == "reality" || query["pbk"] != nil {
            tls["reality"] = [
                "enabled": true,
                "public_key": first(query, fallback: "", keys: "pbk", "publicKey"),
                "short_id": first(query, fallback: "", keys: "sid", "shortId")
            ]
        }
        let allowInsecure = first(query, fallback: "", keys: "allowInsecure", "insecure")
        if allowInsecure == "1" || allowInsecure.lowercased() == "true" {
            tls["insecure"] = true
        }
        return tls
    }

    private static func buildVmessTransport(_ info: [String: Any]) throws -> [String: Any]? {
        let network = string(info["net"]) ?? "tcp"
        if network == "tcp" || network == "raw" || network.isEmpty {
            return nil
        }
        if network == "kcp" || network == "mkcp" {
            throw ParserError.unsupported
        }
        if network == "ws" {
            var transport: [String: Any] = ["type": "ws", "path": string(info["path"]) ?? "/"]
            if let host = string(info["host"]), !host.isEmpty {
                transport["headers"] = ["Host": host]
            }
            return transport
        }
        if network == "grpc" {
            return ["type": "grpc", "service_name": string(info["path"]) ?? ""]
        }
        if network == "xhttp" || network == "splithttp" {
            return buildXHTTPTransport(info.mapValues { "\($0)" })
        }
        return ["type": network]
    }

    private static func buildV2RayTransport(_ query: [String: String]) throws -> [String: Any]? {
        let type = query["type"] ?? query["net"] ?? ""
        if type.isEmpty || type == "tcp" || type == "raw" {
            return nil
        }
        if type == "kcp" || type == "mkcp" {
            throw ParserError.unsupported
        }
        if type == "ws" {
            var transport: [String: Any] = ["type": "ws", "path": first(query, fallback: "/", keys: "path")]
            let host = first(query, fallback: "", keys: "host")
            if !host.isEmpty {
                transport["headers"] = ["Host": host]
            }
            return transport
        }
        if type == "grpc" {
            return ["type": "grpc", "service_name": first(query, fallback: "", keys: "serviceName", "path")]
        }
        if type == "httpupgrade" {
            return ["type": "httpupgrade", "path": first(query, fallback: "/", keys: "path"), "host": first(query, fallback: "", keys: "host")]
        }
        if type == "xhttp" || type == "splithttp" {
            return buildXHTTPTransport(query)
        }
        return ["type": type]
    }

    private static func buildXHTTPTransport(_ values: [String: String]) -> [String: Any] {
        var transport: [String: Any] = ["type": "xhttp", "mode": first(values, fallback: "auto", keys: "mode")]
        let path = first(values, fallback: "", keys: "path")
        if !path.isEmpty {
            transport["path"] = path
        }
        let host = first(values, fallback: "", keys: "host", "authority")
        if !host.isEmpty {
            transport["host"] = host
        }
        guard let rawExtra = values["extra"], let data = rawExtra.data(using: .utf8),
              let extra = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return transport
        }
        let keyMap = [
            "headers": "headers",
            "xPaddingBytes": "x_padding_bytes",
            "x_padding_bytes": "x_padding_bytes",
            "scMaxConcurrentPosts": "sc_max_concurrent_posts",
            "sc_max_concurrent_posts": "sc_max_concurrent_posts",
            "scMaxBufferedPosts": "sc_max_buffered_posts",
            "sc_max_buffered_posts": "sc_max_buffered_posts",
            "scStreamUpServerSecs": "sc_stream_up_server_secs",
            "sc_stream_up_server_secs": "sc_stream_up_server_secs",
            "noSSEHeader": "no_sse_header",
            "no_sse_header": "no_sse_header",
            "xPaddingObfsMode": "x_padding_obfs_mode",
            "x_padding_obfs_mode": "x_padding_obfs_mode",
            "xPaddingPlacement": "x_padding_placement",
            "x_padding_placement": "x_padding_placement",
            "xPaddingKey": "x_padding_key",
            "x_padding_key": "x_padding_key",
            "xPaddingHeader": "x_padding_header",
            "x_padding_header": "x_padding_header",
            "xPaddingMethod": "x_padding_method",
            "x_padding_method": "x_padding_method"
        ]
        for (source, target) in keyMap where extra[source] != nil {
            transport[target] = extra[source]
        }
        return transport
    }

    private static func queryMap(_ rawQuery: String) -> [String: String] {
        guard !rawQuery.isEmpty else {
            return [:]
        }
        var map: [String: String] = [:]
        for part in rawQuery.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let key = percentDecode(pieces[0])
            let value = pieces.count > 1 ? percentDecode(pieces[1]) : ""
            map[key] = value
        }
        return map
    }

    private static func parseAuthorityShare(_ link: String, prefix: String, defaultPort: Int) -> ParsedShare {
        var body = String(link.dropFirst(prefix.count))
        var fragment = ""
        if let fragmentIndex = body.firstIndex(of: "#") {
            fragment = String(body[body.index(after: fragmentIndex)...])
            body = String(body[..<fragmentIndex])
        }
        var query = ""
        if let queryIndex = body.firstIndex(of: "?") {
            query = String(body[body.index(after: queryIndex)...])
            body = String(body[..<queryIndex])
        }
        if let slash = body.firstIndex(of: "/") {
            body = String(body[..<slash])
        }
        let at = body.lastIndex(of: "@")
        let userInfo = at.map { String(body[..<$0]) } ?? ""
        let hostPort = at.map { String(body[body.index(after: $0)...]) } ?? body
        let split = splitHostPort(hostPort, defaultPort: defaultPort)
        return ParsedShare(userInfo: userInfo, host: split.host, port: split.port, query: query, fragment: fragment)
    }

    private static func splitHostPort(_ hostPort: String, defaultPort: Int) -> (host: String, port: Int) {
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            let host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            let rest = hostPort[hostPort.index(after: close)...]
            if rest.hasPrefix(":") {
                return (host, parsePort(String(rest.dropFirst()), fallback: defaultPort))
            }
            return (host, defaultPort)
        }
        guard let colon = hostPort.lastIndex(of: ":") else {
            return (hostPort, defaultPort)
        }
        return (String(hostPort[..<colon]), parsePort(String(hostPort[hostPort.index(after: colon)...]), fallback: defaultPort))
    }

    private static func fragmentOf(_ link: String) -> String {
        guard let index = link.firstIndex(of: "#") else {
            return ""
        }
        return String(link[link.index(after: index)...])
    }

    private static func first(_ query: [String: String], fallback: String, keys: String...) -> String {
        for key in keys {
            if let value = query[key], !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func putPositiveInt(_ object: inout [String: Any], key: String, value: String) {
        let parsed = parsePort(value, fallback: -1)
        if parsed > 0 {
            object[key] = parsed
        }
    }

    private static func parsePort(_ value: String?, fallback: Int) -> Int {
        guard let value, let port = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return fallback
        }
        return port
    }

    private static func percentDecode(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func decodeBase64Text(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        while normalized.count % 4 != 0 {
            normalized += "="
        }
        guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) ??
            Data(base64Encoded: normalized.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"), options: [.ignoreUnknownCharacters]) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func userPassword(_ userInfo: String) -> (username: String, password: String) {
        let decoded = percentDecode(userInfo)
        guard let colon = decoded.firstIndex(of: ":") else {
            return (decoded, "")
        }
        return (String(decoded[..<colon]), String(decoded[decoded.index(after: colon)...]))
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private struct ParsedShare {
        let userInfo: String
        let host: String
        let port: Int
        let query: String
        let fragment: String
    }

    private enum ParserError: Error {
        case invalid
        case unsupported
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
