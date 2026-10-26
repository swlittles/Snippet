import SwiftUI
import AppKit

struct ProcessQuitRequest: Identifiable {
    let id = UUID()
    let process: ProcessEntry
    let force: Bool
    var message: String {
        var parts = [process.isApp ? (force ? "Unsaved changes will be lost." : "\(process.name) can ask you to save changes first.")
                                   : "Quitting a process can stop an app or a macOS feature from working until it restarts."]
        if process.processCount > 1 { parts.append("Its \(process.processCount - 1) helper processes quit with it.") }
        if process.uid != getuid() { parts.append("It runs as \(process.user), so macOS will ask for an administrator’s password.") }
        return parts.joined(separator: " ")
    }
}

/// The Activity section: system load, then a sortable table of processes.
struct ActivityView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var activity: ActivityStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    static let columns: [(sort: ProcessSort, width: CGFloat)] = [(.cpu, 54), (.memory, 70), (.power, 60), (.disk, 72), (.threads, 52), (.pid, 54)]
    var body: some View {
        VStack(spacing: 0) {
            tiles.padding(.horizontal, 20).padding(.top, 12)
            toolbar.padding(.horizontal, 20).padding(.vertical, 8)
            header.padding(.horizontal, 28)
            Divider().padding(.horizontal, 20)
            if model.results.isEmpty { empty } else { list }
        }.frame(height: model.listHeight)
    }
    var tiles: some View {
        let load = activity.system
        return HStack(spacing: 8) {
            StatTile(label: "CPU", value: ActivityFormat.percent(load.cpu, digits: 0) + "%", detail: "User \(ActivityFormat.percent(load.user, digits: 0))% · System \(ActivityFormat.percent(load.system, digits: 0))%",
                     history: load.cpuHistory, ceiling: 100, summary: Self.summary("CPU", load.cpuHistory) { ActivityFormat.percent($0, digits: 0) + "%" })
            StatTile(label: "Memory", value: ActivityFormat.bytes(load.memoryUsed), detail: "of \(ActivityFormat.bytes(load.memoryTotal)) · swap \(ActivityFormat.bytes(load.swapUsed))",
                     history: load.memoryHistory, ceiling: 100, summary: "App \(ActivityFormat.bytes(load.appMemory)) · wired \(ActivityFormat.bytes(load.wired)) · compressed \(ActivityFormat.bytes(load.compressed)) · cached files \(ActivityFormat.bytes(load.cached)). Memory pressure: \(load.pressure.title).",
                     status: pressure(load.pressure))
            StatTile(label: "Disk", value: ActivityFormat.rate(load.diskRead + load.diskWrite), detail: "Read \(ActivityFormat.rate(load.diskRead)) · Write \(ActivityFormat.rate(load.diskWrite))",
                     history: load.diskHistory, ceiling: nil, summary: Self.summary("Disk", load.diskHistory, ActivityFormat.rate))
            StatTile(label: "Network", value: ActivityFormat.rate(load.networkIn + load.networkOut), detail: "In \(ActivityFormat.rate(load.networkIn)) · Out \(ActivityFormat.rate(load.networkOut))",
                     history: load.networkHistory, ceiling: nil, summary: Self.summary("Network", load.networkHistory, ActivityFormat.rate))
        }
    }
    /// "CPU: peak 54%, average 21% over the last 2 minutes."
    static func summary(_ label: String, _ history: [Double], _ format: (Double) -> String) -> String {
        guard !history.isEmpty else { return label + ": measuring…" }
        let seconds = history.count * 2
        let span = seconds >= 120 ? "\(seconds / 60) minutes" : "\(seconds) seconds"
        return "\(label): peak \(format(history.max() ?? 0)), average \(format(history.reduce(0, +) / Double(history.count))) over the last \(span)."
    }
    func pressure(_ pressure: MemoryPressure) -> (icon: String, text: String, color: Color) {
        switch pressure {
        case .normal: return ("checkmark.circle", "Normal", .green)
        case .warning: return ("exclamationmark.triangle", "Warning", .yellow)
        case .critical: return ("exclamationmark.octagon", "Critical", .red)
        }
    }
    var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Show", selection: $activity.scope) { ForEach(ProcessScope.allCases, id: \.self) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 290).help("Apps combines each app with its helper processes")
            Spacer()
            Text(count).font(.system(size: 11)).foregroundStyle(theme.secondary)
        }
    }
    var count: String {
        let shown = model.results.count, noun = activity.scope == .apps ? (shown == 1 ? "app" : "apps") : (shown == 1 ? "process" : "processes")
        return "\(shown.formatted()) \(noun) · \(activity.system.threadCount.formatted()) threads"
    }
    var header: some View {
        HStack(spacing: 8) {
            headerButton(.name).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.columns, id: \.sort) { column in headerButton(column.sort).frame(width: column.width, alignment: .trailing) }
        }.frame(height: 24)
    }
    func headerButton(_ column: ProcessSort) -> some View {
        let active = activity.sort == column
        return Button { activity.sort(by: column) } label: {
            HStack(spacing: 3) {
                Text(column.title)
                if active { Image(systemName: activity.ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
            }.font(.system(size: 11, weight: active ? .semibold : .regular)).foregroundStyle(active ? theme.text : theme.secondary)
        }.buttonStyle(PointerButtonStyle()).help("Sort by " + column.title)
            .accessibilityValue(active ? (activity.ascending ? "Sorted ascending" : "Sorted descending") : "")
    }
    var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.results) { item in if let process = item.process { row(item, process) } }
                }.padding(.horizontal, 18).padding(.vertical, 4)
            }.onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
        }
    }
    func cell(_ process: ProcessEntry, _ column: ProcessSort) -> String {
        switch column {
        case .name: return process.name
        case .cpu: return ActivityFormat.percent(process.cpu)
        case .memory: return ActivityFormat.bytes(process.memory)
        case .power: return ActivityFormat.power(process.power)
        case .disk: return process.restricted ? "—" : ActivityFormat.rate(process.disk)
        case .threads: return process.threads.map { String($0) } ?? "—"
        case .pid: return String(process.pid)
        }
    }
    func row(_ item: ResultItem, _ process: ProcessEntry) -> some View {
        let selected = model.selected == item.id
        return HStack(spacing: 8) {
            HStack(spacing: 7) {
                if let icon = activity.icon(process) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16) }
                else { Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(theme.secondary).frame(width: 16, height: 16) }
                Text(process.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                if process.processCount > 1 { Text("\(process.processCount)").font(.system(size: 10)).foregroundStyle(theme.secondary).help("\(process.processCount) processes") }
                if process.uid != getuid() { Text(process.user).font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.columns, id: \.sort) { column in
                Text(cell(process, column.sort)).font(.system(size: 11.5).monospacedDigit()).lineLimit(1)
                    .foregroundStyle(activity.sort == column.sort ? theme.text : theme.secondary).frame(width: column.width, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(selected ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle()).pointerCursor()
        .onTapGesture(count: 2) { model.selected = item.id; model.preview = true }
        .simultaneousGesture(TapGesture().onEnded { model.selected = item.id })
        .help(process.restricted ? "Owned by \(process.user). Memory is the resident size; disk and power aren’t readable without administrator access." : process.path)
        .id(item.id)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(process.name), \(ActivityFormat.percent(process.cpu)) percent CPU, \(ActivityFormat.bytes(process.memory)) memory")
        .accessibilityValue(selected ? "Selected" : "")
        .contextMenu {
            Button("Show details") { model.selected = item.id; model.preview = true }
            if let app = NSRunningApplication(processIdentifier: process.pid), app.activationPolicy == .regular {
                Button("Bring to front") { model.app.hide(restoreFocus: false); model.app.activate(app) }
            }
            Divider()
            Button("Quit…") { model.selected = item.id; model.requestQuit(process, force: false) }
            Button("Force Quit…") { model.selected = item.id; model.requestQuit(process, force: true) }
            Divider()
            if !process.path.isEmpty { Button("Show in Finder") { model.selected = item.id; model.choose(copy: true) } }
            Button("Copy PID") { model.app.copyText(String(process.pid)); model.message = "PID copied" }
            if !process.path.isEmpty { Button("Copy path") { model.app.copyText(process.path); model.message = "Path copied" } }
        }
    }
    var empty: some View {
        VStack(spacing: 10) {
            if activity.measured {
                Image(systemName: "magnifyingglass").font(.system(size: 26, weight: .light)).foregroundStyle(theme.accent)
                Text(activity.scope == .apps ? "No matching apps" : "No matching processes").font(.system(size: 16, weight: .medium))
                Text("Filter by name, PID or user name.").font(.system(size: 12)).foregroundStyle(theme.secondary)
            } else {
                ProgressView().controlSize(.small)
                Text("Measuring…").font(.system(size: 12)).foregroundStyle(theme.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A label, a current value, a detail line and a sparkline of recent samples.
struct StatTile: View {
    @EnvironmentObject var theme: ThemeStore
    let label: String
    let value: String
    let detail: String
    let history: [Double]
    /// A fixed top for percentages; rates scale to their own peak.
    let ceiling: Double?
    let summary: String
    var status: (icon: String, text: String, color: Color)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 11)).foregroundStyle(theme.secondary)
                if let status {
                    Spacer(minLength: 2)
                    Image(systemName: status.icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(status.color)
                    Text(status.text).font(.system(size: 10)).foregroundStyle(theme.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text(value).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Sparkline(values: history, ceiling: ceiling, color: theme.accent).frame(width: 46, height: 20)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .help(summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, detail, status.map { "Pressure " + $0.text } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

struct Sparkline: View {
    let values: [Double]
    let ceiling: Double?
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let top = max(ceiling ?? (values.max() ?? 0), ceiling == nil ? 1024 : 1)
            let step = geo.size.width / CGFloat(max(SystemLoad.historyLength - 1, 1))
            // Newest at the right edge, so the line grows in from the right as samples arrive.
            let points = values.enumerated().map { index, value in
                CGPoint(x: geo.size.width - CGFloat(values.count - 1 - index) * step, y: geo.size.height - 1 - CGFloat(min(value, top) / top) * (geo.size.height - 2))
            }
            if points.count > 1 {
                Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: geo.size.height)); points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height)); path.closeSubpath()
                }.fill(color.opacity(0.14))
                Path { path in path.addLines(points) }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

struct ProcessDetailView: View {
    let process: ProcessEntry
    @ObservedObject var activity: ActivityStore
    @EnvironmentObject var theme: ThemeStore
    var kind: String {
        var parts = [process.isApp ? "Application" : "Process"]
        if process.processCount > 1 { parts.append("\(process.processCount) processes") }
        if process.uid != getuid() { parts.append("runs as \(process.user)") }
        return parts.joined(separator: " · ")
    }
    var parent: String {
        guard process.parent > 0 || process.pid > 0 else { return "—" }
        return (activity.process(process.parent)?.name ?? "PID") + " (\(process.parent))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let icon = activity.icon(process) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 28, height: 28) }
                else { Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(theme.accent).frame(width: 28, height: 28) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(process.path.isEmpty ? kind : kind + " · " + process.path).font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    field("PID", String(process.pid)); field(process.processCount > 1 ? "Processes" : "Parent", process.processCount > 1 ? String(process.processCount) : parent)
                    field("User", process.user); field("Started", process.started == .distantPast ? "—" : process.started.formatted(.relative(presentation: .named)))
                }
                GridRow {
                    field("CPU", ActivityFormat.percent(process.cpu) + "%"); field("CPU time", ActivityFormat.duration(process.cpuTime))
                    field("Threads", process.threads.map { String($0) } ?? "—"); field("Power", ActivityFormat.power(process.power))
                }
                GridRow {
                    field(process.restricted ? "Resident memory" : "Memory", ActivityFormat.bytes(process.memory))
                    field("Disk now", process.restricted ? "—" : ActivityFormat.rate(process.disk))
                    field("Read", process.restricted ? "—" : ActivityFormat.bytes(Double(process.bytesRead), binary: false))
                    field("Written", process.restricted ? "—" : ActivityFormat.bytes(Double(process.bytesWritten), binary: false))
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }
    func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(theme.secondary)
            Text(value).font(.system(size: 12).monospacedDigit()).lineLimit(1).textSelection(.enabled)
        }.frame(width: 140, alignment: .leading)
    }
}
