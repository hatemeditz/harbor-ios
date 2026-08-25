import Foundation

struct StremioUser: Codable, Equatable {
    let id: String
    let email: String
    let fullname: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email
        case fullname
        case avatar
    }

    var displayName: String {
        if let fullname, !fullname.isEmpty { return fullname }
        return email.split(separator: "@").first.map(String.init) ?? email
    }
}

struct LoginResponse: Codable {
    let authKey: String
    let user: StremioUser
}
