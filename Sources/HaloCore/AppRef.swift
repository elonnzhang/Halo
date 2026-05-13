import Foundation

public struct AppRef: Hashable, Sendable, Codable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct UsageRecord: Hashable, Sendable, Codable {
    public let app: AppRef
    public let activations: Int
    public let lastUsed: Date

    public init(app: AppRef, activations: Int, lastUsed: Date) {
        self.app = app
        self.activations = activations
        self.lastUsed = lastUsed
    }
}
