import SwiftUI
import ServiceManagement
import Combine
import AppKit

@main
struct TopCPUApp: App {
    @StateObject private var monitor = CPUMonitor()
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(monitor: monitor, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarIconView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIconView: View {
    @ObservedObject var monitor: CPUMonitor

    var body: some View {
        Image(systemName: "waveform.path.ecg.rectangle.fill")
            .font(.system(size: 20, weight: .semibold))
            .imageScale(.large)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(monitor.isThresholdExceeded ? .orange : .primary)
            .symbolEffect(.rotate.byLayer, value: monitor.isThresholdExceeded)
            .animation(.smooth(duration: 0.25), value: monitor.isThresholdExceeded)
    }
}

private struct MenuPanelView: View {
    @ObservedObject var monitor: CPUMonitor
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        VStack(spacing: 10) {
            header

            Divider()

            if monitor.topProcesses.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                ForEach(monitor.topProcesses) { process in
                    ProcessRow(process: process)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12, weight: .regular))

                Spacer(minLength: 8)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }

            if let errorMessage = launchAtLogin.lastErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Top CPU Processes")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                openActivityMonitor()
            } label: {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Open Activity Monitor")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessCPU

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .foregroundStyle(process.percentColor)

            Text(process.name)
                .font(.system(size: 12.5, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(process.percentText)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(process.percentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MenuPanelView(
        monitor: CPUMonitor(
            topProcesses: [
                ProcessCPU(pid: 100, name: "Xcode", cpuPercent: 72.4),
                ProcessCPU(pid: 101, name: "Google Chrome Helper", cpuPercent: 47.1),
                ProcessCPU(pid: 102, name: "WindowServer", cpuPercent: 18.6)
            ],
            sampleInterval: 5.0,
            cpuThresholdPercent: 85,
            sustainedThresholdDuration: 10,
            startsSampling: false
        ),
        launchAtLogin: LaunchAtLoginManager()
    )
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastErrorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = (service.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastErrorMessage = nil
            refresh()
        } catch {
            lastErrorMessage = "Couldn’t update launch setting. Check login items permissions."
            refresh()
        }
    }
}
