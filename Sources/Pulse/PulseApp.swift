import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            StatsView().environmentObject(monitor)
        } label: {
            MenuBarLabel(cpu: monitor.cpuTotal, memoryUsed: monitor.memory.used)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when launched outside the .app bundle (swift run).
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarLabel: View {
    let cpu: Double
    let memoryUsed: UInt64

    var body: some View {
        // The status item flattens SwiftUI labels to one image + one text, so the
        // whole label (icons + numbers) is rendered to a template image instead.
        Image(nsImage: rendered)
    }

    @MainActor
    private var rendered: NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }

    private var content: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.bar.fill", variableValue: min(max(cpu / 100, 0), 1))
            Text(formatPercent(cpu))
            Image(systemName: "memorychip").padding(.leading, 6)
            Text(formatBytes(memoryUsed, short: true))
        }
        .font(.system(size: 13, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.black)
        .padding(.horizontal, 2)
    }
}
