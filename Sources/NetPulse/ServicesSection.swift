import SwiftUI

struct ServicesSection: View {
    @ObservedObject var monitor: StatusMonitor
    @State private var isAdding = false
    @State private var draftLink = ""
    @FocusState private var isDraftFocused: Bool

    private let visibleRowLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if monitor.services.isEmpty {
                Text("No services yet — add a status page URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if monitor.services.count > visibleRowLimit {
                ScrollView { rows }
                    .frame(height: CGFloat(visibleRowLimit) * 24)
            } else {
                rows
            }

            if isAdding { addField }

            if let failure = monitor.addFailure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Services").font(.headline)
            if monitor.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            Button {
                toggleAddField()
            } label: {
                Image(systemName: isAdding ? "xmark" : "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(isAdding ? "Cancel" : "Add a service")
        }
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(monitor.services) { service in
                ServiceRow(service: service,
                           health: monitor.health[service.id] ?? .unknown,
                           onRemove: { monitor.remove(service) })
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            TextField("Paste a status page URL", text: $draftLink)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($isDraftFocused)
                .onSubmit { submitDraft() }
            if monitor.isAdding {
                ProgressView().controlSize(.mini)
            } else {
                Button("Add") { submitDraft() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(draftLink.isEmpty)
            }
        }
    }

    private func toggleAddField() {
        isAdding.toggle()
        monitor.addFailure = nil
        draftLink = ""
        isDraftFocused = isAdding
    }

    private func submitDraft() {
        let link = draftLink
        Task {
            guard await monitor.add(link) else { return }
            draftLink = ""
            isAdding = false
        }
    }
}

private struct ServiceRow: View {
    let service: Service
    let health: Health
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Favicon(host: service.site.host ?? "")
            Text(service.name)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(isHovered ? 1 : 0)
            .help("Remove \(service.name)")
            Circle()
                .fill(health.color)
                .frame(width: 8, height: 8)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { NSWorkspace.shared.open(service.statusPage) }
        .contextMenu {
            Button("Open \(service.name)") { NSWorkspace.shared.open(service.site) }
            Button("Remove", role: .destructive, action: onRemove)
        }
        .help("\(health.label) — click to open \(service.statusPage.host ?? service.name)")
    }
}

private struct Favicon: View {
    let host: String

    var body: some View {
        AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            Image(systemName: "globe").foregroundStyle(.secondary)
        }
        .frame(width: 16, height: 16)
    }
}

private extension Health {
    var color: Color {
        switch self {
        case .ok: return .green
        case .degraded: return .orange
        case .down: return .red
        case .unknown: return .gray
        }
    }

    var label: String {
        switch self {
        case .ok: return "All systems operational"
        case .degraded: return "Degraded"
        case .down: return "Major outage"
        case .unknown: return "Status unavailable"
        }
    }
}
