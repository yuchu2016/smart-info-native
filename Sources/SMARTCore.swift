import Foundation
import Darwin

struct CommandResult {
    let output: Data
    let error: String
    let status: Int32
    let timedOut: Bool
}

enum CommandRunner {
    static func run(_ executable: String, _ arguments: [String], timeout: Double = 12) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() }
        catch { return CommandResult(output: Data(), error: error.localizedDescription, status: -1, timedOut: false) }
        let readers = DispatchGroup()
        let lock = NSLock()
        var output = Data(), errors = Data()
        readers.enter()
        DispatchQueue.global().async {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); output = data; lock.unlock(); readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); errors = data; lock.unlock(); readers.leave()
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
        }
        readers.wait()
        return CommandResult(output: output, error: String(data: errors, encoding: .utf8) ?? "", status: process.terminationStatus, timedOut: timedOut)
    }
}

func dictionary(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
    if let s = value as? String, let n = Double(s), n.isFinite { return n }
    return nil
}
func text(_ value: Any?) -> String? {
    guard let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return s
}
func integerString(_ n: Double?) -> String {
    guard let n else { return "—" }
    return n.formatted(.number.precision(.fractionLength(0)))
}
func byteString(_ n: Double?) -> String {
    guard let n, n >= 0 else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = n, index = 0
    while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
    return String(format: "%.2f %@", value, units[index])
}

enum Health: String, Codable {
    case good, caution, failed, unknown
    var title: String {
        switch self { case .good: return "状态正常"; case .caution: return "需要关注"; case .failed: return "健康告警"; case .unknown: return "状态未知" }
    }
    var symbol: String {
        switch self { case .good: return "checkmark.shield.fill"; case .caution: return "exclamationmark.shield.fill"; case .failed: return "xmark.shield.fill"; case .unknown: return "questionmark.circle.fill" }
    }
}

struct Attribute: Identifiable {
    let id: Int
    let name: String
    let value: String
    let worst: String
    let threshold: String
    let raw: String
    let failing: Bool
    var whenFailed: String = "未提供"
    var flags: [String: Any] = [:]
    var original: [String: Any] = [:]
    var reachedThreshold: Bool {
        guard let current = Double(value.replacingOccurrences(of: ",", with: "")), let limit = Double(threshold.replacingOccurrences(of: ",", with: "")), limit > 0 else { return false }
        return current <= limit
    }
}

struct DiskSnapshot: Identifiable {
    let id: String
    var name: String
    var node: String
    var capacity: Double?
    var internalDisk: Bool
    var bus: String
    var protocolName: String
    var serial: String?
    var firmware: String?
    var source: String
    var smartPassed: Bool?
    var temperature: Double?
    var percentageUsed: Double?
    var availableSpare: Double?
    var spareThreshold: Double?
    var powerHours: Double?
    var powerCycles: Double?
    var unsafeShutdowns: Double?
    var bytesRead: Double?
    var bytesWritten: Double?
    var mediaErrors: Double?
    var errorEntries: Double?
    var criticalWarning: Double?
    var reallocated: Double?
    var pendingSectors: Double?
    var uncorrectable: Double?
    var attributes: [Attribute] = []
    var nvmeFields: [String: Any] = [:]
    var systemFields: [String: Any] = [:]
    var engineJSON: [String: Any] = [:]
    var systemJSON: [String: Any] = [:]
    var messages: [String] = []
    var rawData: String = ""
    var observed = Date()
    var hasHealthData: Bool { smartPassed != nil || temperature != nil || percentageUsed != nil || !attributes.isEmpty }
    var health: Health {
        if smartPassed == false { return .failed }
        if (criticalWarning ?? 0) > 0 { return .failed }
        if attributes.contains(where: { $0.failing || $0.reachedThreshold }) || (pendingSectors ?? 0) > 0 || (uncorrectable ?? 0) > 0 { return .failed }
        if (percentageUsed ?? 0) >= 100 || (mediaErrors ?? 0) > 0 || (reallocated ?? 0) > 0 { return .caution }
        if let spare = availableSpare, let threshold = spareThreshold, spare < threshold { return .caution }
        if let t = temperature {
            if let critical = SMARTDetails.temperatureThreshold("critical", disk: self), t >= critical { return .failed }
            let warning = SMARTDetails.temperatureThreshold("warning", disk: self) ?? 70
            if t >= warning { return .caution }
        }
        return smartPassed == true ? .good : .unknown
    }
    var healthDetail: String {
        switch health {
        case .failed: return "设备报告告警或异常指标，请优先备份重要数据。"
        case .caution: return "存在需要关注的指标，请结合厂商标准与历史变化判断。"
        case .good: return "设备 SMART 检查通过；这不代表不会发生故障。"
        case .unknown: return "没有取得明确的 SMART 健康结论，不能判断为正常。"
        }
    }
    var isNVMe: Bool { protocolName.uppercased().contains("NVME") || percentageUsed != nil }
}

enum SMARTParser {
    static func initial(id: String, info: [String: Any]) -> DiskSnapshot {
        var disk = DiskSnapshot(id: id, name: text(info["MediaName"]) ?? text(info["IORegistryEntryName"]) ?? id,
                                node: text(info["DeviceNode"]) ?? "/dev/\(id)", capacity: number(info["TotalSize"]) ?? number(info["Size"]),
                                internalDisk: info["Internal"] as? Bool ?? false, bus: text(info["BusProtocol"]) ?? "未知接口",
                                protocolName: "未知", source: "macOS 磁盘服务")
        switch text(info["SMARTStatus"]) {
        case "Verified": disk.smartPassed = true
        case "Failing": disk.smartPassed = false
        default: disk.smartPassed = nil
        }
        disk.systemJSON = info
        let system = dictionary(info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"])
        disk.systemFields = system
        if !system.isEmpty {
            disk.protocolName = "NVMe"
            disk.source = "macOS 原生 SMART"
            func counter(_ key: String) -> Double? {
                guard let low = number(system[key + "_0"]) else { return nil }
                return low + (number(system[key + "_1"]) ?? 0) * 18446744073709551616
            }
            if let kelvin = number(system["TEMPERATURE"]), kelvin > 0 { disk.temperature = kelvin - 273.15 }
            disk.percentageUsed = number(system["PERCENTAGE_USED"])
            disk.availableSpare = number(system["AVAILABLE_SPARE"])
            disk.spareThreshold = number(system["AVAILABLE_SPARE_THRESHOLD"])
            disk.powerHours = counter("POWER_ON_HOURS")
            disk.powerCycles = counter("POWER_CYCLES")
            disk.unsafeShutdowns = counter("UNSAFE_SHUTDOWNS")
            disk.mediaErrors = counter("MEDIA_ERRORS")
            disk.errorEntries = counter("NUM_ERROR_INFO_LOG_ENTRIES")
            disk.bytesRead = counter("DATA_UNITS_READ").map { $0 * 512000 }
            disk.bytesWritten = counter("DATA_UNITS_WRITTEN").map { $0 * 512000 }
        }
        return disk
    }

    static func apply(json: [String: Any], to original: DiskSnapshot) -> DiskSnapshot {
        var disk = original
        disk.engineJSON = json
        disk.nvmeFields = dictionary(json["nvme_smart_health_information_log"])
        SMARTDetails.captureThermalOutput(json: json, fields: &disk.nvmeFields)
        let device = dictionary(json["device"])
        disk.name = text(json["model_name"]) ?? text(json["scsi_model_name"]) ?? disk.name
        disk.serial = text(json["serial_number"])
        disk.firmware = text(json["firmware_version"]) ?? text(json["scsi_revision"])
        disk.protocolName = text(device["protocol"]) ?? text(device["type"]) ?? disk.protocolName
        disk.capacity = number(dictionary(json["user_capacity"])["bytes"]) ?? disk.capacity
        if let passed = dictionary(json["smart_status"])["passed"] as? Bool { disk.smartPassed = passed }
        disk.temperature = number(dictionary(json["temperature"])["current"]) ?? disk.temperature
        disk.powerHours = number(dictionary(json["power_on_time"])["hours"]) ?? disk.powerHours
        disk.powerCycles = number(json["power_cycle_count"]) ?? disk.powerCycles
        let nvme = dictionary(json["nvme_smart_health_information_log"])
        if !nvme.isEmpty {
            disk.protocolName = "NVMe"
            disk.temperature = number(nvme["temperature"]) ?? disk.temperature
            disk.percentageUsed = number(nvme["percentage_used"]) ?? disk.percentageUsed
            disk.availableSpare = number(nvme["available_spare"]) ?? disk.availableSpare
            disk.spareThreshold = number(nvme["available_spare_threshold"]) ?? disk.spareThreshold
            disk.criticalWarning = number(nvme["critical_warning"])
            disk.unsafeShutdowns = number(nvme["unsafe_shutdowns"]) ?? disk.unsafeShutdowns
            disk.mediaErrors = number(nvme["media_errors"]) ?? disk.mediaErrors
            disk.errorEntries = number(nvme["num_err_log_entries"]) ?? disk.errorEntries
            disk.powerHours = number(nvme["power_on_hours"]) ?? disk.powerHours
            disk.powerCycles = number(nvme["power_cycles"]) ?? disk.powerCycles
            disk.bytesRead = number(nvme["data_units_read"]).map { $0 * 512000 } ?? disk.bytesRead
            disk.bytesWritten = number(nvme["data_units_written"]).map { $0 * 512000 } ?? disk.bytesWritten
        }
        let table = dictionary(json["ata_smart_attributes"])["table"] as? [[String: Any]] ?? []
        disk.attributes = table.compactMap { row in
            guard let n = number(row["id"]), n >= 0, n <= 255, n.rounded(.towardZero) == n else { return nil }
            let raw = dictionary(row["raw"])
            let failure = text(row["when_failed"])
            return Attribute(id: Int(n), name: text(row["name"]) ?? "属性 \(Int(n))", value: integerString(number(row["value"])), worst: integerString(number(row["worst"])), threshold: integerString(number(row["thresh"])), raw: text(raw["string"]) ?? integerString(number(raw["value"])), failing: failure != nil && failure != "-" && failure != "never", whenFailed: failure ?? "未提供", flags: dictionary(row["flags"]), original: row)
        }
        func ataRaw(_ names: [String]) -> Double? {
            table.first(where: { row in names.contains(text(row["name"]) ?? "") }).flatMap { number(dictionary($0["raw"])["value"]) }
        }
        disk.reallocated = ataRaw(["Reallocated_Sector_Ct", "Reallocated_Block_Count"])
        disk.pendingSectors = ataRaw(["Current_Pending_Sector"])
        disk.uncorrectable = ataRaw(["Offline_Uncorrectable"])
        if !nvme.isEmpty || !table.isEmpty || dictionary(json["smart_status"])["passed"] != nil {
            disk.source = "smartctl 原生引擎"
        }
        let warnings = dictionary(json["smartctl"])["messages"] as? [[String: Any]] ?? []
        disk.messages += warnings.compactMap { text($0["string"]) }
        return disk
    }
}

struct ScanResult { let disks: [DiskSnapshot]; let error: String?; let engineVersion: String }

enum DiskService {
    static var enginePath: String? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("smartctl").path,
           FileManager.default.isExecutableFile(atPath: resource) { return resource }
        if let custom = ProcessInfo.processInfo.environment["SMARTINFO_ENGINE"], FileManager.default.isExecutableFile(atPath: custom) { return custom }
        for p in ["/opt/homebrew/sbin/smartctl", "/opt/homebrew/bin/smartctl", "/usr/local/sbin/smartctl", "/usr/local/bin/smartctl"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
    static func plist(_ data: Data) -> [String: Any] {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return [:] }
        return dictionary(object)
    }
    static func read(id: String, deviceType: String = "auto") -> DiskSnapshot? {
        guard id.range(of: "^disk[0-9]+$", options: .regularExpression) != nil else { return nil }
        let result = CommandRunner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(id)"])
        let info = plist(result.output)
        guard !info.isEmpty else { return nil }
        var disk = SMARTParser.initial(id: id, info: info)
        var raw: [String: Any] = ["device": id, "observed_at": ISO8601DateFormatter().string(from: Date()), "diskutil": info]
        if let engine = enginePath {
            var arguments = ["-x", "--json=ov"]
            if deviceType != "auto" { arguments += ["-d", deviceType] }
            arguments += [disk.node]
            let engineResult = CommandRunner.run(engine, arguments)
            if let json = try? JSONSerialization.jsonObject(with: engineResult.output) as? [String: Any] {
                disk = SMARTParser.apply(json: json, to: disk)
                raw["smartctl"] = json
            } else {
                disk.messages.append(engineResult.timedOut ? "smartctl 读取超时（12 秒）" : "smartctl 返回无效 JSON")
            }
            if !engineResult.error.isEmpty { disk.messages.append(engineResult.error.trimmingCharacters(in: .whitespacesAndNewlines)) }
            raw["smartctl_exit_code"] = engineResult.status
            raw["smartctl_timeout"] = engineResult.timedOut
        }
        if !disk.hasHealthData {
            disk.messages.insert("未取得 SMART 数据", at: 0)
        }
        if let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) { disk.rawData = string }
        return disk
    }
    static func scan() -> ScanResult {
        let result = CommandRunner.run("/usr/sbin/diskutil", ["list", "-plist", "physical"])
        let info = plist(result.output)
        guard result.status == 0, !info.isEmpty else {
            return ScanResult(disks: [], error: result.timedOut ? "磁盘扫描超时" : "无法列举物理磁盘。\(result.error)", engineVersion: "macOS 原生")
        }
        let ids = info["WholeDisks"] as? [String] ?? []
        let disks = ids.compactMap { read(id: $0) }.sorted {
            if $0.internalDisk != $1.internalDisk { return $0.internalDisk }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        var version = "macOS 原生"
        if let engine = enginePath {
            let r = CommandRunner.run(engine, ["--version"], timeout: 5)
            if let line = String(data: r.output, encoding: .utf8)?.components(separatedBy: .newlines).first { version = line }
        }
        let error: String? = disks.count < ids.count ? "部分磁盘已断开或读取失败" : nil
        return ScanResult(disks: disks, error: error, engineVersion: version)
    }
}
