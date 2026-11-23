import Foundation

enum ProbeError: LocalizedError {
    case unreachable
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Couldn't reach that page."
        case .unsupported: return "That status page isn't supported."
        }
    }
}

enum StatusProbe {
    static func detect(_ link: URL) async throws -> Service {
        guard let page = await resolvedPage(for: link) else { throw ProbeError.unreachable }

        if let service = bespokeService(for: page.url) { return service }
        if let service = await statuspageService(at: page.url) { return service }
        if let service = await statusioService(at: page) { return service }
        if let service = await instatusService(at: page.url) { return service }

        throw ProbeError.unsupported
    }

    static func health(of service: Service) async -> Health {
        guard let data = await get(service.endpoint) else { return .unknown }

        switch service.provider {
        case .statuspage: return statuspageHealth(from: data)
        case .statusio: return statusioHealth(from: data)
        case .instatus: return instatusHealth(from: data)
        case .slack: return slackHealth(from: data)
        case .googleCloud: return googleCloudHealth(from: data)
        }
    }

    // MARK: - Detection

    private struct ResolvedPage {
        let url: URL
        let statusPageID: String?
    }

    private static func resolvedPage(for link: URL) async -> ResolvedPage? {
        guard let (_, response) = try? await session.data(from: link),
              let http = response as? HTTPURLResponse,
              let final = http.url
        else { return nil }

        let id = http.value(forHTTPHeaderField: "x-status-page-id")
        return ResolvedPage(url: origin(of: final) ?? final, statusPageID: id)
    }

    private static func bespokeService(for page: URL) -> Service? {
        switch page.host {
        case "slack-status.com", "status.slack.com":
            return Service(name: "Slack",
                           site: URL(string: "https://slack.com")!,
                           statusPage: page,
                           provider: .slack,
                           endpoint: page.appending(path: "api/v2.0.0/current"))
        case "status.cloud.google.com":
            return Service(name: "Google Cloud",
                           site: URL(string: "https://cloud.google.com")!,
                           statusPage: page,
                           provider: .googleCloud,
                           endpoint: page.appending(path: "incidents.json"))
        default:
            return nil
        }
    }

    private static func statuspageService(at page: URL) async -> Service? {
        let endpoint = page.appending(path: "api/v2/status.json")
        guard let data = await get(endpoint),
              let payload = try? decoder.decode(StatuspagePayload.self, from: data)
        else { return nil }

        return service(named: payload.page.name, page: page, provider: .statuspage, endpoint: endpoint)
    }

    private static func statusioService(at page: ResolvedPage) async -> Service? {
        guard let id = page.statusPageID,
              let endpoint = URL(string: "https://api.status.io/1.0/status/\(id)"),
              let data = await get(endpoint),
              (try? decoder.decode(StatusioPayload.self, from: data)) != nil
        else { return nil }

        return service(named: nil, page: page.url, provider: .statusio, endpoint: endpoint)
    }

    private static func instatusService(at page: URL) async -> Service? {
        let endpoint = page.appending(path: "summary.json")
        guard let data = await get(endpoint),
              let payload = try? decoder.decode(InstatusPayload.self, from: data)
        else { return nil }

        return service(named: payload.page.name, page: page, provider: .instatus, endpoint: endpoint)
    }

    private static func service(named name: String?, page: URL, provider: ProviderKind, endpoint: URL) -> Service {
        let host = page.host ?? ""
        let site = productSite(forStatusHost: host) ?? page
        return Service(name: name ?? displayName(for: site),
                       site: site,
                       statusPage: page,
                       provider: provider,
                       endpoint: endpoint)
    }

    // MARK: - Health

    static func statuspageHealth(from data: Data) -> Health {
        guard let payload = try? decoder.decode(StatuspagePayload.self, from: data) else { return .unknown }
        switch payload.status.indicator {
        case "none": return .ok
        case "minor": return .degraded
        case "major", "critical": return .down
        default: return .unknown
        }
    }

    static func statusioHealth(from data: Data) -> Health {
        guard let payload = try? decoder.decode(StatusioPayload.self, from: data) else { return .unknown }
        switch payload.result.statusOverall.statusCode {
        case 100: return .ok
        case 200, 300, 400: return .degraded
        case 500, 600: return .down
        default: return .unknown
        }
    }

    static func instatusHealth(from data: Data) -> Health {
        guard let payload = try? decoder.decode(InstatusPayload.self, from: data) else { return .unknown }
        switch payload.page.status {
        case "UP": return .ok
        case "HASISSUES", "UNDERMAINTENANCE": return .degraded
        default: return .unknown
        }
    }

    static func slackHealth(from data: Data) -> Health {
        guard let payload = try? decoder.decode(SlackPayload.self, from: data) else { return .unknown }
        if payload.activeIncidents.isEmpty { return .ok }
        return payload.activeIncidents.contains { $0.type == "outage" } ? .down : .degraded
    }

    static func googleCloudHealth(from data: Data) -> Health {
        guard let incidents = try? decoder.decode([GoogleCloudIncident].self, from: data) else { return .unknown }
        let open = incidents.filter { $0.end == nil }
        if open.isEmpty { return .ok }
        return open.contains { $0.severity == "high" } ? .down : .degraded
    }

    // MARK: - Payloads

    private struct StatuspagePayload: Decodable {
        struct Page: Decodable { let name: String }
        struct Status: Decodable { let indicator: String }
        let page: Page
        let status: Status
    }

    private struct StatusioPayload: Decodable {
        struct Result: Decodable {
            struct Overall: Decodable { let statusCode: Int }
            let statusOverall: Overall
        }
        let result: Result
    }

    private struct InstatusPayload: Decodable {
        struct Page: Decodable {
            let name: String
            let status: String
        }
        let page: Page
    }

    private struct SlackPayload: Decodable {
        struct Incident: Decodable { let type: String }
        let activeIncidents: [Incident]
    }

    private struct GoogleCloudIncident: Decodable {
        let end: String?
        let severity: String
    }

    // MARK: - Plumbing

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func get(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    private static func origin(of url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    /// status.sentry.io → sentry.io, www.vercel-status.com → vercel.com,
    /// githubstatus.com → github.com. Best effort; the JSON stays editable.
    static func productSite(forStatusHost host: String) -> URL? {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return URL(string: "https://\(withoutStatusMarker(bare))")
    }

    static func withoutStatusMarker(_ host: String) -> String {
        if host.hasPrefix("status.") { return String(host.dropFirst("status.".count)) }
        if let marker = host.range(of: "-status.") { return host.replacingCharacters(in: marker, with: ".") }
        if let marker = host.range(of: "status.") { return host.replacingCharacters(in: marker, with: ".") }
        return host
    }

    private static func displayName(for site: URL) -> String {
        guard let label = site.host?.split(separator: ".").first else { return site.absoluteString }
        return label.capitalized
    }
}
