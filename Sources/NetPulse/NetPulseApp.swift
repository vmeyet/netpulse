import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct NetPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tester = SpeedTester()
    @StateObject private var monitor = StatusMonitor()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(tester: tester, monitor: monitor)
        } label: {
            if tester.isRunning || tester.mbps > 0 {
                Text("\(Int(tester.mbps)) Mbps")
            } else {
                Image(systemName: "speedometer")
            }
        }
        // .window runs a real SwiftUI view and lets us detect open/close.
        .menuBarExtraStyle(.window)
    }
}

struct DropdownView: View {
    @ObservedObject var tester: SpeedTester
    @ObservedObject var monitor: StatusMonitor

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "speedometer")
                Text("Internet Speed").font(.headline)
                Spacer()
            }

            VStack(spacing: 2) {
                Text(String(format: "%.1f", tester.mbps))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Mbps  ·  download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Scaled against peak so the bar stays lively on any link.
            ProgressView(value: min(tester.mbps, max(tester.peakMbps, 1)),
                         total: max(tester.peakMbps, 1))
                .tint(.green)

            HStack {
                Label(String(format: "peak %.0f", tester.peakMbps), systemImage: "arrow.up.forward")
                Spacer()
                Label(String(format: "%.0f MB", Double(tester.bytesDownloaded) / 1_000_000),
                      systemImage: "arrow.down.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ServicesSection(monitor: monitor)

            Divider()

            HStack {
                if tester.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Testing…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Stopped").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            tester.start()
            Task { await monitor.refresh() }
        }
        .onDisappear { tester.stop() }
    }
}
