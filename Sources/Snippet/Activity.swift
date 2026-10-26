import AppKit
import Darwin
import IOKit

/// One process or, in the Apps view, an app with its helper processes summed.
struct ProcessEntry: Identifiable, Equatable {
    var id: UUID
    var pid: pid_t
    var parent: pid_t = 0
    var uid: uid_t = 0
    var user = ""
    var name: String
    var path = ""
    var started = Date.distantPast
    /// Percent of one core, as in Activity Monitor, so a busy process can exceed 100.
    var cpu = 0.0
    var cpuTime: TimeInterval = 0
    /// The memory footprint, or the resident size when the process is restricted.
    var memory: UInt64 = 0
    var threads: Int?
    var diskRead = 0.0, diskWrite = 0.0
    var bytesRead: UInt64 = 0, bytesWritten: UInt64 = 0
    /// Watts, from the kernel's per-task energy estimate. Nil where the Mac doesn't report it.
    var power: Double?
    /// The outermost app bundle containing the executable, so helpers carry their app's icon.
    var bundle: URL?
    /// A running application's own process.
    var isApp = false
    /// Owned by another user: only the path is readable, so CPU time and resident memory come from ps.
    var restricted = false
    var processCount = 1
    var disk: Double { diskRead + diskWrite }
}

enum ProcessScope: String, CaseIterable { case apps, mine, all
    var title: String { switch self { case .apps: return "Apps"; case .mine: return "My processes"; case .all: return "All processes" } }
}
enum ProcessSort: String, CaseIterable { case name, cpu, memory, power, disk, threads, pid
    var title: String {
        switch self { case .name: return "Name"; case .cpu: return "% CPU"; case .memory: return "Memory"; case .power: return "Power"; case .disk: return "Disk"; case .threads: return "Threads"; case .pid: return "PID" }
    }
    /// Names read A to Z; measurements start with the largest.
    var ascendingByDefault: Bool { self == .name }
}
enum MemoryPressure: Int { case normal = 1, warning = 2, critical = 4
    var title: String { switch self { case .normal: return "Normal"; case .warning: return "Warning"; case .critical: return "Critical" } }
}

struct SystemLoad: Equatable {
    /// Percent of all cores together.
    var user = 0.0, system = 0.0
    var cpu: Double { user + system }
    var memoryTotal = ProcessInfo.processInfo.physicalMemory
    var appMemory: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cached: UInt64 = 0, swapUsed: UInt64 = 0
    var memoryUsed: UInt64 { appMemory + wired + compressed }
    var pressure = MemoryPressure.normal
    var diskRead = 0.0, diskWrite = 0.0, networkIn = 0.0, networkOut = 0.0
    var processCount = 0, threadCount = 0
    /// One value per sample, oldest first, for the sparklines.
    var cpuHistory: [Double] = [], memoryHistory: [Double] = [], diskHistory: [Double] = [], networkHistory: [Double] = []
    static let historyLength = 60
}

enum ActivityFormat {
    /// "0 KB", "812 KB", "1.4 MB", "11.2 GB". Memory uses binary units, transfer decimal, as in Activity Monitor.
    static func bytes(_ value: Double, binary: Bool = true) -> String {
        let unit = binary ? 1024.0 : 1000.0
        var scaled = max(0, value) / unit, index = 0
        let names = ["KB", "MB", "GB", "TB"]
        while scaled >= unit, index < names.count - 1 { scaled /= unit; index += 1 }
        let digits = scaled >= 100 || scaled == 0 || index == 0 ? 0 : 1
        return scaled.formatted(.number.precision(.fractionLength(digits))) + " " + names[index]
    }
    static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }
    static func rate(_ value: Double) -> String { bytes(value, binary: false) + "/s" }
    static func percent(_ value: Double, digits: Int = 1) -> String { value.formatted(.number.precision(.fractionLength(digits))) }
    static func power(_ watts: Double?) -> String {
        guard let watts else { return "—" }
        return watts < 1 ? "\(Int((watts * 1000).rounded())) mW" : watts.formatted(.number.precision(.fractionLength(1))) + " W"
    }
    /// "4:05", "1:02:03".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds), h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

enum ActivityList {
    /// "/Applications/Chrome.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/Helper" → /Applications/Chrome.app
    static func outermostApp(_ path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? URL(fileURLWithPath: path) : nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
    }
    /// Each app's processes folded into one row: helpers inside its bundle add their CPU, memory, disk and power.
    static func grouped(_ processes: [ProcessEntry]) -> [ProcessEntry] {
        var groups: [String: ProcessEntry] = [:]
        for app in processes where app.isApp {
            let key = app.bundle?.path ?? "pid:\(app.pid)"
            if groups[key] == nil { groups[key] = app }
        }
        for process in processes where !process.isApp {
            guard let key = process.bundle?.path, var group = groups[key] else { continue }
            group.cpu += process.cpu; group.cpuTime += process.cpuTime; group.memory += process.memory
            group.diskRead += process.diskRead; group.diskWrite += process.diskWrite
            group.bytesRead += process.bytesRead; group.bytesWritten += process.bytesWritten
            if let power = process.power { group.power = (group.power ?? 0) + power }
            if let threads = process.threads { group.threads = (group.threads ?? 0) + threads }
            group.processCount += 1
            groups[key] = group
        }
        return Array(groups.values)
    }
    /// Pure digits find a PID; otherwise names match as in app search, and a user name matches exactly.
    static func matches(_ process: ProcessEntry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if let pid = Int32(q), pid == process.pid { return true }
        if AppSearch.score(process.name, query: q) != nil { return true }
        return !process.user.isEmpty && AppSearch.fold(process.user) == AppSearch.fold(q)
    }
    static func sorted(_ processes: [ProcessEntry], by sort: ProcessSort, ascending: Bool) -> [ProcessEntry] {
        func value(_ p: ProcessEntry) -> Double {
            switch sort {
            case .name: return 0
            case .cpu: return p.cpu
            case .memory: return Double(p.memory)
            case .power: return p.power ?? -1
            case .disk: return p.disk
            case .threads: return Double(p.threads ?? -1)
            case .pid: return Double(p.pid)
            }
        }
        return processes.sorted { a, b in
            if sort != .name { let x = value(a), y = value(b); if x != y { return ascending ? x < y : x > y } }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return (order == .orderedAscending) == (ascending || sort != .name) }
            return a.pid < b.pid
        }
    }
    static func list(_ processes: [ProcessEntry], scope: ProcessScope, query: String, sort: ProcessSort, ascending: Bool, uid: uid_t = getuid()) -> [ProcessEntry] {
        let scoped: [ProcessEntry]
        switch scope {
        case .apps: scoped = grouped(processes)
        case .mine: scoped = processes.filter { $0.uid == uid }
        case .all: scoped = processes
        }
        return sorted(scoped.filter { matches($0, query: query) }, by: sort, ascending: ascending)
    }
    /// ps prints CPU time as [[dd-]hh:]mm:ss.ss.
    static func psTime(_ text: Substring) -> TimeInterval? {
        var days = 0.0, clock = text
        if let dash = text.firstIndex(of: "-") { guard let d = Double(text[..<dash]) else { return nil }; days = d; clock = text[text.index(after: dash)...] }
        var seconds = 0.0
        for part in clock.split(separator: ":") { guard let value = Double(part) else { return nil }; seconds = seconds * 60 + value }
        return days * 86_400 + seconds
    }
    /// Lines of `ps -axo pid=,time=,rss=`: PID → (CPU seconds, resident bytes).
    static func parsePS(_ output: String) -> [pid_t: (cpu: TimeInterval, resident: UInt64)] {
        var result: [pid_t: (cpu: TimeInterval, resident: UInt64)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let pid = pid_t(fields[0]), let time = psTime(fields[1]), let kilobytes = UInt64(fields[2]) else { continue }
            result[pid] = (time, kilobytes * 1024)
        }
        return result
    }
    static func cpuPercent(previous: TimeInterval, current: TimeInterval, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return (current - previous) / elapsed * 100
    }
    static func identifier(pid: pid_t, started: timeval) -> UUID {
        var raw = (UInt32(bitPattern: pid), UInt32(truncatingIfNeeded: started.tv_sec), UInt32(truncatingIfNeeded: Int64(started.tv_sec) >> 32), UInt32(bitPattern: started.tv_usec))
        return withUnsafeBytes(of: &raw) { NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress) as UUID }
    }
    /// Why a process mustn't be quit from here, if it mustn't.
    static func protectedReason(_ process: ProcessEntry, own: pid_t = getpid()) -> String? {
        if process.pid == own { return "To quit \(AppEnvironment.current.name), use Quit in its menu-bar menu." }
        if process.pid == 0 { return "kernel_task is the macOS kernel and can’t be quit." }
        if process.pid == 1 { return "launchd starts every other process and can’t be quit." }
        return nil
    }
}

struct RunningAppInfo { let pid: pid_t; let name: String; let bundle: URL? }

/// Reads the process table and system counters. Used only from ActivityStore's queue.
final class ActivitySampler {
    private struct Previous { var cpu: TimeInterval; var read: UInt64; var written: UInt64; var energy: UInt64 }
    private var previous: [UUID: Previous] = [:]
    private var previousTime: TimeInterval?
    private var previousTicks: [UInt32]?
    private var previousNetwork: (UInt64, UInt64)?, previousDisk: (UInt64, UInt64)?
    private var history = SystemLoad()
    private var users: [uid_t: String] = [:]
    private let host = mach_host_self()
    private let timebase: Double = { var info = mach_timebase_info_data_t(); mach_timebase_info(&info); return Double(info.numer) / Double(info.denom) }()

    /// The next sample is a fresh baseline, so rates never span the time the list was closed.
    func reset() {
        previous = [:]; previousTime = nil; previousTicks = nil; previousNetwork = nil; previousDisk = nil
        history = SystemLoad()
    }
    /// Nil for a baseline: rates need two samples.
    func sample(apps: [RunningAppInfo]) -> (processes: [ProcessEntry], system: SystemLoad)? {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 }
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [ProcessEntry] = [], current: [UUID: Previous] = [:], needsPS: [Int] = []
        for info in Self.processTable() {
            let pid = info.kp_proc.p_pid
            let uid = info.kp_eproc.e_ucred.cr_uid
            let started = info.kp_proc.p_starttime
            var entry = ProcessEntry(id: ActivityList.identifier(pid: pid, started: started), pid: pid, name: "")
            entry.parent = info.kp_eproc.e_ppid
            entry.uid = uid
            entry.user = user(uid)
            entry.started = Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
            entry.path = Self.path(pid)
            let comm = withUnsafeBytes(of: info.kp_proc.p_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if let app = appsByPID[pid] {
                entry.isApp = true; entry.name = app.name.isEmpty ? comm : app.name
                entry.bundle = app.bundle ?? ActivityList.outermostApp(entry.path)
            } else {
                entry.name = entry.path.isEmpty ? comm : (entry.path as NSString).lastPathComponent
                entry.bundle = ActivityList.outermostApp(entry.path)
            }
            var usage = rusage_info_v6()
            let readable = withUnsafeMutablePointer(to: &usage) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) } } == 0
            if readable {
                let cpu = Double(usage.ri_user_time + usage.ri_system_time) * timebase / 1_000_000_000
                entry.cpuTime = cpu
                entry.memory = usage.ri_phys_footprint
                entry.bytesRead = usage.ri_diskio_bytesread; entry.bytesWritten = usage.ri_diskio_byteswritten
                var task = proc_taskinfo()
                if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 { entry.threads = Int(task.pti_threadnum) }
                let sample = Previous(cpu: cpu, read: usage.ri_diskio_bytesread, written: usage.ri_diskio_byteswritten, energy: usage.ri_energy_nj)
                if let elapsed, let before = previous[entry.id] {
                    entry.cpu = ActivityList.cpuPercent(previous: before.cpu, current: cpu, elapsed: elapsed)
                    entry.diskRead = Self.rate(sample.read, before.read, elapsed)
                    entry.diskWrite = Self.rate(sample.written, before.written, elapsed)
                    if sample.energy > 0 { entry.power = Self.rate(sample.energy, before.energy, elapsed) / 1_000_000_000 }
                }
                current[entry.id] = sample
            } else {
                entry.restricted = true
                needsPS.append(entries.count)
            }
            entries.append(entry)
        }
        if !needsPS.isEmpty {
            let ps = Self.runPS()
            for index in needsPS {
                guard let values = ps[entries[index].pid] else { continue }
                entries[index].cpuTime = values.cpu
                entries[index].memory = values.resident
                let id = entries[index].id
                if let elapsed, let before = previous[id] { entries[index].cpu = ActivityList.cpuPercent(previous: before.cpu, current: values.cpu, elapsed: elapsed) }
                current[id] = Previous(cpu: values.cpu, read: 0, written: 0, energy: 0)
            }
        }
        previous = current
        previousTime = now
        let system = systemLoad(elapsed: elapsed, processes: entries)
        guard elapsed != nil else { return nil }
        return (entries, system)
    }

    private func user(_ uid: uid_t) -> String {
        if let name = users[uid] { return name }
        var record = passwd(), result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        let name = getpwuid_r(uid, &record, &buffer, buffer.count, &result) == 0 && result != nil ? String(cString: record.pw_name) : String(uid)
        users[uid] = name
        return name
    }
    static func processTable() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return [] }
        // Room for processes started between the two calls.
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = table.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &table, &size, nil, 0) == 0 else { return [] }
        return Array(table.prefix(size / MemoryLayout<kinfo_proc>.stride))
    }
    static func path(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }
    /// ps is setuid root, so it reads CPU time and resident memory for processes Snippet can't.
    static func runPS() -> [pid_t: (cpu: TimeInterval, resident: UInt64)] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,time=,rss="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ActivityList.parsePS(String(decoding: data, as: UTF8.self))
    }

    private func systemLoad(elapsed: TimeInterval?, processes: [ProcessEntry]) -> SystemLoad {
        var load = history
        load.processCount = processes.count
        load.threadCount = processes.reduce(0) { $0 + ($1.threads ?? 0) }
        if let ticks = cpuTicks() {
            if let before = previousTicks {
                let delta = zip(ticks, before).map { Double($0 &- $1) }
                let total = delta.reduce(0, +)
                if total > 0 { load.user = (delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]) / total * 100; load.system = delta[Int(CPU_STATE_SYSTEM)] / total * 100 }
            }
            previousTicks = ticks
        }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        if withUnsafeMutablePointer(to: &vm, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) } }) == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            // Activity Monitor's breakdown: app memory is anonymous memory that can't be purged.
            load.appMemory = UInt64(vm.internal_page_count) > UInt64(vm.purgeable_count) ? (UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count)) * page : 0
            load.wired = UInt64(vm.wire_count) * page
            load.compressed = UInt64(vm.compressor_page_count) * page
            load.cached = (UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)) * page
        }
        var level: Int32 = 1, size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 { load.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal }
        var swap = xsw_usage(); size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { load.swapUsed = swap.xsu_used }
        let network = Self.networkBytes(), disk = Self.diskBytes()
        if let elapsed, elapsed > 0 {
            if let before = previousNetwork { load.networkIn = Self.rate(network.0, before.0, elapsed); load.networkOut = Self.rate(network.1, before.1, elapsed) }
            if let before = previousDisk { load.diskRead = Self.rate(disk.0, before.0, elapsed); load.diskWrite = Self.rate(disk.1, before.1, elapsed) }
            func push(_ values: inout [Double], _ value: Double) { values.append(value); if values.count > SystemLoad.historyLength { values.removeFirst(values.count - SystemLoad.historyLength) } }
            push(&load.cpuHistory, load.cpu)
            push(&load.memoryHistory, Double(load.memoryUsed) / Double(max(load.memoryTotal, 1)) * 100)
            push(&load.diskHistory, load.diskRead + load.diskWrite)
            push(&load.networkHistory, load.networkIn + load.networkOut)
        }
        previousNetwork = network; previousDisk = disk
        history = load
        return load
    }
    static func rate(_ now: UInt64, _ before: UInt64, _ elapsed: TimeInterval) -> Double { now >= before ? Double(now - before) / elapsed : 0 }
    private func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        guard withUnsafeMutablePointer(to: &info, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) } }) == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return [ticks.0, ticks.1, ticks.2, ticks.3]
    }
    /// Bytes received and sent on every interface except loopback, from the 64-bit counters.
    static func networkBytes() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return (0, 0) }
        var received: UInt64 = 0, sent: UInt64 = 0, offset = 0
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= size {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_flags & IFF_LOOPBACK == 0 { received += message.ifm_data.ifi_ibytes; sent += message.ifm_data.ifi_obytes }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }
    /// Bytes read and written by every block storage driver since startup.
    static func diskBytes() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
        }
        return (read, written)
    }
}

enum QuitOutcome: Equatable { case sent, needsAdministrator, failed(String) }

/// The Activity section: samples every two seconds while it's on screen, and quits processes.
final class ActivityStore: ObservableObject {
    @Published private(set) var processes: [ProcessEntry] = []
    @Published private(set) var system = SystemLoad()
    /// False until the first sample with rates arrives after opening.
    @Published private(set) var measured = false
    @Published var scope: ProcessScope { didSet { defaults.set(scope.rawValue, forKey: "activityScope") } }
    @Published var sort: ProcessSort { didSet { defaults.set(sort.rawValue, forKey: "activitySort") } }
    @Published var ascending: Bool { didSet { defaults.set(ascending, forKey: "activityAscending") } }
    let defaults: UserDefaults
    private let sampler = ActivitySampler()
    private let queue = DispatchQueue(label: "Snippet.activity", qos: .utility)
    private var timer: Timer?
    private var sampling = false
    private var generation = 0
    private let icons = NSCache<NSString, NSImage>()
    init(defaults: UserDefaults = AppEnvironment.defaults) {
        self.defaults = defaults
        scope = defaults.string(forKey: "activityScope").flatMap(ProcessScope.init) ?? .all
        let sort = defaults.string(forKey: "activitySort").flatMap(ProcessSort.init) ?? .cpu
        self.sort = sort
        ascending = defaults.object(forKey: "activityAscending") as? Bool ?? sort.ascendingByDefault
    }
    var running: Bool { timer != nil }
    func start() {
        guard timer == nil else { return }
        generation += 1
        let generation = generation
        queue.async { [sampler] in sampler.reset() }
        measured = false
        sample()
        // The first sample is a baseline; take the second sooner than the regular interval.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in if self?.generation == generation, self?.running == true { self?.sample() } }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() {
        timer?.invalidate(); timer = nil
        generation += 1
    }
    func sample() {
        guard !sampling else { return }
        sampling = true
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
            .map { RunningAppInfo(pid: $0.processIdentifier, name: $0.localizedName ?? "", bundle: $0.bundleURL) }
        let generation = generation
        queue.async { [weak self, sampler] in
            let result = sampler.sample(apps: apps)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                guard let result, generation == self.generation else { return }
                self.processes = result.processes
                self.system = result.system
                self.measured = true
            }
        }
    }
    func list(query: String) -> [ProcessEntry] {
        ActivityList.list(processes, scope: scope, query: query, sort: sort, ascending: ascending)
    }
    /// Clicking the sorted column reverses it; another column starts in its natural direction.
    func sort(by column: ProcessSort) {
        if sort == column { ascending.toggle() } else { sort = column; ascending = column.ascendingByDefault }
    }
    func icon(_ process: ProcessEntry) -> NSImage? {
        guard let bundle = process.bundle else { return nil }
        if let icon = icons.object(forKey: bundle.path as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: bundle.path)
        icons.setObject(icon, forKey: bundle.path as NSString)
        return icon
    }
    func process(_ pid: pid_t) -> ProcessEntry? { processes.first { $0.pid == pid } }
    /// Apps are asked to quit as with Command–Q, so they can save; other processes get SIGTERM, or SIGKILL when forced.
    func quit(_ process: ProcessEntry, force: Bool) -> QuitOutcome {
        if let reason = ActivityList.protectedReason(process) { return .failed(reason) }
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if self?.running == true { self?.sample() } } }
        if let app = NSRunningApplication(processIdentifier: process.pid), app.activationPolicy != .prohibited, force ? app.forceTerminate() : app.terminate() { return .sent }
        if Darwin.kill(process.pid, force ? SIGKILL : SIGTERM) == 0 { return .sent }
        switch errno {
        case EPERM: return .needsAdministrator
        case ESRCH: return .failed("\(process.name) has already quit.")
        default: return .failed("Couldn’t quit \(process.name): " + String(cString: strerror(errno)))
        }
    }
    /// macOS shows its standard administrator prompt. Completes on the main thread with an error, or nil if it quit or was cancelled.
    func quitAsAdministrator(_ process: ProcessEntry, force: Bool, completion: @escaping (String?) -> Void) {
        if let reason = ActivityList.protectedReason(process) { completion(reason); return }
        let script = "do shell script \"/bin/kill -\(force ? 9 : 15) \(process.pid)\" with administrator privileges"
        queue.async { [weak self] in
            let task = Process(), errors = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = errors
            var message: String?
            do {
                try task.run()
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                task.waitUntilExit()
                // -128 is "User canceled".
                if task.terminationStatus != 0 && !output.contains("-128") {
                    message = "Couldn’t quit \(process.name): " + (output.components(separatedBy: ": ").last ?? output).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch { message = "Couldn’t ask for administrator access: " + error.localizedDescription }
            DispatchQueue.main.async {
                completion(message)
                if self?.running == true { self?.sample() }
            }
        }
    }
}
