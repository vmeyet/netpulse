import Foundation

enum ProviderKind: String, Codable, Sendable {
    case statuspage
    case statusio
    case instatus
    case slack
    case googleCloud
}

struct Service: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let site: URL
    let statusPage: URL
    let provider: ProviderKind
    let endpoint: URL

    var id: URL { endpoint }
}

enum Health: String, Sendable {
    case ok
    case degraded
    case down
    case unknown
}

/// Services live in a hand-editable JSON file so they can be changed
/// without the app, and are written back whenever the UI edits them.
enum ServiceCatalog {
    static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".config/netpulse/services.json")

    static func load() -> [Service] {
        guard let data = try? Data(contentsOf: fileURL) else {
            save(defaults)
            return defaults
        }
        guard let stored = try? JSONDecoder().decode([Service].self, from: data) else {
            setBrokenFileAside()
            return defaults
        }
        return stored
    }

    private static func setBrokenFileAside() {
        let brokenURL = fileURL.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: brokenURL)
        try? FileManager.default.moveItem(at: fileURL, to: brokenURL)
    }

    static func save(_ services: [Service]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(services) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let defaults: [Service] = [
        Service(name: "GitLab",
                site: URL(string: "https://gitlab.com")!,
                statusPage: URL(string: "https://status.gitlab.com")!,
                provider: .statusio,
                endpoint: URL(string: "https://api.status.io/1.0/status/5b36dc6502d06804c08349f7")!),
        Service(name: "Sentry",
                site: URL(string: "https://sentry.io")!,
                statusPage: URL(string: "https://status.sentry.io")!,
                provider: .statuspage,
                endpoint: URL(string: "https://status.sentry.io/api/v2/status.json")!),
        Service(name: "Claude",
                site: URL(string: "https://claude.com")!,
                statusPage: URL(string: "https://status.claude.com")!,
                provider: .statuspage,
                endpoint: URL(string: "https://status.claude.com/api/v2/status.json")!),
        Service(name: "Slack",
                site: URL(string: "https://slack.com")!,
                statusPage: URL(string: "https://slack-status.com")!,
                provider: .slack,
                endpoint: URL(string: "https://slack-status.com/api/v2.0.0/current")!),
        Service(name: "Google Cloud",
                site: URL(string: "https://cloud.google.com")!,
                statusPage: URL(string: "https://status.cloud.google.com")!,
                provider: .googleCloud,
                endpoint: URL(string: "https://status.cloud.google.com/incidents.json")!),
    ]
}
