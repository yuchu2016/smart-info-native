import Foundation
import CoreFoundation
import AppKit

enum DetailTone { case neutral, good, caution, alert, unavailable }
struct SMARTDetail: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let reference: String
    let meaning: String
    let status: String
    let tone: DetailTone
    var sensitive: Bool = false
}
struct MetricSpec {
    let key: String
    let title: String
    let unit: String
    let reference: String
    let meaning: String
}
struct ATAMeaning {
    let title: String
    let unit: String
    let meaning: String
}

enum SMARTDetails {
    static let specs: [MetricSpec] = [
        .init(key: "critical_warning", title: "关键告警位掩码", unit: "位掩码", reference: "0 表示没有当前关键告警", meaning: "每一个置位代表一种当前告警；下方逐位展开，不是历史故障计数。"),
        .init(key: "temperature", title: "复合温度", unit: "°C", reference: "优先参考设备 WCTEMP / CCTEMP", meaning: "控制器与闪存子系统的综合温度，不能假定等于任意一个传感器。"),
        .init(key: "available_spare", title: "可用备用空间", unit: "%", reference: "应不低于设备报告的备用阈值", meaning: "可用于替换损耗单元的备用容量百分比；不是文件系统剩余空间。"),
        .init(key: "available_spare_threshold", title: "备用空间告警阈值", unit: "%", reference: "由设备报告，不使用通用默认值", meaning: "当可用备用容量低于此值，控制器可报告关键告警。"),
        .init(key: "percentage_used", title: "寿命已用", unit: "%", reference: "100% 表示估计耐久额度已使用完", meaning: "厂商依据实际使用估计的耐久消耗；允许超过 100%，不等于已损坏或故障概率。"),
        .init(key: "data_units_read", title: "累计读取数据单位", unit: "× 512,000 B", reference: "累计计数，无通用上限", meaning: "每个单位为 1,000 × 512 字节，按千单位向上取整，不含元数据；换算容量为近似值。"),
        .init(key: "data_units_written", title: "累计写入数据单位", unit: "× 512,000 B", reference: "结合厂商 TBW 与使用场景", meaning: "主机累计写入量，不含元数据，不等于 NAND 实际写入量或写入放大。"),
        .init(key: "host_reads", title: "主机读取命令数", unit: "次", reference: "累计计数，无通用上限", meaning: "控制器完成的读取命令数量；含 NVMe Compare 与 Read，不是文件数。"),
        .init(key: "host_writes", title: "主机写入命令数", unit: "次", reference: "累计计数，无通用上限", meaning: "控制器完成的写入命令数量，不是写入字节数。"),
        .init(key: "controller_busy_time", title: "控制器忙碌时间", unit: "分钟", reference: "累计计数，不能据此判断性能", meaning: "控制器存在尚未完成的 I/O 命令的累计时间；不是应用运行时长。"),
        .init(key: "power_cycles", title: "通电次数", unit: "次", reference: "累计计数，无通用上限", meaning: "控制器经历的电源周期次数，不等于操作系统启动次数。"),
        .init(key: "power_on_hours", title: "通电时长", unit: "小时", reference: "累计计数，无通用上限", meaning: "控制器报告的累计通电小时，可能不包含处于某些低功耗状态的时间。"),
        .init(key: "unsafe_shutdowns", title: "非正常断电次数", unit: "次", reference: "关注增长趋势；非 0 不代表坏盘", meaning: "断电前未收到规范关机通知的累计次数；意外断电、桥接行为等均可能影响。"),
        .init(key: "media_errors", title: "介质与数据完整性错误", unit: "次", reference: "理想值为 0；大于 0 需关注", meaning: "控制器检测到的不可恢复数据完整性错误，例如不可纠正 ECC、校验失败或 LBA 标记不匹配。"),
        .init(key: "num_err_log_entries", title: "错误信息日志条目数", unit: "条", reference: "须结合错误类型，不等于坏扇区数", meaning: "控制器生命周期内生成的错误日志条目总计，包含非介质错误；与当前可读取日志条数不同。"),
        .init(key: "warning_temp_time", title: "警告温度累计时间", unit: "分钟", reference: "大于 0 表示曾处于警告温区", meaning: "复合温度处于警告阈值 WCTEMP 与临界阈值 CCTEMP 之间的累计时间。阈值未实现时 0 不证明从未过热。"),
        .init(key: "critical_comp_time", title: "临界温度累计时间", unit: "分钟", reference: "大于 0 需检查散热历史", meaning: "控制器报告的复合温度处于临界温区的累计时间，不代表当前仍然过热。"),
        .init(key: "thermal_mgmt_temp1_transition_count", title: "一级热管理触发次数", unit: "次", reference: "关注增长趋势与负载", meaning: "控制器为降低温度进入一级热管理状态的累计次数。"),
        .init(key: "thermal_mgmt_temp2_transition_count", title: "二级热管理触发次数", unit: "次", reference: "关注增长趋势与负载", meaning: "控制器为降低温度进入二级热管理状态的累计次数。"),
        .init(key: "thermal_mgmt_temp1_total_time", title: "一级热管理累计时间", unit: "秒", reference: "历史时间，非当前降速证明", meaning: "控制器因一级热管理而进行温度控制的累计时间。"),
        .init(key: "thermal_mgmt_temp2_total_time", title: "二级热管理累计时间", unit: "秒", reference: "历史时间，非当前降速证明", meaning: "控制器因二级热管理而进行温度控制的累计时间。"),
        .init(key: "nsid", title: "健康日志命名空间", unit: "ID", reference: "-1 表示全控制器 / 全局日志", meaning: "说明健康日志的适用范围，不能把全局计数当成某一个分区的计数。")
    ]
    static let systemMap = [
        "critical_warning": "CRITICAL_WARNING", "temperature": "TEMPERATURE", "available_spare": "AVAILABLE_SPARE", "available_spare_threshold": "AVAILABLE_SPARE_THRESHOLD", "percentage_used": "PERCENTAGE_USED", "data_units_read": "DATA_UNITS_READ", "data_units_written": "DATA_UNITS_WRITTEN", "host_reads": "HOST_READ_COMMANDS", "host_writes": "HOST_WRITE_COMMANDS", "controller_busy_time": "CONTROLLER_BUSY_TIME", "power_cycles": "POWER_CYCLES", "power_on_hours": "POWER_ON_HOURS", "unsafe_shutdowns": "UNSAFE_SHUTDOWNS", "media_errors": "MEDIA_ERRORS", "num_err_log_entries": "NUM_ERROR_INFO_LOG_ENTRIES"
    ]
    static func captureThermalOutput(json: [String: Any], fields: inout [String: Any]) {
        let lines = dictionary(json["smartctl"])["output"] as? [String] ?? []
        let names = ["Thermal Temp. 1 Transition Count": "thermal_mgmt_temp1_transition_count", "Thermal Temp. 2 Transition Count": "thermal_mgmt_temp2_transition_count", "Thermal Temp. 1 Total Time": "thermal_mgmt_temp1_total_time", "Thermal Temp. 2 Total Time": "thermal_mgmt_temp2_total_time"]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let key = names[parts[0]], fields[key] == nil,
                  let value = UInt64(parts[1]) else { continue }
            fields[key] = NSNumber(value: value)
            fields[key + "_s"] = parts[1]
        }
    }
    static func formatted(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "未提供" }
        if let s = value as? String { return s.isEmpty ? "空字符串" : s }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "是" : "否" }
            return n.stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), let s = String(data: data, encoding: .utf8) { return s }
        return String(describing: value)
    }
    static func metricValue(_ key: String, disk: DiskSnapshot) -> Any? {
        if let exact = text(disk.nvmeFields[key + "_s"]) { return exact }
        if let value = disk.nvmeFields[key], !(value is NSNull) { return value }
        guard let systemKey = systemMap[key] else { return nil }
        if key == "temperature" {
            guard let kelvin = number(disk.systemFields[systemKey]), kelvin > 0 else { return nil }
            return kelvin - 273.15
        }
        if let value = disk.systemFields[systemKey], !(value is NSNull) { return value }
        guard let low = disk.systemFields[systemKey + "_0"] as? NSNumber else { return nil }
        let high = disk.systemFields[systemKey + "_1"] as? NSNumber
        let decimal = low.decimalValue + (high?.decimalValue ?? 0) * Decimal(string: "18446744073709551616")!
        return NSDecimalNumber(decimal: decimal).stringValue
    }
    static func temperatureThreshold(_ key: String, disk: DiskSnapshot) -> Double? {
        let limits = dictionary(disk.engineJSON["nvme_composite_temperature_threshold"])
        return number(limits[key]) ?? number(dictionary(disk.engineJSON["temperature"])[key == "warning" ? "op_limit_max" : "critical_limit_max"])
    }
    static func assessment(_ key: String, value: Any?, disk: DiskSnapshot) -> (String, DetailTone) {
        guard let value, !(value is NSNull) else { return ("未提供", .unavailable) }
        let n = number(value)
        switch key {
        case "critical_warning": return (n == 0 ? "无当前关键告警" : "存在关键告警", n == 0 ? .good : .alert)
        case "temperature":
            if let t = n, let critical = temperatureThreshold("critical", disk: disk), t >= critical { return ("达到设备临界阈值", .alert) }
            if let t = n, let warning = temperatureThreshold("warning", disk: disk), t >= warning { return ("达到设备警告阈值", .caution) }
            if let t = n, temperatureThreshold("warning", disk: disk) == nil, t >= 70 { return ("高温参考提示，非厂商阈值", .caution) }
            return (temperatureThreshold("warning", disk: disk) == nil ? "无厂商阈值，参考读数" : "低于已知温度阈值", .neutral)
        case "available_spare":
            guard let spare = n, let threshold = number(metricValue("available_spare_threshold", disk: disk)) else { return ("阈值未提供", .neutral) }
            return (spare < threshold ? "低于备用阈值" : "未低于备用阈值", spare < threshold ? .alert : .good)
        case "percentage_used": return ((n ?? 0) >= 100 ? "估计耐久已耗尽，建议关注" : "厂商耐久估计", (n ?? 0) >= 100 ? .caution : .neutral)
        case "media_errors": return (n == 0 ? "未记录介质错误" : "已记录错误，请结合日志", n == 0 ? .good : .caution)
        case "num_err_log_entries": return (n == 0 ? "未记录错误条目" : "有历史条目，需确认类型", .neutral)
        case "warning_temp_time", "critical_comp_time": return ((n ?? 0) > 0 ? "存在高温历史记录" : "记录为 0，不等于绝无过热", (n ?? 0) > 0 ? .caution : .neutral)
        case "unsafe_shutdowns": return ((n ?? 0) > 0 ? "历史计数，不单独判故障" : "记录为 0", .neutral)
        default: return ("参考信息", .neutral)
        }
    }
    static func nvmeRows(_ disk: DiskSnapshot) -> [SMARTDetail] {
        var rows = specs.map { spec -> SMARTDetail in
            let value = metricValue(spec.key, disk: disk)
            let a = assessment(spec.key, value: value, disk: disk)
            var shown = formatted(value), reference = spec.reference
            if spec.key == "temperature", let n = number(value) { shown = String(format: "%.2f", n) }
            if spec.key == "critical_warning", let n = number(value), n >= 0, n <= 255 { shown = String(format: "0x%02X", Int(n)) }
            if spec.key.hasPrefix("data_units_"), let n = number(value) { shown += "\n≈ " + byteString(n * 512000) }
            if spec.key == "temperature" {
                let warning = temperatureThreshold("warning", disk: disk), critical = temperatureThreshold("critical", disk: disk)
                reference = "警告：\(warning.map { integerString($0) + " °C" } ?? "未提供")\n临界：\(critical.map { integerString($0) + " °C" } ?? "未提供")"
            }
            if spec.key == "available_spare", let t = metricValue("available_spare_threshold", disk: disk) { reference = "设备阈值：\(formatted(t)) %" }
            return SMARTDetail(id: spec.key, title: spec.title, value: shown, unit: spec.unit, reference: reference, meaning: spec.meaning, status: a.0, tone: a.1)
        }
        let sensors = disk.nvmeFields["temperature_sensors"] as? [Any] ?? []
        for index in 0..<max(8, sensors.count) {
            let value: Any? = index < sensors.count ? sensors[index] : nil
            let available = value != nil && !(value is NSNull)
            rows.append(SMARTDetail(id: "temperature_sensors[\(index)]", title: "温度传感器 \(index + 1)", value: formatted(value), unit: "°C", reference: "传感器位置与阈值由厂商定义", meaning: "该传感器的当前读数；不能假设对应闪存或控制器。未返回的传感器不补为 0 °C。", status: available ? "参考读数" : "未提供", tone: available ? .neutral : .unavailable))
        }
        rows += ["warning", "critical"].map { key in
            let value = temperatureThreshold(key, disk: disk)
            return SMARTDetail(id: "temperature_threshold.\(key)", title: key == "warning" ? "警告复合温度阈值 WCTEMP" : "临界复合温度阈值 CCTEMP", value: value.map { integerString($0) } ?? "未提供", unit: "°C", reference: "设备 Identify Controller 报告", meaning: "厂商报告的复合温度阈值；未取得时不使用通用温度替代。", status: value == nil ? "未提供" : "厂商阈值", tone: value == nil ? .unavailable : .neutral)
        }
        let known = Set(specs.map { $0.key } + ["temperature_sensors"])
        let extra = disk.nvmeFields.filter { key, _ in
            !known.contains(key) && !known.contains(String(key.dropLast(2)))
        }
        rows += (extra.isEmpty ? [] : leaves(extra, prefix: "nvme_smart_health_information_log")).map { path, value in
            let key = path.replacingOccurrences(of: "nvme_smart_health_information_log.", with: "").components(separatedBy: "[").first ?? ""
            if key.hasSuffix("_le"), let spec = specs.first(where: { $0.key == String(key.dropLast(3)) }) {
                return SMARTDetail(id: path, title: spec.title + " · 原始字节", value: formatted(value), unit: "字节值 0–255", reference: "小端字节表示，非独立健康指标", meaning: "引擎为避免大整数精度丢失，额外返回低位字节在前的计数器字节数组。数组第 i 项权重为 256 的 i 次方；上方已经显示完整十进制计数。", status: "编码辅助字段", tone: .neutral)
            }
            return SMARTDetail(id: path, title: "额外 NVMe 字段", value: formatted(value), unit: "设备原值", reference: "查阅设备或规范定义", meaning: "设备返回但未在中文词典内定义的字段。原路径与原值完整保留，不猜测单位或异常阈值。", status: "含义未定义", tone: .neutral)
        }
        return rows
    }
    static func warningRows(_ disk: DiskSnapshot) -> [SMARTDetail] {
        let value = number(metricValue("critical_warning", disk: disk))
        let bits = value.flatMap { $0 >= 0 && $0 <= 255 ? UInt8($0) : nil }
        let names = ["备用空间不足", "温度越过阈值", "NVM 可靠性下降", "介质进入只读模式", "易失性内存备份失败", "持久内存区域不可靠 / 只读", "保留 / 未定义位 6", "保留 / 未定义位 7"]
        let meanings = ["备用空间已低于设备阈值。", "温度高于或低于控制器温度告警边界。", "严重介质错误或内部错误导致子系统可靠性下降。", "介质被置于只读状态，应优先备份和检查。", "仅适用于配备相应内存备份方案的设备。", "依照 smartmontools 7.5 解码：持久内存区域变为只读或不可靠，不是温度位。", "当前解码器未定义此位；置位时保留告警。", "当前解码器未定义此位；置位时保留告警。"]
        return (0..<8).map { i in
            let active = bits.map { ($0 & (1 << i)) != 0 }
            return SMARTDetail(id: "critical_warning.bit\(i)", title: "位 \(i) · \(names[i])", value: active.map { $0 ? "1 · 置位" : "0 · 未置位" } ?? "未提供", unit: "bit", reference: "0 表示未报告该当前告警", meaning: meanings[i], status: active.map { $0 ? "当前告警" : "该位未告警" } ?? "未知", tone: active.map { $0 ? .alert : .good } ?? .unavailable)
        }
    }
    static func leaves(_ value: Any, prefix: String) -> [(String, Any)] {
        if let d = value as? [String: Any] {
            if d.isEmpty { return [(prefix, d)] }
            return d.keys.sorted().flatMap { leaves(d[$0]!, prefix: prefix.isEmpty ? $0 : prefix + "." + $0) }
        }
        if let a = value as? [Any] {
            if a.isEmpty { return [(prefix, a)] }
            return a.enumerated().flatMap { leaves($0.element, prefix: prefix + "[\($0.offset)]") }
        }
        return [(prefix, value)]
    }
    static func additionalRows(_ disk: DiskSnapshot) -> [SMARTDetail] {
        var json = disk.engineJSON
        json.removeValue(forKey: "nvme_smart_health_information_log")
        var ata = dictionary(json["ata_smart_attributes"])
        ata.removeValue(forKey: "table")
        if !ata.isEmpty { json["ata_smart_attributes"] = ata } else { json.removeValue(forKey: "ata_smart_attributes") }
        var engine = dictionary(json["smartctl"])
        engine.removeValue(forKey: "output")
        if !engine.isEmpty { json["smartctl"] = engine } else { json.removeValue(forKey: "smartctl") }
        var rows = (json.isEmpty ? [] : leaves(json, prefix: "smartctl JSON")).map { path, value -> SMARTDetail in
            let sensitive = path.lowercased().contains("serial") || path.lowercased().contains("wwn") || path.lowercased().contains("eui")
            let caption = fieldMeaning(path)
            return SMARTDetail(id: path, title: caption.0, value: formatted(value), unit: caption.1, reference: "设备 / 引擎原始返回值", meaning: caption.2, status: "参考信息", tone: .neutral, sensitive: sensitive)
        }
        if !disk.systemFields.isEmpty {
            rows += leaves(disk.systemFields, prefix: "macOS SMART").map { path, value in
                let suffix = path.components(separatedBy: ".").last ?? path
                let mapped = systemMap.first { suffix == $0.value || suffix == $0.value + "_0" || suffix == $0.value + "_1" }
                let title = mapped.flatMap { pair in specs.first { $0.key == pair.key }?.title } ?? "macOS 原生 SMART 字段"
                let meaning = suffix == "TEMPERATURE" ? "系统原始温度为 Kelvin；上方已经转换为 °C。" : suffix.hasSuffix("_0") || suffix.hasSuffix("_1") ? "128 位计数器的低 / 高 64 位；上方合并显示，此处保留系统原始分段值。" : "保留系统返回的健康字段，不改写设备原值。"
                return SMARTDetail(id: path, title: title, value: formatted(value), unit: suffix == "TEMPERATURE" ? "K" : "原始值", reference: "macOS 原始接口", meaning: meaning, status: "原始字段", tone: .neutral)
            }
        }
        return rows
    }
    static func fieldMeaning(_ path: String) -> (String, String, String) {
        let key = path.components(separatedBy: ".").last ?? path
        let simple: [String: (String, String, String)] = [
            "model_name": ("设备型号", "文本", "控制器返回的型号字符串。"),
            "serial_number": ("设备序列号", "文本", "设备唯一标识，默认隐藏，分享前注意隐私。"),
            "firmware_version": ("固件版本", "文本", "控制器当前运行的固件版本。"),
            "passed": ("设备 SMART 总体结论", "布尔值", "设备总体自检结论；通过不等于绝无故障风险。"),
            "bytes": ("容量 / 大小", "字节", "单位为字节；请按完整字段路径区分设备、命名空间与逻辑块。"),
            "protocol": ("访问协议", "文本", "读取引擎识别的设备协议。"),
            "nsid": ("命名空间标识", "ID", "说明日志适用的命名空间范围。"),
            "exit_status": ("引擎退出状态", "位掩码", "smartctl 非 0 可表示附加读取失败或健康告警；并不等于所有数据不可用。"),
            "entry_latency_us": ("进入电源状态延迟", "微秒", "进入该电源状态的报告延迟。"),
            "exit_latency_us": ("退出电源状态延迟", "微秒", "退出该电源状态的报告延迟。"),
            "max_power": ("电源状态最大功率", "W", "该电源状态报告的最大功率。"),
            "active_power": ("电源状态活动功率", "W", "该电源状态报告的活动功率。"),
            "idle_power": ("电源状态空闲功率", "W", "该电源状态报告的空闲功率。")
        ]
        if path.contains("_le[") { return ("计数器原始小端字节", "字节值 0–255", "低位字节在前的整数辅助表示，不是另一项健康指标。") }
        if key.hasSuffix("_s") { return ("计数器精确十进制字符串", "十进制文本", "避免 JSON 数值超出安全整数范围时失去精度的辅助表示。") }
        if let result = simple[key] { return result }
        if path.contains("nvme_error_information_log") {
            let errors: [String: (String, String, String)] = [
                "size": ("错误日志最大槽位", "条", "控制器支持的错误日志容量，不是生命周期错误次数。"),
                "read": ("本次读取日志槽位", "条", "本次读取到的日志槽位数，不等于有效错误数量。"),
                "unread": ("未读取日志槽位", "条", "控制器日志中本次未读取的槽位数。"),
                "error_count": ("错误累计编号", "编号", "对应错误条目的累计错误计数。"),
                "submission_queue_id": ("提交队列 ID", "ID", "产生错误命令所在的队列。"),
                "command_id": ("命令 ID", "ID", "发生错误的命令标识。"),
                "status_field": ("命令完成状态", "位域 / 原值", "NVMe 完成状态编码，应结合状态描述解码。"),
                "lba": ("出错逻辑块地址", "LBA", "若设备提供，表示与错误关联的逻辑块地址。")
            ]
            if let result = errors[key] { return result }
        }
        let additional: [String: (String, String, String)] = [
            "available": ("SMART 功能可用", "布尔值", "控制器是否报告可提供 SMART；不保证每项日志都能读取。"),
            "enabled": ("SMART 功能启用", "布尔值", "控制器报告的 SMART 功能启用状态。"),
            "current": ("当前读数", "依字段路径", "该分组当前读数，具体指标由完整路径确定。"),
            "op_limit_max": ("运行温度警告上限", "°C", "设备报告的复合温度警告上限。"),
            "critical_limit_max": ("临界温度上限", "°C", "设备报告的复合温度临界上限。"),
            "nvme_number_of_namespaces": ("命名空间数量", "个", "控制器报告的命名空间数量，不等于 macOS 分区数量。"),
            "nvme_controller_id": ("NVMe 控制器 ID", "ID", "设备报告的控制器标识。"),
            "non_operational_state": ("非运行电源状态", "布尔值", "此电源状态是否不处理正常 I/O。"),
            "relative_read_latency": ("相对读取延迟等级", "相对等级", "电源状态间相对等级，不能直接解释为毫秒。"),
            "relative_write_latency": ("相对写入延迟等级", "相对等级", "电源状态间相对等级，不能直接解释为毫秒。"),
            "relative_read_throughput": ("相对读取吞吐等级", "相对等级", "电源状态间相对吞吐等级，不是 MB/s。"),
            "relative_write_throughput": ("相对写入吞吐等级", "相对等级", "电源状态间相对吞吐等级，不是 MB/s。"),
            "data_bytes": ("逻辑块数据大小", "字节", "对应 LBA 格式每个逻辑块的数据大小。"),
            "metadata_bytes": ("逻辑块元数据大小", "字节", "对应 LBA 格式每个逻辑块的元数据大小。"),
            "formatted": ("当前使用的 LBA 格式", "布尔值", "此 LBA 格式是否为设备当前格式。")
        ]
        return additional[key] ?? ("额外返回字段", "原始值", "完整保留返回字段；厂商或协议可能另有定义，未定义的字段不猜测含义或阈值。")
    }
    static func ataMeaning(_ attribute: Attribute) -> ATAMeaning {
        let meanings: [String: ATAMeaning] = [
            "Raw_Read_Error_Rate": .init(title: "原始读取错误率", unit: "厂商编码", meaning: "厂商定义的读错误指标；原始大数不应直接当作实际错误次数。"),
            "Read_Error_Rate": .init(title: "读取错误率", unit: "厂商编码", meaning: "读取相关错误指标，需按型号解码原始值与归一化值。"),
            "Throughput_Performance": .init(title: "吞吐性能", unit: "厂商定义", meaning: "性能相关归一化指标，不是实时 MB/s。"),
            "Spin_Up_Time": .init(title: "主轴起转时间", unit: "厂商定义", meaning: "机械盘达到运行转速的时间相关指标，原始格式由厂商决定。"),
            "Start_Stop_Count": .init(title: "主轴启停次数", unit: "次（需核对厂商）", meaning: "记录机械盘主轴启停，不等于整机启动次数。"),
            "Reallocated_Sector_Ct": .init(title: "重映射扇区数量", unit: "扇区 / 厂商编码", meaning: "已经被备用空间替换的扇区相关计数，持续增长值得关注。"),
            "Reallocated_Block_Count": .init(title: "重映射块数量", unit: "块 / 厂商编码", meaning: "SSD 替换或重映射的块计数，需结合厂商定义。"),
            "Seek_Error_Rate": .init(title: "寻道错误率", unit: "厂商编码", meaning: "机械盘寻道错误相关指标；原始值可能由多个字段组成。"),
            "Seek_Time_Performance": .init(title: "寻道时间性能", unit: "厂商定义", meaning: "机械盘寻道性能的归一化指标。"),
            "Power_On_Hours": .init(title: "通电时长", unit: "通常为小时", meaning: "累计通电时长；某些型号使用分钟、半分钟或多字段编码，按厂商解释为准。"),
            "Spin_Retry_Count": .init(title: "主轴起转重试", unit: "次（需核对厂商）", meaning: "机械盘启动主轴时的重试记录，增长可能与机械或供电有关。"),
            "Power_Cycle_Count": .init(title: "电源周期次数", unit: "次", meaning: "设备经历的电源周期累计计数。"),
            "Program_Fail_Count_Chip": .init(title: "闪存编程失败", unit: "厂商定义计数", meaning: "闪存编程失败相关记录，适用范围与编码由厂商定义。"),
            "Erase_Fail_Count_Chip": .init(title: "闪存擦除失败", unit: "厂商定义计数", meaning: "闪存擦除失败相关记录，不同型号统计口径可能不同。"),
            "Wear_Leveling_Count": .init(title: "磨损均衡计数", unit: "厂商定义", meaning: "可能表示擦写周期或剩余耐久；不能统一解释为寿命百分比。"),
            "Used_Rsvd_Blk_Cnt_Tot": .init(title: "已使用备用块", unit: "厂商定义计数", meaning: "累计使用的备用块，需结合型号与归一化阈值。"),
            "Unused_Rsvd_Blk_Cnt_Tot": .init(title: "未使用备用块", unit: "厂商定义计数", meaning: "可用备用块相关指标；不等于文件系统空闲空间。"),
            "Runtime_Bad_Block": .init(title: "运行期坏块", unit: "厂商定义计数", meaning: "设备运行期间产生的坏块相关记录。"),
            "End-to-End_Error": .init(title: "端到端数据错误", unit: "厂商定义计数", meaning: "内部数据通路一致性错误，需核对厂商定义。"),
            "Reported_Uncorrect": .init(title: "已报告不可纠正错误", unit: "厂商定义计数", meaning: "向主机报告的不可纠正错误相关记录。"),
            "Command_Timeout": .init(title: "命令超时", unit: "厂商编码", meaning: "设备命令超时记录；供电、连线、桥接或设备问题都可能影响。"),
            "Airflow_Temperature_Cel": .init(title: "气流温度", unit: "°C / 编码", meaning: "按引擎解码的温度读数；归一化值可能是 100 减温度，不等于摄氏度。"),
            "Temperature_Celsius": .init(title: "设备温度", unit: "°C / 多字段编码", meaning: "原始值可能同时含当前、最低、最高温度，应保留引擎原始字符串。"),
            "G-Sense_Error_Rate": .init(title: "震动 / 冲击记录", unit: "厂商定义计数", meaning: "冲击传感器记录，不单独代表介质损坏。"),
            "Power-Off_Retract_Count": .init(title: "断电磁头回缩", unit: "次（需核对厂商）", meaning: "机械盘断电回缩磁头相关累计记录。"),
            "Load_Cycle_Count": .init(title: "磁头加载 / 卸载", unit: "次", meaning: "机械盘磁头加载、卸载累计次数。"),
            "Reallocated_Event_Count": .init(title: "重映射事件次数", unit: "次（需核对厂商）", meaning: "重映射尝试或事件数量，和重映射扇区数不是同一指标。"),
            "Current_Pending_Sector": .init(title: "当前待映射扇区", unit: "扇区", meaning: "读取不稳定、等待进一步处理的扇区；非 0 应优先备份并检查。"),
            "Offline_Uncorrectable": .init(title: "离线不可纠正扇区", unit: "扇区", meaning: "离线扫描发现的不可纠正扇区；非 0 应优先备份并检查。"),
            "UDMA_CRC_Error_Count": .init(title: "接口 CRC 错误", unit: "次（需核对厂商）", meaning: "ATA 链路传输完整性错误，常需检查线缆、连接与桥接，不等于介质坏块。"),
            "SSD_Life_Left": .init(title: "SSD 剩余寿命", unit: "厂商定义", meaning: "可能为剩余耐久百分比或归一化值；以该型号解释为准。"),
            "Media_Wearout_Indicator": .init(title: "介质磨损指示", unit: "厂商定义", meaning: "厂商提供的磨损归一化指标，方向与编码需核对型号。"),
            "Total_LBAs_Written": .init(title: "主机累计写入 LBA", unit: "厂商定义 LBA 单位", meaning: "不同厂商可使用不同数据单位，不强制按 512 字节换算。"),
            "Total_LBAs_Read": .init(title: "主机累计读取 LBA", unit: "厂商定义 LBA 单位", meaning: "累计读取相关原始计数，单位需核对厂商定义。")
        ]
        return meanings[attribute.name] ?? .init(title: "厂商自定义属性 \(String(format: "%02X", attribute.id))", unit: "厂商定义", meaning: "该属性名称未收录中文解释。ATA 的属性 ID 与原始编码并非跨厂商统一，保留原名称、原值与所有标志，不套用其他型号定义。")
    }
    static func ataAssessment(_ attribute: Attribute) -> (String, DetailTone) {
        if attribute.failing { return (attribute.whenFailed == "now" ? "当前达到失效条件" : "记录过失效条件", .alert) }
        if attribute.reachedThreshold { return ("归一化值达到阈值", .alert) }
        let raw = number(dictionary(attribute.original["raw"])["value"])
        if ["Current_Pending_Sector", "Offline_Uncorrectable"].contains(attribute.name), let raw, raw > 0 { return ("存在异常计数，优先备份", .alert) }
        if ["Reallocated_Sector_Ct", "Reallocated_Block_Count", "UDMA_CRC_Error_Count"].contains(attribute.name), let raw, raw > 0 { return ("存在历史计数，关注趋势", .caution) }
        return ("按厂商定义判断", .neutral)
    }
}

// Immutable presentation prepared with each disk read, never during selection changes.
// Column widths are fixed so text measurement can also happen off the main thread.
struct SMARTDisplayCell {
    let text: String
    let masked: String
    let monospaced: Bool
    init(_ text: String, masked: String? = nil, monospaced: Bool = false) {
        self.text = text; self.masked = masked ?? text; self.monospaced = monospaced
    }
    var font: NSFont { monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11) }
}
struct SMARTDisplayRow {
    let id: String
    let cells: [SMARTDisplayCell]
    let tone: DetailTone
    let group: Bool
    let spanning: Bool
    let height: CGFloat
    init(id: String, cells: [SMARTDisplayCell], tone: DetailTone = .neutral, group: Bool = false, spanning: Bool = false) {
        self.id = id; self.cells = cells; self.tone = tone; self.group = group; self.spanning = spanning || group
        if group { self.height = 42; return }
        var height: CGFloat = 20
        for (index, cell) in cells.enumerated() {
            let width = spanning ? SMARTPresentation.widths.reduce(0, +) - 20 : SMARTPresentation.widths[index] - 20
            for text in Set([cell.text, cell.masked]) {
                let rect = (text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: cell.font])
                height = max(height, ceil(rect.height))
            }
        }
        self.height = max(44, height + 24)
    }
}
struct SMARTPresentation {
    static let widths: [CGFloat] = [248, 178, 120, 210, 316, 178]
    static let headings = ["指标 / 原始字段", "当前读数", "单位", "参考阈值 / 标准", "中文含义", "异常"]
    let revision = UUID()
    let diskID: String
    let health: Health
    let rows: [SMARTDisplayRow]
    let rawOutput: String
    let maskedOutput: String
    let nvmeCount: Int
    let warningCount: Int
    let additionalCount: Int

    init(_ disk: DiskSnapshot) {
        diskID = disk.id; health = disk.health
        let nvme = disk.isNVMe ? SMARTDetails.nvmeRows(disk) : []
        let warnings = disk.isNVMe ? SMARTDetails.warningRows(disk) : []
        let additional = SMARTDetails.additionalRows(disk)
        nvmeCount = nvme.count; warningCount = warnings.count; additionalCount = additional.count
        var result: [SMARTDisplayRow] = []
        func group(_ id: String, _ title: String, _ count: Int? = nil) {
            result.append(SMARTDisplayRow(id: "group." + id, cells: [.init(title), .init(count.map { "\($0) 项" } ?? "")], group: true))
        }
        func append(_ rows: [SMARTDetail]) {
            result += rows.map { row in
                SMARTDisplayRow(id: row.id, cells: [
                    .init(row.title + "\n" + row.id),
                    .init(row.value, masked: row.sensitive ? "••••••••" : nil, monospaced: true),
                    .init(row.unit), .init(row.reference), .init(row.meaning),
                    .init(row.tone == .alert || row.tone == .caution ? row.status : "—")
                ], tone: row.tone)
            }
        }
        if disk.isNVMe {
            group("nvme", "NVMe 健康日志", nvme.count); append(nvme)
            group("warnings", "关键告警位", warnings.count); append(warnings)
        }
        if !disk.attributes.isEmpty {
            group("ata", "ATA SMART 属性", disk.attributes.count)
            for attribute in disk.attributes {
                let meaning = SMARTDetails.ataMeaning(attribute), assessment = SMARTDetails.ataAssessment(attribute)
                let prefix = "attribute[\(attribute.id)]"
                group(prefix, "\(String(format: "%02X", attribute.id)) / \(attribute.id) · \(meaning.title)")
                let fields = [("VALUE", "当前归一化值", attribute.value), ("WORST", "历史最差值", attribute.worst), ("THRESH", "失效阈值", attribute.threshold), ("RAW", "原始编码", attribute.raw), ("WHEN_FAILED", "失效记录", attribute.whenFailed)]
                append(fields.map { key, title, value in
                    SMARTDetail(id: prefix + "." + key, title: title + " · " + key, value: value, unit: key == "RAW" ? meaning.unit : key == "WHEN_FAILED" ? "记录" : "归一化值", reference: ["VALUE", "WORST", "THRESH"].contains(key) ? "VALUE ≤ 正数 THRESH 时达到阈值" : key == "RAW" ? "按型号定义解码，非通用阈值" : "now 为当前失效；其他失效记录需结合引擎定义", meaning: attribute.name + "\n" + meaning.meaning, status: assessment.0, tone: assessment.1)
                })
                let flags = attribute.flags.keys.sorted().map { "\($0)=\(SMARTDetails.formatted(attribute.flags[$0]))" }.joined(separator: " · ")
                append([SMARTDetail(id: prefix + ".FLAGS", title: "属性标志 FLAGS", value: flags.isEmpty ? "未提供" : flags, unit: "标志", reference: "设备 / 引擎返回值", meaning: attribute.name, status: "—", tone: .neutral)])
                append(SMARTDetails.leaves(attribute.original, prefix: prefix + ".original").map { path, value in
                    SMARTDetail(id: path, title: "ATA 原始字段", value: SMARTDetails.formatted(value), unit: "原始值", reference: "设备 / 引擎返回值", meaning: "按完整路径保留属性原值与厂商扩展字段。", status: "—", tone: .neutral)
                })
            }
        } else if !disk.isNVMe {
            group("ata-empty", "无 ATA 属性数据")
        }
        group("additional", "其他字段", additional.count); append(additional)
        let lines = dictionary(disk.engineJSON["smartctl"])["output"] as? [String] ?? []
        rawOutput = lines.joined(separator: "\n")
        let maskedLines = lines.map { Self.maskOutput($0, serial: disk.serial) }
        maskedOutput = maskedLines.joined(separator: "\n")
        if !lines.isEmpty {
            group("output", "smartctl 输出", lines.count)
            // Each complete line lives in a reusable cell. It wraps rather than truncates.
            for (index, line) in lines.enumerated() {
                result.append(SMARTDisplayRow(id: "output[\(index)]", cells: [
                    .init(line, masked: maskedLines[index], monospaced: true)
                ], spanning: true))
            }
        }
        rows = result
    }
    static func maskOutput(_ line: String, serial: String?) -> String {
        let lower = line.lowercased()
        if ["serial", "eui", "wwn", "ieee oui", "unique id"].contains(where: { lower.contains($0) }) {
            let label = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "设备标识"
            return label + ": [设备标识已隐藏]"
        }
        guard let serial, !serial.isEmpty else { return line }
        return line.replacingOccurrences(of: serial, with: "[设备标识已隐藏]")
    }
}
