import Foundation

enum FlagUtil {
    private static let nameToCode: [String: String] = [
        "united states": "us",
        "united kingdom": "gb",
        "hong kong": "hk",
        "taiwan": "tw",
        "japan": "jp",
        "singapore": "sg",
        "germany": "de",
        "malaysia": "my",
        "korea": "kr",
        "south korea": "kr",
        "canada": "ca",
        "france": "fr",
        "netherlands": "nl",
        "australia": "au",
        "india": "in",
        "russia": "ru",
        "turkey": "tr",
        "thailand": "th",
        "vietnam": "vn",
        "philippines": "ph",
        "indonesia": "id",
        "brazil": "br",
        "mexico": "mx",
        "italy": "it",
        "spain": "es",
        "switzerland": "ch",
        "poland": "pl",
        "sweden": "se",
        "norway": "no",
        "finland": "fi",
        "ireland": "ie",
        "ukraine": "ua",
        "israel": "il",
        "united arab emirates": "ae"
    ]

    static func code(fromName name: String) -> String? {
        if let code = codeFromEmojiPrefix(name) {
            return code
        }
        let lower = name.lowercased()
        return nameToCode.first { lower.contains($0.key) }?.value
    }

    static func stripFlagPrefix(_ name: String) -> String {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2, isRegional(scalars[0]), isRegional(scalars[1]) else {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(String.UnicodeScalarView(scalars.dropFirst(2))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func emoji(fromCode code: String?) -> String {
        guard var normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !normalized.isEmpty else {
            return ""
        }
        if normalized == "uk" {
            normalized = "gb"
        }
        guard normalized.count == 2 else {
            return ""
        }
        let scalars = normalized.unicodeScalars.map { $0.value }
        guard scalars.count == 2, scalars.allSatisfy({ $0 >= 97 && $0 <= 122 }) else {
            return ""
        }
        let base: UInt32 = 0x1F1E6
        let first = UnicodeScalar(base + scalars[0] - 97)!
        let second = UnicodeScalar(base + scalars[1] - 97)!
        return String(first) + String(second)
    }

    private static func codeFromEmojiPrefix(_ name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2, isRegional(scalars[0]), isRegional(scalars[1]) else {
            return nil
        }
        let base: UInt32 = 97
        let first = UnicodeScalar(base + scalars[0].value - 0x1F1E6)!
        let second = UnicodeScalar(base + scalars[1].value - 0x1F1E6)!
        return String(first) + String(second)
    }

    private static func isRegional(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 0x1F1E6 && scalar.value <= 0x1F1FF
    }
}
