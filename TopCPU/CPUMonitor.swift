import AppKit
import Combine
import Foundation
import SwiftUI

struct ProcessCPU: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpuPercent: Double

    var id: Int32 { pid }

    var percentText: String {
        String(format: "%.1f%%", cpuPercent)
    }

    var percentColor: Color {
        switch cpuPercent {
        case 80...:
            return .red
        case 40...:
            return .orange
        default:
            return .secondary
        }
    }
}

@MainActor
final class CPUMonitor: ObservableObject {
    @Published var topProcesses: [ProcessCPU]
    let sampleInterval: TimeInterval
    @Published var isThresholdExceeded = false

    private let cpuThresholdPercent: Double
    private let sustainedThresholdDuration: TimeInterval
    private var consecutiveThresholdSamples: Int = 0
    private let sampler = ProcessCPUSampler()
    private var samplingTask: Task<Void, Never>?

    init(
        topProcesses: [ProcessCPU] = [],
        sampleInterval: TimeInterval = 5.0,
        cpuThresholdPercent: Double = 85,
        sustainedThresholdDuration: TimeInterval = 10,
        startsSampling: Bool = true
    ) {
        self.topProcesses = topProcesses
        self.sampleInterval = sampleInterval
        self.cpuThresholdPercent = cpuThresholdPercent
        self.sustainedThresholdDuration = sustainedThresholdDuration

        if startsSampling {
            startSampling()
        }
    }

    deinit {
        samplingTask?.cancel()
    }

    private func startSampling() {
        guard samplingTask == nil else { return }

        samplingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let top = await self.sampler.sampleTopProcesses(limit: 3)

                await MainActor.run {
                    self.apply(top)
                }

                try? await Task.sleep(for: .seconds(self.sampleInterval))
            }
        }
    }

    private func apply(_ top: [ProcessCPU]) {
        topProcesses = top

        guard let hottest = top.first else {
            consecutiveThresholdSamples = 0
            isThresholdExceeded = false
            return
        }

        if hottest.cpuPercent >= cpuThresholdPercent {
            consecutiveThresholdSamples += 1
        } else {
            consecutiveThresholdSamples = 0
        }

        let requiredSamples = max(1, Int(ceil(sustainedThresholdDuration / sampleInterval)))
        isThresholdExceeded = consecutiveThresholdSamples >= requiredSamples
    }
}

actor ProcessCPUSampler {
    func sampleTopProcesses(limit: Int) -> [ProcessCPU] {
        let output = runPS()

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { parsePSLine(String($0)) }
            .sorted(by: { $0.cpuPercent > $1.cpuPercent })
            .prefix(limit)
            .map { $0 }
    }

    private func runPS() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid=,%cpu=,comm="]
        process.environment = ["LC_ALL": "C", "LANG": "C"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parsePSLine(_ line: String) -> ProcessCPU? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
        guard parts.count == 3,
              let pid = Int32(parts[0]),
              let cpuPercent = Double(parts[1]),
              cpuPercent >= 0.1
        else {
            return nil
        }

        let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return ProcessCPU(pid: pid, name: name, cpuPercent: cpuPercent)
    }
}
