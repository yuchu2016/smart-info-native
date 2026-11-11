import SwiftUI
import AppKit
import Combine

extension Health {
    var tint: Color {
        switch self { case .good: return Color(red: 0.10, green: 0.53, blue: 0.36); case .caution: return .orange; case .failed: return .red; case .unknown: return .secondary }
    }
}

@MainActor final class DiskStore: ObservableObject {
    @Published var disks: [DiskSnapshot] = []
    @Published var selection: String?
    @Published var busy = false
    @Published var lastUpdate: Date?
    @Published var error: String?
    @Published var engineVersion = "macOS 原生"
    @Published var automatic = false
    @Published var operation = "准备就绪"
    private var presentations: [String: SMARTPresentation] = [:]
    var selected: DiskSnapshot? { disks.first { $0.id == selection } }
    var selectedPresentation: SMARTPresentation? { selection.flatMap { presentations[$0] } }
    func health(_ disk: DiskSnapshot) -> Health { presentations[disk.id]?.health ?? disk.health }
    func select(_ id: String) { if selection != id { selection = id } }

    func refresh() {
        guard !busy else { return }
        busy = true; operation = "正在扫描物理磁盘…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DiskService.scan()
            let prepared = Dictionary(uniqueKeysWithValues: result.disks.map { ($0.id, SMARTPresentation($0)) })
            DispatchQueue.main.async {
                self.presentations = prepared
                self.disks = result.disks
                self.error = result.error
                self.engineVersion = result.engineVersion
                if !self.disks.contains(where: { $0.id == self.selection }) { self.selection = self.disks.first?.id }
                self.lastUpdate = Date(); self.busy = false; self.operation = "准备就绪"
            }
        }
    }
    func reread(type: String) {
        guard !busy, let id = selection else { return }
        busy = true; operation = "正在读取 \(id)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let disk = DiskService.read(id: id, deviceType: type)
            let prepared = disk.map { SMARTPresentation($0) }
            DispatchQueue.main.async {
                if let disk, let prepared, let index = self.disks.firstIndex(where: { $0.id == id }) { self.presentations[id] = prepared; self.disks[index] = disk; self.error = nil }
                else { self.error = "磁盘已断开或读取失败" }
                self.lastUpdate = Date(); self.busy = false; self.operation = "准备就绪"
            }
        }
    }
    func exportSelected() {
        guard let disk = selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SMART-\(disk.id).json"
        panel.title = "导出磁盘诊断报告"
        panel.message = "JSON · 包含设备序列号"
        if panel.runModal() == .OK, let url = panel.url {
            do { try disk.rawData.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = "导出失败：\(error.localizedDescription)" }
        }
    }
}

@main struct SMARTInfoApp: App {
    @StateObject private var store = DiskStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("SMART Info Native") {
            ContentView().environmentObject(store).frame(minWidth: 1010, minHeight: 710).preferredColorScheme(.light)
        }
        .defaultSize(width: 1170, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("刷新磁盘") { store.refresh() }.keyboardShortcut("r").disabled(store.busy)
                Button("导出当前磁盘报告…") { store.exportSelected() }.keyboardShortcut("e").disabled(store.selected == nil || store.busy)
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 SMART Info Native") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "SMART Info Native", .applicationVersion: "1.1.3", .credits: NSAttributedString(string: "SwiftUI · ARM64\nsmartmontools 7.5 · GPL v2")])
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Measures selection publication through the next forced window layout/display.
// The 16 ms scheduled frame is included; this is not a pure GPU/frame-rate measurement.
@MainActor enum SwitchBenchmark {
    static var started = false
    static var samples: [Double] = []
    static func start(_ store: DiskStore) {
        guard !started else { return }; started = true
        store.refresh()
        waitForScan(store)
    }
    static func waitForScan(_ store: DiskStore) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if store.busy { waitForScan(store); return }
            guard store.disks.count >= 2 else { print("BENCHMARK ERROR: needs two physical disks"); NSApp.terminate(nil); return }
            step(store, index: 0)
        }
    }
    static func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.identifier?.rawValue == "SMARTMetricsTable" { return table }
        for child in view.subviews { if let table = findTable(child) { return table } }
        return nil
    }
    static func validateTable(_ table: NSTableView, coordinator: SMARTMetricsTable.Coordinator, store: DiskStore) {
        guard let prepared = store.selectedPresentation, let scroll = table.enclosingScrollView else { fatalError("Table not attached") }
        func check(_ condition: Bool, _ name: String) { if !condition { fatalError("UI FAIL: " + name) }; print("UI PASS: " + name) }
        check(table.numberOfRows == prepared.rows.count, "native table retains every prepared row")
        let visible = table.rows(in: table.visibleRect)
        check(visible.length > 0 && visible.length < table.numberOfRows / 2, "only viewport rows are visible")
        var loaded = 0
        for index in 0..<table.numberOfRows { if table.rowView(atRow: index, makeIfNecessary: false) != nil { loaded += 1 } }
        check(loaded < table.numberOfRows / 2, "offscreen row views not eagerly instantiated")
        print("UI ROWS: total=\(table.numberOfRows) loaded=\(loaded) visible=\(visible.length)")
        check(table.headerView == nil && (scroll.superview as? SMARTTableContainer)?.header.frame.height == 30, "header has a separate non-overlapping viewport")
        let previousReloads = coordinator.reloads
        coordinator.update(prepared, showSerial: coordinator.showSerial, scroll: scroll)
        check(coordinator.reloads == previousReloads, "unrelated state updates do not reload table")
        check(scroll.hasHorizontalScroller && scroll.hasVerticalScroller && table.tableColumns.count == 6, "six fixed columns and both scroll axes")
        check(zip(table.tableColumns, SMARTPresentation.widths).allSatisfy { abs($0.0.width - $0.1) < 1 }, "native column widths match precomputed text measurements")
        scroll.contentView.scroll(to: NSPoint(x: 200, y: scroll.contentView.bounds.origin.y))
        if let container = scroll.superview as? SMARTTableContainer {
            check(abs(container.header.contentView.bounds.origin.x - scroll.contentView.bounds.origin.x) < 1, "header follows horizontal data scroll")
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
        if let serialIndex = prepared.rows.firstIndex(where: { $0.id.contains("serial_number") }) {
            coordinator.update(prepared, showSerial: true, scroll: scroll)
            let field = coordinator.tableView(table, viewFor: table.tableColumns[1], row: serialIndex) as? SMARTTextCell
            check(field?.label.stringValue == prepared.rows[serialIndex].cells[1].text, "identifier reveal uses original value")
            coordinator.update(prepared, showSerial: false, scroll: scroll)
            let masked = coordinator.tableView(table, viewFor: table.tableColumns[1], row: serialIndex) as? SMARTTextCell
            check(masked?.label.stringValue == "••••••••", "identifier masking replaces reused cell text")
        }
        table.scrollRowToVisible(table.numberOfRows - 1); table.layoutSubtreeIfNeeded()
        let lastRow = coordinator.tableView(table, rowViewForRow: table.numberOfRows - 1) as? SMARTNativeRow
        check(lastRow?.spanningLabel.stringValue == prepared.rows.last?.cells.first?.masked, "last original output line reachable and complete")
        if let other = store.disks.first(where: { $0.id != prepared.diskID }) {
            coordinator.update(SMARTPresentation(other), showSerial: false, scroll: scroll)
            check(scroll.contentView.bounds.origin.y == -scroll.contentInsets.top, "disk switch resets scroll position below header")
            coordinator.update(prepared, showSerial: false, scroll: scroll)
        }
    }
    static func validateClicks(_ store: DiskStore, index: Int) {
        guard index < 3 else { fflush(stdout); NSApp.terminate(nil); return }
        guard let target = store.disks.first(where: { $0.id != store.selection }),
              let probe = DiskHitProbe.views[target.id], let window = probe.window,
              probe.bounds.width >= 239, probe.bounds.height >= 100 else { fatalError("UI FAIL: full-width disk hit area missing") }
        let points = [NSPoint(x: probe.bounds.width - 4, y: probe.bounds.midY), NSPoint(x: 4, y: 4), NSPoint(x: probe.bounds.width - 4, y: probe.bounds.height - 4)]
        let point = probe.convert(points[index], to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: index + 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { fatalError("UI FAIL: mouse event creation") }
            window.sendEvent(event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard store.selection == target.id else { fatalError("UI FAIL: blank-space disk click \(index)") }
            print("UI PASS: disk blank-space click \(index + 1), hit area \(Int(probe.bounds.width)) × \(Int(probe.bounds.height)) pt")
            validateClicks(store, index: index + 1)
        }
    }
    static func step(_ store: DiskStore, index: Int) {
        guard index < 24 else {
            guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                  let table = findTable(root), let delegate = table.delegate as? SMARTMetricsTable.Coordinator else { fatalError("UI benchmark missing native metrics table") }
            validateTable(table, coordinator: delegate, store: store)
            if let path = ProcessInfo.processInfo.environment["SMARTINFO_UI_IMAGE"], let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.layoutSubtreeIfNeeded(); root.cacheDisplay(in: root.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
            }
            let values = samples.sorted()
            print(String(format: "UI SWITCH: n=%d median=%.2f ms p95=%.2f ms max=%.2f ms (16 ms frame delay included)", values.count, values[values.count / 2], values[Int(Double(values.count - 1) * 0.95)], values.last!))
            validateClicks(store, index: 0)
            return
        }
        let begin = ProcessInfo.processInfo.systemUptime
        store.selection = store.disks[(index + 1) % store.disks.count].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
            }
            let elapsed = (ProcessInfo.processInfo.systemUptime - begin) * 1000
            if index >= 4 { samples.append(elapsed) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { step(store, index: index + 1) }
        }
    }
}

// Test-only geometry marker. It never handles mouse events itself.
struct DiskHitProbe: NSViewRepresentable {
    static var views: [String: DiskHitProbeView] = [:]
    let diskID: String
    func makeNSView(context: Context) -> DiskHitProbeView {
        let view = DiskHitProbeView(); view.diskID = diskID; Self.views[diskID] = view; return view
    }
    func updateNSView(_ view: DiskHitProbeView, context: Context) { }
    static func dismantleNSView(_ view: DiskHitProbeView, coordinator: ()) { views.removeValue(forKey: view.diskID) }
}
final class DiskHitProbeView: NSView {
    var diskID = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ViewState: ObservableObject {
    @Published var section = "全部指标"
    @Published var deviceType = "auto"
    @Published var showSerial = false
    var revealedDisk: String?
}

struct ContentView: View {
    @EnvironmentObject var store: DiskStore
    @StateObject private var local = ViewState()
    private var section: String { get { local.section } nonmutating set { local.section = newValue } }
    private var deviceType: String { get { local.deviceType } nonmutating set { local.deviceType = newValue } }
    private var showSerial: Bool {
        get { local.showSerial && local.revealedDisk == store.selection }
        nonmutating set { local.revealedDisk = newValue ? store.selection : nil; if local.showSerial != newValue { local.showSerial = newValue } }
    }
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    let ink = Color(red: 0.13, green: 0.18, blue: 0.27)
    let canvas = Color(red: 0.96, green: 0.97, blue: 0.99)

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 252)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.07))
                }
                if let disk = store.selected {
                    VStack(alignment: .leading, spacing: 18) {
                        diskHeading(disk)
                        HStack(spacing: 5) {
                            ForEach(["概览", "全部指标", "诊断信息"], id: \.self) { item in
                                Button { section = item } label: {
                                    Text(item).font(.system(size: 13, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 9)
                                        .foregroundStyle(section == item ? Color.blue : Color.secondary)
                                        .background(section == item ? Color.blue.opacity(0.09) : .clear).clipShape(RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)
                    if section == "全部指标" {
                        allMetrics(disk).padding(.horizontal, 28).padding(.bottom, 24)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                if section == "概览" { overview(disk) }
                                else { diagnostics(disk) }
                            }.padding(.horizontal, 28).padding(.bottom, 28)
                        }
                    }
                } else { emptyState }
                footer
            }.background(canvas)
        }
        .tint(.blue)
        .onAppear {
            if CommandLine.arguments.contains("--benchmark-ui") { SwitchBenchmark.start(store) }
            else { store.refresh() }
        }
        .onReceive(timer) { _ in if store.automatic { store.refresh() } }
        .onChange(of: store.selection) { _ in
            if deviceType != "auto" { deviceType = "auto" }
            if local.showSerial { showSerial = false }
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "externaldrive.fill.badge.checkmark").font(.system(size: 29)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SMART Info").font(.system(size: 20, weight: .semibold)).foregroundStyle(ink)
                    Text("Native · Apple Silicon").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 23).padding(.top, 27).padding(.bottom, 30)
            HStack { Text("物理磁盘").font(.system(size: 12, weight: .medium)); Spacer(); Text("\(store.disks.count)").font(.system(size: 12)).foregroundStyle(.secondary) }
                .padding(.horizontal, 24).padding(.bottom, 13)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(store.disks) { disk in
                        Button { store.select(disk.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: disk.internalDisk ? "internaldrive" : "externaldrive").font(.system(size: 23)).foregroundStyle(store.selection == disk.id ? .blue : .secondary).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(disk.name).font(.system(size: 13, weight: .medium)).foregroundStyle(ink).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(disk.id) · \(byteString(disk.capacity))").font(.system(size: 11)).foregroundStyle(.secondary)
                                    HStack(spacing: 5) { Circle().fill(store.health(disk).tint).frame(width: 6, height: 6); Text(store.health(disk).title).font(.system(size: 11)).foregroundStyle(store.health(disk).tint) }
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 16).padding(.vertical, 16)
                                .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                                .background(store.selection == disk.id ? Color.blue.opacity(0.07) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(.interaction, Rectangle())
                                .background {
                                    if CommandLine.arguments.contains("--benchmark-ui") { DiskHitProbe(diskID: disk.id) }
                                }
                        }.buttonStyle(.plain).accessibilityIdentifier("disk-select-" + disk.id)
                    }
                }.padding(.horizontal, 6)
            }
            Spacer(minLength: 12)
            Text("v1.1.3").font(.system(size: 11)).foregroundStyle(.secondary).padding(23)
        }.background(.white)
    }

    var header: some View {
        HStack(spacing: 12) {
            Text("磁盘健康").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink)
            Spacer()
            Toggle("每分钟刷新", isOn: $store.automatic).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            Button { store.exportSelected() } label: { Label("导出", systemImage: "square.and.arrow.up") }.disabled(store.selected == nil || store.busy)
            Button { store.refresh() } label: {
                HStack(spacing: 6) {
                    if store.busy { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14) }
                    else { Image(systemName: "arrow.clockwise") }
                    Text(store.busy ? "读取中" : "刷新")
                }
            }.buttonStyle(.borderedProminent).disabled(store.busy).keyboardShortcut("r")
        }.padding(.horizontal, 28).padding(.vertical, 19).background(.white)
    }

    func diskHeading(_ disk: DiskSnapshot) -> some View {
        HStack(spacing: 17) {
            Image(systemName: disk.internalDisk ? "internaldrive.fill" : "externaldrive.fill").font(.system(size: 37)).foregroundStyle(.blue)
                .frame(width: 70, height: 70).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 8) {
                Text(disk.name).font(.system(size: 25, weight: .semibold)).foregroundStyle(ink).textSelection(.enabled)
                Text("\(disk.node)  ·  \(disk.internalDisk ? "内置磁盘" : "外接磁盘")  ·  \(disk.bus)  ·  \(disk.protocolName)")
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text(byteString(disk.capacity)).font(.system(size: 19, weight: .medium)).foregroundStyle(ink)
        }
    }

    func overview(_ disk: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 17) {
                Image(systemName: store.health(disk).symbol).font(.system(size: 38)).foregroundStyle(store.health(disk).tint)
                Text(store.health(disk).title).font(.system(size: 19, weight: .semibold)).foregroundStyle(store.health(disk).tint)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("数据来源").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(disk.source).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                }
            }.padding(22).background(store.health(disk).tint.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 15))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metric("当前温度", value: disk.temperature.map { String(format: "%.0f °C", $0) } ?? "—", icon: "thermometer.medium", color: (disk.temperature ?? 0) >= (SMARTDetails.temperatureThreshold("warning", disk: disk) ?? 70) ? .orange : .blue)
                metric(disk.isNVMe ? "寿命已用" : "重映射扇区", value: disk.isNVMe ? disk.percentageUsed.map { "\(integerString($0)) %" } ?? "—" : integerString(disk.reallocated), icon: "chart.bar.xaxis", color: .blue)
                metric("通电时长", value: disk.powerHours.map { "\(integerString($0)) h" } ?? "—", icon: "clock", color: .blue)
                metric("累计读取", value: byteString(disk.bytesRead), icon: "arrow.down.circle", color: .blue)
                metric("累计写入", value: byteString(disk.bytesWritten), icon: "arrow.up.circle", color: .blue)
                metric(disk.isNVMe ? "介质错误" : "待映射扇区", value: integerString(disk.isNVMe ? disk.mediaErrors : disk.pendingSectors), icon: "exclamationmark.circle", color: ((disk.mediaErrors ?? disk.pendingSectors) ?? 0) > 0 ? .orange : .blue)
            }
            infoPanel(disk)
        }
    }

    func metric(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(color).font(.system(size: 15)) }
            Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(ink).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }

    func infoPanel(_ disk: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设备信息").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 13) {
                    infoRow("固件版本", disk.firmware ?? "未提供")
                    HStack(spacing: 8) {
                        Text("序列号").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                        Text(showSerial ? disk.serial ?? "未提供" : disk.serial == nil ? "未提供" : "••••••••").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        Button { showSerial.toggle() } label: { Image(systemName: showSerial ? "eye.slash" : "eye") }.buttonStyle(.plain).foregroundStyle(.blue).help("显示或隐藏序列号")
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 13) { infoRow("启动次数", integerString(disk.powerCycles)); infoRow("非正常断电", integerString(disk.unsafeShutdowns)) }
            }
        }.padding(22).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) { Text(label).foregroundStyle(.secondary).frame(width: 76, alignment: .leading); Text(value).foregroundStyle(ink).textSelection(.enabled) }.font(.system(size: 12))
    }
    func allMetrics(_ disk: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("SMART 明细").font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                Spacer(minLength: 0)
                if let prepared = store.selectedPresentation, !prepared.rawOutput.isEmpty {
                    Button("复制输出") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(showSerial ? prepared.rawOutput : prepared.maskedOutput, forType: .string)
                    }.font(.system(size: 11))
                }
                Button { showSerial.toggle() } label: { Label(showSerial ? "隐藏标识" : "显示标识", systemImage: showSerial ? "eye.slash" : "eye") }.font(.system(size: 11))
            }.padding(16)
            Divider()
            if let prepared = store.selectedPresentation {
                SMARTMetricsTable(presentation: prepared, showSerial: showSerial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    func diagnostics(_ disk: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("读取诊断").font(.system(size: 16, weight: .semibold))
                HStack {
                    Text("桥接模式").font(.system(size: 12))
                    Picker("桥接模式", selection: $local.deviceType) {
                        Text("自动识别").tag("auto"); Text("SATA / SAT").tag("sat"); Text("Realtek NVMe").tag("sntrealtek"); Text("JMicron NVMe").tag("sntjmicron"); Text("ASMedia NVMe").tag("sntasmedia")
                    }.labelsHidden().frame(width: 185)
                    Button("重新读取此盘") { store.reread(type: deviceType) }.disabled(store.busy || DiskService.enginePath == nil)
                    Spacer()
                }
                Divider()
                if disk.messages.isEmpty {
                    Label("无读取错误", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.green)
                } else {
                    ForEach(Array(disk.messages.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }.padding(23).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("原始数据").font(.system(size: 16, weight: .semibold)); Spacer(); Button("导出 JSON…") { store.exportSelected() } }
                ScrollView([.horizontal, .vertical]) {
                    Text(disk.rawData.isEmpty ? "尚无数据" : disk.rawData).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.frame(height: 300).background(canvas).clipShape(RoundedRectangle(cornerRadius: 10))
            }.padding(23).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    var emptyState: some View {
        VStack(spacing: 18) {
            if store.busy { ProgressView().controlSize(.large); Text("读取中…").font(.system(size: 15)) }
            else {
                Image(systemName: "externaldrive.badge.questionmark").font(.system(size: 54)).foregroundStyle(.blue)
                Text("未发现磁盘").font(.system(size: 20, weight: .medium))
                Button("重新扫描") { store.refresh() }.buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var footer: some View {
        HStack(spacing: 8) {
            if store.busy { Text(store.operation).font(.system(size: 11)).foregroundStyle(.secondary) }
            if let date = store.lastUpdate { Text("更新 \(date.formatted(date: .omitted, time: .standard))").font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer()
            Text("\(store.disks.count) 块磁盘").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 27).padding(.vertical, 12).background(.white)
    }
}

// One bounded native scroll view; NSTableView only creates/reuses visible rows.
struct SMARTMetricsTable: NSViewRepresentable {
    let presentation: SMARTPresentation
    let showSerial: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SMARTTableContainer {
        let container = SMARTTableContainer()
        let scroll = container.scroll
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false; scroll.borderType = .noBorder
        scroll.scrollerStyle = .legacy
        scroll.automaticallyAdjustsContentInsets = false
        let table = NSTableView()
        table.identifier = NSUserInterfaceItemIdentifier("SMARTMetricsTable")
        table.style = .plain
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = true
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAutomaticRowHeights = false
        table.allowsColumnReordering = false; table.allowsColumnResizing = false
        for (index, width) in SMARTPresentation.widths.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = SMARTPresentation.headings[index]
            column.width = width; column.minWidth = width; column.maxWidth = width
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.headerView = nil
        table.frame = NSRect(x: 0, y: 0, width: SMARTPresentation.widths.reduce(0, +), height: 0)
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        return container
    }
    func updateNSView(_ container: SMARTTableContainer, context: Context) {
        context.coordinator.update(presentation, showSerial: showSerial, scroll: container.scroll)
    }
    static func dismantleNSView(_ container: SMARTTableContainer, coordinator: Coordinator) {
        coordinator.table?.delegate = nil; coordinator.table?.dataSource = nil
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        var presentation: SMARTPresentation?
        var showSerial = false
        var reloads = 0
        func update(_ next: SMARTPresentation, showSerial: Bool, scroll: NSScrollView) {
            guard let table else { return }
            guard presentation?.revision != next.revision || self.showSerial != showSerial else { return }
            let switched = presentation?.diskID != next.diskID
            let origin = scroll.contentView.bounds.origin
            // Discard any field-editor selection before reused cells receive another disk.
            if table.window?.firstResponder is NSTextView { table.window?.makeFirstResponder(table) }
            presentation = next; self.showSerial = showSerial
            table.reloadData(); reloads += 1
            if switched { scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top)) }
            else {
                let y = max(-scroll.contentInsets.top, min(origin.y, max(0, table.bounds.height - scroll.contentView.bounds.height)))
                scroll.contentView.scroll(to: NSPoint(x: origin.x, y: y))
            }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func numberOfRows(in tableView: NSTableView) -> Int { presentation?.rows.count ?? 0 }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { presentation!.rows[row].height }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard let row = presentation?.rows[index], !row.spanning,
                  let column = tableColumn, let index = Int(column.identifier.rawValue), index < row.cells.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("metric-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SMARTTextCell ?? SMARTTextCell()
            cell.identifier = identifier
            let value = row.cells[index]
            cell.configure(value, showSerial: showSerial, color: index == 5 ? color(row.tone) : row.tone == .unavailable ? .secondaryLabelColor : .labelColor)
            return cell
        }
        func tableView(_ tableView: NSTableView, rowViewForRow index: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("smart-row")
            let view = tableView.makeView(withIdentifier: id, owner: self) as? SMARTNativeRow ?? SMARTNativeRow()
            view.identifier = id
            if let row = presentation?.rows[index] { view.configure(row, showSerial: showSerial) }
            return view
        }
        func color(_ tone: DetailTone) -> NSColor {
            switch tone { case .alert: return .systemRed; case .caution: return .systemOrange; default: return .secondaryLabelColor }
        }
    }
}

final class SMARTTableContainer: NSView {
    let scroll = NSScrollView()
    let header = NSScrollView()
    var observer: NSObjectProtocol?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let headings = NSView(frame: NSRect(x: 0, y: 0, width: SMARTPresentation.widths.reduce(0, +), height: 30))
        headings.wantsLayer = true; headings.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        var x: CGFloat = 0
        for (index, width) in SMARTPresentation.widths.enumerated() {
            let label = NSTextField(labelWithString: SMARTPresentation.headings[index])
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.frame = NSRect(x: x + 10, y: 8, width: width - 20, height: 16)
            headings.addSubview(label); x += width
        }
        header.documentView = headings
        header.hasHorizontalScroller = false; header.hasVerticalScroller = false
        header.automaticallyAdjustsContentInsets = false
        addSubview(scroll); addSubview(header)
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.header.contentView.scroll(to: NSPoint(x: self.scroll.contentView.bounds.origin.x, y: 0))
        }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: max(0, bounds.height - 30), width: bounds.width, height: 30)
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 30))
    }
}

final class SMARTTextCell: NSTableCellView {
    let label = NSTextField(wrappingLabelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.isEditable = false; label.isSelectable = true
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
        addSubview(label); textField = label
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func configure(_ cell: SMARTDisplayCell, showSerial: Bool, color: NSColor) {
        label.stringValue = showSerial ? cell.text : cell.masked
        label.font = cell.font; label.textColor = color
        needsLayout = true
    }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: 10, width: max(0, bounds.width - 20), height: max(0, bounds.height - 20))
        label.preferredMaxLayoutWidth = max(0, bounds.width - 20)
    }
}

final class SMARTNativeRow: NSTableRowView {
    let spanningLabel = NSTextField(wrappingLabelWithString: "")
    var group = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        spanningLabel.isEditable = false; spanningLabel.isSelectable = true
        spanningLabel.maximumNumberOfLines = 0; spanningLabel.lineBreakMode = .byWordWrapping
        addSubview(spanningLabel)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func configure(_ row: SMARTDisplayRow, showSerial: Bool) {
        group = row.group; spanningLabel.isHidden = !row.spanning
        if row.spanning {
            if row.group {
                spanningLabel.stringValue = row.cells.map { $0.text }.filter { !$0.isEmpty }.joined(separator: "   ·   ")
                spanningLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            } else {
                spanningLabel.stringValue = showSerial ? row.cells[0].text : row.cells[0].masked
                spanningLabel.font = row.cells[0].font
            }
            spanningLabel.textColor = .labelColor
        } else { spanningLabel.stringValue = "" }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        spanningLabel.frame = NSRect(x: 10, y: 10, width: max(0, bounds.width - 20), height: max(0, bounds.height - 20))
        spanningLabel.preferredMaxLayoutWidth = max(0, bounds.width - 20)
    }
    override func drawBackground(in dirtyRect: NSRect) {
        if group { NSColor.systemBlue.withAlphaComponent(0.07).setFill(); dirtyRect.fill() }
        else { super.drawBackground(in: dirtyRect) }
    }
}
