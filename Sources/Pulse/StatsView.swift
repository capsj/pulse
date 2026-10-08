import AppKit
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var monitor: Monitor
    @AppStorage("sortBy") private var sortBy: ProcessSort = .cpu

    enum ProcessSort: String, CaseIterable { case cpu = "CPU", memory = "Memory" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cpuSection
            Divider()
            memorySection
            Divider()
            processSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: CPU

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("CPU").font(.headline)
                Detail("Thermal", thermalLabel).padding(.leading, 6)
                Spacer()
                Text(formatPercent(monitor.cpuTotal))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(loadColor(monitor.cpuTotal))
            }
            Sparkline(values: monitor.history).frame(height: 36)
            CoreBars(cores: monitor.cores).frame(height: 16)
            HStack(spacing: 12) {
                Detail("User", formatPercent(monitor.cpuUser))
                Detail("Sys", formatPercent(monitor.cpuSystem))
                Detail("Load", monitor.loadAverage.map { String(format: "%.1f", $0) }.joined(separator: " "))
            }
        }
    }

    private var thermalLabel: String {
        switch monitor.thermal {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    // MARK: Memory

    private var memorySection: some View {
        let m = monitor.memory
        let usedPercent = m.total > 0 ? Double(m.used) / Double(m.total) * 100 : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory").font(.headline)
                Spacer()
                Text("\(formatBytes(m.used)) / \(formatBytes(m.total))")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(loadColor(usedPercent))
            }
            StackedBar(total: m.total, segments: [
                (m.app, .blue), (m.wired, .orange), (m.compressed, .purple), (m.cached, .gray.opacity(0.35)),
            ])
            .frame(height: 8)
            HStack(spacing: 12) {
                Detail("App", formatBytes(m.app), color: .blue)
                Detail("Wired", formatBytes(m.wired), color: .orange)
                Detail("Compressed", formatBytes(m.compressed), color: .purple)
            }
            HStack(spacing: 12) {
                Detail("Cached", formatBytes(m.cached), color: .gray)
                Detail("Swap", formatBytes(m.swapUsed))
                Detail("Pressure", m.pressure.rawValue)
            }
        }
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top Processes").font(.headline)
                Spacer()
                Picker("Sort", selection: $sortBy) {
                    ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }
            ForEach(topProcesses) { p in
                HStack(spacing: 6) {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Text(String(p.pid)).font(.caption).foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Text(formatPercent(p.cpu))
                        .monospacedDigit()
                        .foregroundStyle(sortBy == .cpu ? .primary : .secondary)
                        .frame(width: 52, alignment: .trailing)
                    Text(formatBytes(p.memoryBytes))
                        .monospacedDigit()
                        .foregroundStyle(sortBy == .memory ? .primary : .secondary)
                        .frame(width: 66, alignment: .trailing)
                }
                .font(.callout)
                .frame(height: 18)
            }
        }
    }

    private var topProcesses: [ProcessRow] {
        let sorted = switch sortBy {
        case .cpu: monitor.processes.sorted { $0.cpu > $1.cpu }
        case .memory: monitor.processes.sorted { $0.memoryBytes > $1.memoryBytes }
        }
        return Array(sorted.prefix(8))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Activity Monitor…") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

// MARK: - Pieces

private struct Detail: View {
    let label: String
    let value: String
    var color: Color?

    init(_ label: String, _ value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

private struct Sparkline: View {
    let values: [Double] // 0...100, oldest first

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: CGFloat(i) * stepX, y: size.height - CGFloat(v / 100) * size.height)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(.accentColor.opacity(0.18)))
            ctx.stroke(line, with: .color(.accentColor), lineWidth: 1.5)
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct CoreBars: View {
    let cores: [Double]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, usage in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(loadColor(usage))
                            .frame(height: max(2, geo.size.height * usage / 100))
                    }
                }
            }
        }
    }
}

private struct StackedBar: View {
    let total: UInt64
    let segments: [(UInt64, Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let width = total > 0 ? geo.size.width * CGFloat(seg.0) / CGFloat(total) : 0
                    seg.1.frame(width: max(0, width))
                }
                Spacer(minLength: 0)
            }
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Formatting

func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value)
}

func formatBytes(_ bytes: UInt64, short: Bool = false) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 10 { return String(format: short ? "%.0fG" : "%.1f GB", gb) }
    if gb >= 1 { return String(format: short ? "%.1fG" : "%.1f GB", gb) }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1 { return String(format: short ? "%.0fM" : "%.0f MB", mb) }
    return String(format: short ? "%.0fK" : "%.0f KB", Double(bytes) / 1024)
}

func loadColor(_ percent: Double) -> Color {
    switch percent {
    case 80...: .red
    case 50...: .orange
    default: .green
    }
}
