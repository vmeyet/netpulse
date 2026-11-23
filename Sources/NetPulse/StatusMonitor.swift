import Foundation

@MainActor
final class StatusMonitor: ObservableObject {
    @Published private(set) var services: [Service] = ServiceCatalog.load()
    @Published private(set) var health: [URL: Health] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAdding = false
    @Published var addFailure: String?

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: (URL, Health).self) { group in
            for service in services {
                group.addTask { (service.id, await StatusProbe.health(of: service)) }
            }
            for await (id, result) in group { health[id] = result }
        }
    }

    func add(_ typedLink: String) async -> Bool {
        guard !isAdding else { return false }
        guard let link = Self.normalized(typedLink) else {
            addFailure = "That doesn't look like a URL."
            return false
        }

        isAdding = true
        addFailure = nil
        defer { isAdding = false }

        do {
            let service = try await StatusProbe.detect(link)
            guard !services.contains(where: { $0.id == service.id }) else {
                addFailure = "\(service.name) is already in the list."
                return false
            }
            services.append(service)
            ServiceCatalog.save(services)
            health[service.id] = await StatusProbe.health(of: service)
            return true
        } catch {
            addFailure = error.localizedDescription
            return false
        }
    }

    func remove(_ service: Service) {
        services.removeAll { $0.id == service.id }
        health[service.id] = nil
        ServiceCatalog.save(services)
    }

    nonisolated static func normalized(_ typed: String) -> URL? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let absolute = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: absolute), url.host != nil else { return nil }
        return url
    }
}
