import Foundation

struct Addon: Codable, Identifiable, Equatable {
    let transportUrl: String
    let manifest: AddonManifest
    var flags: AddonFlags?

    var id: String { manifest.id + "|" + transportUrl }

    var displayName: String { manifest.name }
}

struct AddonFlags: Codable, Equatable {
    var official: Bool?
    var protected: Bool?
}

struct AddonManifest: Codable, Equatable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let background: String?
    let contactEmail: String?
    let types: [String]?
    let resources: [AddonResource]?
    let catalogs: [AddonCatalogDef]?
    let idPrefixes: [String]?
    let behaviorHints: AddonBehaviorHints?
}

struct AddonBehaviorHints: Codable, Equatable {
    var adult: Bool?
    var p2p: Bool?
    var configurable: Bool?
    var configurationRequired: Bool?
}

enum AddonResource: Codable, Equatable {
    case named(String)
    case detailed(AddonResourceDef)

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self = .named(string)
        } else {
            self = .detailed(try AddonResourceDef(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .named(let string): try container.encode(string)
        case .detailed(let def): try container.encode(def)
        }
    }

    var typeName: String {
        switch self {
        case .named(let s): return s
        case .detailed(let d): return d.name
        }
    }
}

struct AddonResourceDef: Codable, Equatable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

struct AddonCatalogDef: Codable, Equatable {
    let type: String
    let id: String
    let name: String?
    let extra: [AddonCatalogExtra]?
}

struct AddonCatalogExtra: Codable, Equatable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
}

struct AddonCollectionResult: Decodable {
    let addons: [Addon]

    private enum CodingKeys: String, CodingKey {
        case addons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addons = try container.decode(LossyArray<Addon>.self, forKey: .addons).elements
    }
}
