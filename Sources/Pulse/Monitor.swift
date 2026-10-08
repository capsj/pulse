import Darwin
import Foundation

struct ProcessRow: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let cpu: Double        // percent, as reported by ps
    let memoryBytes: UInt64 // resident set size
    var id: Int32 { pid }
}

struct MemoryStats {
    enum Pressure: String { case normal = "Normal", warning = "Warning", critical = "Critical" }

    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: Pressure = .normal

    /// Matches Activity Monitor's "Memory Used": app + wired + compressed.
    var used: UInt64 { app + wired + compressed }
}

/// Samples system-wide CPU and memory via Mach, and the process table via `ps`,
/// every `interval` seconds. All published state is updated on the main actor.
@MainActor
final class Monitor: ObservableObject {
    @Published var cpuTotal: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var cores: [Double] = []
    @Published var history: [Double] = Array(repeating: 0, count: 60)
    @Published var loadAverage: [Double] = [0, 0, 0]
    @Published var thermal: ProcessInfo.ThermalState = .nominal
    @Published var memory = MemoryStats()
    @Published var processes: [ProcessRow] = []

    let interval: TimeInterval = 2
    private var previousTicks: [[UInt32]] = []
    private var timer: Timer?
    private var samplingProcesses = false

    init() {
        previousTicks = readCPUTicks()
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so it keeps ticking while the panel is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func tick() {
        let ticks = readCPUTicks()
        if !ticks.isEmpty, ticks.count == previousTicks.count {
            var user = 0.0, system = 0.0, total = 0.0
            cores = zip(ticks, previousTicks).map { now, prev in
                let d = (0..<4).map { Double(now[$0] &- prev[$0]) }
                let sum = d.reduce(0, +)
                user += d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_NICE)]
                system += d[Int(CPU_STATE_SYSTEM)]
                total += sum
                return sum > 0 ? (sum - d[Int(CPU_STATE_IDLE)]) / sum * 100 : 0
            }
            cpuUser = total > 0 ? user / total * 100 : 0
            cpuSystem = total > 0 ? system / total * 100 : 0
            cpuTotal = cpuUser + cpuSystem
            history.removeFirst()
            history.append(cpuTotal)
        }
        previousTicks = ticks

        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        loadAverage = load
        thermal = ProcessInfo.processInfo.thermalState
        memory = readMemory()

        guard !samplingProcesses else { return }
        samplingProcesses = true
        Task { [weak self] in
            let rows = await Task.detached(priority: .utility) { readProcesses() }.value
            self?.processes = rows
            self?.samplingProcesses = false
        }
    }
}

// MARK: - Sampling

/// Per-core [user, system, idle, nice] tick counters.
private func readCPUTicks() -> [[UInt32]] {
    var cpuCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
          let info else { return [] }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
    }
    let states = Int(CPU_STATE_MAX)
    return (0..<Int(cpuCount)).map { core in
        (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
    }
}

private func readMemory() -> MemoryStats {
    var m = MemoryStats()
    m.total = ProcessInfo.processInfo.physicalMemory

    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    if kr == KERN_SUCCESS {
        let page = UInt64(vm_kernel_page_size)
        let anonymous = UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count))
        m.app = anonymous * page
        m.wired = UInt64(vm.wire_count) * page
        m.compressed = UInt64(vm.compressor_page_count) * page
        m.cached = (UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)) * page
    }

    var swap = xsw_usage()
    var swapSize = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
        m.swapUsed = swap.xsu_used
    }

    var level: Int32 = 0
    var levelSize = MemoryLayout<Int32>.size
    if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
        m.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
    }
    return m
}

/// Per-process CPU and memory come from `ps`. Reading other users' processes
/// (WindowServer, kernel_task, daemons) directly needs an Apple-private
/// entitlement that `ps` has and third-party apps can't get.
private func readProcesses() -> [ProcessRow] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
    let out = Pipe()
    ps.standardOutput = out
    ps.standardError = FileHandle.nullDevice
    do { try ps.run() } catch { return [] }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    let psPid = ps.processIdentifier

    var rows: [ProcessRow] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]), pid != psPid,
              let cpu = Double(parts[1]),
              let rssKB = UInt64(parts[2]) else { continue }
        rows.append(ProcessRow(pid: pid,
                               name: parts[3].trimmingCharacters(in: .whitespaces),
                               cpu: cpu,
                               memoryBytes: rssKB * 1024))
    }
    return rows
}
