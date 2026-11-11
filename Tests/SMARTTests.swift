import Foundation

@main struct SMARTTests {
    static func main() throws {
        if CommandLine.arguments.contains("--benchmark-display") {
            let scan = DiskService.scan()
            for disk in scan.disks {
                var samples: [Double] = [], checksum = 0
                for _ in 0..<100 {
                    let begin = ProcessInfo.processInfo.systemUptime
                    let a = SMARTDetails.nvmeRows(disk), b = SMARTDetails.warningRows(disk), c = SMARTDetails.additionalRows(disk)
                    checksum += a.count + b.count + c.count
                    samples.append((ProcessInfo.processInfo.systemUptime - begin) * 1000)
                }
                samples.sort()
                print(String(format: "DISPLAY BUILD %@: median=%.3f ms p95=%.3f ms checksum=%d", disk.id, samples[50], samples[94], checksum))
            }
            return
        }
        if CommandLine.arguments.contains("--scan") {
            let scan = DiskService.scan()
            print("Engine: \(scan.engineVersion)")
            if let error = scan.error { print("Scan warning: \(error)") }
            for disk in scan.disks {
                print("\(disk.id) | \(disk.name) | \(disk.protocolName) | \(disk.health.rawValue) | temp=\(integerString(disk.temperature)) | used=\(integerString(disk.percentageUsed))% | read=\(byteString(disk.bytesRead)) | written=\(byteString(disk.bytesWritten)) | hours=\(integerString(disk.powerHours)) | source=\(disk.source)")
                let rows = SMARTDetails.nvmeRows(disk)
                print("  Full NVMe table: \(rows.count) rows; warning bits: \(SMARTDetails.warningRows(disk).count); supplementary leaves: \(SMARTDetails.additionalRows(disk).count)")
                for row in rows { print("    \(row.id) | \(row.title) | \(row.value.replacingOccurrences(of: "\n", with: " ")) | \(row.unit) | \(row.status)") }
                for warning in disk.messages { print("  Warning: \(warning)") }
            }
            if let output = ProcessInfo.processInfo.environment["SMARTINFO_TEST_REPORT"], let disk = scan.disks.first {
                try disk.rawData.write(toFile: output, atomically: true, encoding: .utf8)
            }
            return
        }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
            count += 1; print("PASS: \(name)")
        }
        let base = SMARTParser.initial(id: "disk0", info: ["MediaName": "Fallback Model", "Internal": true, "Size": 500000000000])
        check(base.name == "Fallback Model", "Model falls back to diskutil MediaName")
        check(base.health == .unknown, "No data is unknown, never healthy")
        let empty = SMARTParser.apply(json: [:], to: base)
        check(empty.health == .unknown && empty.attributes.isEmpty, "Missing NVMe/ATA fields do not crash")
        let nulls = SMARTParser.apply(json: ["ata_smart_attributes": NSNull(), "nvme_smart_health_information_log": NSNull(), "model_name": NSNull()], to: base)
        check(nulls.name == base.name && nulls.health == .unknown, "Explicit JSON nulls do not crash")
        let nvmeJSON: [String: Any] = ["model_name": "NVMe SSD", "serial_number": "test-serial", "firmware_version": "v1", "device": ["type": "nvme", "protocol": "NVMe"], "smart_status": ["passed": true], "nvme_smart_health_information_log": ["temperature": 35, "percentage_used": 1, "critical_warning": 0, "data_units_written": 1000, "media_errors": 0]]
        let nvme = SMARTParser.apply(json: nvmeJSON, to: base)
        check(nvme.name == "NVMe SSD" && nvme.serial == "test-serial", "Model and serial are top-level smartctl fields")
        check(nvme.attributes.isEmpty && nvme.health == .good, "NVMe does not require ATA attribute table")
        check(nvme.bytesWritten == 512000000, "NVMe data units use 512000 bytes, not 512 bytes")
        check(nvme.temperature == 35, "smartctl temperature is already Celsius")
        let system = SMARTParser.initial(id: "disk0", info: ["SMARTStatus": "Verified", "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["TEMPERATURE": 308, "PERCENTAGE_USED": 0, "POWER_ON_HOURS_0": 325, "DATA_UNITS_READ_0": 1000]])
        check(abs((system.temperature ?? 0) - 34.85) < 0.001, "diskutil NVMe Kelvin converted to Celsius")
        check(system.health == .good && system.powerHours == 325 && system.bytesRead == 512000000, "macOS native fallback health and counters")
        let unknownTemp = SMARTParser.initial(id: "disk0", info: ["SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["TEMPERATURE": 308]])
        check(unknownTemp.health == .unknown, "Temperature alone is not proof of health")
        let failed = SMARTParser.apply(json: ["smart_status": ["passed": false]], to: system)
        check(failed.health == .failed, "SMART failing is red alert")
        let warning = SMARTParser.apply(json: ["nvme_smart_health_information_log": ["critical_warning": 2]], to: system)
        check(warning.health == .failed, "NVMe critical warning is red alert")
        let aged = SMARTParser.apply(json: ["nvme_smart_health_information_log": ["percentage_used": 105]], to: system)
        check(aged.health == .caution && aged.percentageUsed == 105, "Endurance over 100 percent is retained")
        let errors = SMARTParser.apply(json: ["nvme_smart_health_information_log": ["media_errors": 1]], to: system)
        check(errors.health == .caution, "Media errors generate attention")
        let ata = SMARTParser.apply(json: ["smart_status": ["passed": true], "ata_smart_attributes": ["table": [["id": 197, "name": "Current_Pending_Sector", "value": 100, "thresh": 0, "raw": ["value": 1, "string": "1"]]]]], to: base)
        check(ata.attributes.count == 1 && ata.pendingSectors == 1 && ata.health == .failed, "ATA pending sectors parsed independently")
        let partial = SMARTParser.apply(json: ["smartctl": ["exit_status": 4, "messages": [["string": "Optional error log unavailable"]]]], to: system)
        check(partial.health == .good && partial.temperature != nil && partial.messages.count == 1, "Partial engine failure preserves native health data")
        let malformedATA = SMARTParser.apply(json: ["ata_smart_attributes": ["table": [["id": 1e50], ["id": -1], ["id": 5.5]]]], to: base)
        check(malformedATA.attributes.isEmpty, "Malformed ATA identifiers cannot overflow or crash")
        check(DiskService.read(id: "disk0; touch /tmp/notallowed") == nil, "Device identifiers validated; no shell interpolation")
        let timeout = CommandRunner.run("/bin/sleep", ["3"], timeout: 0.1)
        check(timeout.timedOut, "Command timeout terminates the child process")
        let noExecutable = CommandRunner.run("/path/that/does/not/exist", [])
        check(noExecutable.status == -1, "Missing helper reports error rather than crashing")
        let fullLog: [String: Any] = ["temperature": 40, "critical_warning": 32, "host_reads": 123, "host_writes": 456, "controller_busy_time": 789, "warning_temp_time": 12, "critical_comp_time": 3, "temperature_sensors": [41, NSNull(), 42], "vendor_future": ["counter": 99], "data_units_read": 9007199254740992.0, "data_units_read_s": "9007199254740993"]
        let detailed = SMARTParser.apply(json: ["nvme_smart_health_information_log": fullLog, "nvme_composite_temperature_threshold": ["warning": 60, "critical": 80], "smartctl": ["output": ["Thermal Temp. 1 Transition Count:   5", "Thermal Temp. 2 Transition Count:   6", "Thermal Temp. 1 Total Time:         70", "Thermal Temp. 2 Total Time:         80"]]], to: system)
        let rows = SMARTDetails.nvmeRows(detailed)
        check(rows.contains { $0.id == "host_reads" && $0.value == "123" }, "Host read commands fully included")
        check(rows.contains { $0.id == "controller_busy_time" && $0.unit == "分钟" }, "Busy time unit is minutes")
        check(rows.contains { $0.id == "warning_temp_time" && $0.value == "12" }, "Warning temperature history fully included")
        check(rows.contains { $0.id == "thermal_mgmt_temp1_total_time" && $0.value == "70" && $0.unit == "秒" }, "Thermal counters recovered from original output with seconds unit")
        check(rows.filter { $0.id.hasPrefix("temperature_sensors[") }.count == 8, "All eight optional temperature sensors expanded")
        check(rows.contains { $0.id == "temperature_sensors[1]" && $0.value == "未提供" }, "Missing sensor stays unavailable, not zero Celsius")
        check(rows.contains { $0.id == "nvme_smart_health_information_log.vendor_future.counter" && $0.value == "99" }, "Unknown future NVMe fields retained recursively")
        check(rows.first { $0.id == "data_units_read" }?.value.hasPrefix("9007199254740993") == true, "Exact counter string preserved beyond JSON safe integer limit")
        check(rows.first { $0.id == "temperature" }?.reference.contains("60 °C") == true, "Device-specific temperature thresholds shown")
        let bitRows = SMARTDetails.warningRows(detailed)
        check(bitRows.count == 8 && bitRows[5].value.hasPrefix("1") && bitRows[5].title.contains("持久内存"), "Critical bit 5 is persistent memory, not temperature")
        check(SMARTDetails.warningRows(base).allSatisfy { $0.value == "未提供" }, "Missing critical-warning value is not clear bits")
        let custom = SMARTParser.apply(json: ["ata_smart_attributes": ["table": [["id": 197, "name": "Vendor_Custom_Metric", "value": 100, "worst": 99, "thresh": 10, "when_failed": "-", "flags": ["prefailure": true], "raw": ["value": 7, "string": "7 extra"], "vendor_extra": ["bytes": [1, 2]]]]]], to: base)
        check(custom.attributes.first?.flags["prefailure"] as? Bool == true, "ATA flags preserved")
        check(custom.attributes.first?.raw == "7 extra", "ATA raw string preserved without unit assumptions")
        check(custom.pendingSectors == nil && custom.health == .unknown, "Custom ATA ID 197 is not automatically treated as pending sectors")
        check(custom.attributes.first.map { SMARTDetails.ataMeaning($0).title.contains("厂商自定义") } == true, "ATA description uses reported name, not ID alone")
        check(custom.attributes.first.map { SMARTDetails.leaves($0.original, prefix: "attribute").contains { $0.0 == "attribute.vendor_extra.bytes[1]" } } == true, "ATA extra fields and arrays fully preserved")
        let metadata = SMARTParser.apply(json: ["serial_number": "private-123", "nvme_namespaces": [["id": 1, "size": ["bytes": 1000]]], "vendor_log": ["unknown": 88]], to: base)
        let extra = SMARTDetails.additionalRows(metadata)
        check(extra.contains { $0.id.contains("nvme_namespaces[0].size.bytes") }, "Supplementary namespaces fully expanded")
        check(extra.contains { $0.id.contains("vendor_log.unknown") && $0.value == "88" }, "Unknown supplementary fields never omitted")
        check(extra.contains { $0.id.contains("serial_number") && $0.sensitive }, "Supplementary device identifiers masked by default")
        check(SMARTDetails.formatted(true) == "是" && SMARTDetails.formatted(0) == "0" && SMARTDetails.formatted(NSNull()) == "未提供", "Boolean, zero, and null remain distinct")
        let highCounter = SMARTParser.initial(id: "disk0", info: ["SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["HOST_READ_COMMANDS_0": 1, "HOST_READ_COMMANDS_1": 1]])
        check(SMARTDetails.formatted(SMARTDetails.metricValue("host_reads", disk: highCounter)) == "18446744073709551617", "Native 128-bit counter combines high/low segments exactly")
        let thresholds = SMARTParser.apply(json: ["smart_status": ["passed": true], "nvme_smart_health_information_log": ["temperature": 75], "nvme_composite_temperature_threshold": ["warning": 83, "critical": 85]], to: base)
        check(thresholds.health == .good, "Known manufacturer warning threshold overrides generic 70 Celsius rule")
        let hot = SMARTParser.apply(json: ["nvme_smart_health_information_log": ["temperature": 86], "nvme_composite_temperature_threshold": ["warning": 83, "critical": 85]], to: thresholds)
        check(hot.health == .failed, "Manufacturer critical threshold produces health alert")
        let thresholdATA = SMARTParser.apply(json: ["ata_smart_attributes": ["table": [["id": 1, "name": "Raw_Read_Error_Rate", "value": 5, "thresh": 10]]]], to: base)
        check(thresholdATA.health == .failed, "ATA normalized threshold applies to summary and detail consistently")
        let leDisk = SMARTParser.apply(json: ["nvme_smart_health_information_log": ["host_reads_le": [5, 1]]], to: system)
        check(SMARTDetails.nvmeRows(leDisk).contains { $0.id.hasSuffix("host_reads_le[0]") && $0.title.contains("原始字节") }, "Little-endian counter helper bytes have correct explanation")
        check(SMARTDetails.additionalRows(base).isEmpty, "Empty engine dictionary creates no invented supplementary row")
        let prepared = SMARTPresentation(detailed)
        check(prepared.nvmeCount == rows.count && prepared.warningCount == bitRows.count, "Cached NVMe rows and all warning bits preserved")
        check(rows.allSatisfy { source in prepared.rows.contains { $0.id == source.id && $0.cells[1].text == source.value && $0.cells[4].text == source.meaning } }, "Presentation preserves exact values and complete definitions")
        check(prepared.rows.allSatisfy { $0.height.isFinite && $0.height >= 42 }, "Every cached native row height is finite and nonzero")
        check(Set(prepared.rows.map { $0.id }).count == prepared.rows.count, "Native row identifiers remain unique")
        let preparedATA = SMARTPresentation(custom)
        check(["VALUE", "WORST", "THRESH", "RAW", "WHEN_FAILED", "FLAGS"].allSatisfy { key in preparedATA.rows.contains { $0.id == "attribute[197]." + key } }, "Every ATA column and flags included in native table")
        check(preparedATA.rows.contains { $0.id == "attribute[197].original.vendor_extra.bytes[1]" && $0.cells[1].text == "2" }, "Virtualized ATA table retains original vendor arrays")
        check(preparedATA.rows.contains { $0.id == "attribute[197].RAW" && $0.cells[1].text == "7 extra" }, "Native ATA RAW preserves complete source string")
        let preparedMetadata = SMARTPresentation(metadata)
        check(extra.allSatisfy { source in preparedMetadata.rows.contains { $0.id == source.id && $0.cells[1].text == source.value } }, "Every supplementary field retained in native presentation")
        check(preparedMetadata.rows.contains { $0.id.contains("serial_number") && $0.cells[1].text == "private-123" && $0.cells[1].masked == "••••••••" }, "Cached serial has separate masked and unmasked display")
        let outputDisk = SMARTParser.apply(json: ["serial_number": "secret-123", "smartctl": ["output": ["Serial Number: secret-123", "Vendor uses secret-123 here", "IEEE OUI Identifier: 001122", "Temperature: 35 Celsius", "", "Last output line"]]], to: base)
        let outputPresentation = SMARTPresentation(outputDisk)
        check(outputPresentation.rawOutput == "Serial Number: secret-123\nVendor uses secret-123 here\nIEEE OUI Identifier: 001122\nTemperature: 35 Celsius\n\nLast output line", "Full output text, empty lines and order preserved")
        check(!outputPresentation.maskedOutput.contains("secret-123") && !outputPresentation.maskedOutput.contains("001122"), "Output identifiers hidden in precomputed copy and display text")
        check(outputPresentation.rows.filter { $0.id.hasPrefix("output[") }.count == 6 && outputPresentation.rows.last?.cells.first?.text == "Last output line", "Every original output line is a scrollable spanning row")
        let longText = String(repeating: "完整字段与中文说明不截断 ", count: 100)
        let longRow = SMARTDisplayRow(id: "long", cells: [.init("字段"), .init(longText), .init("文本"), .init("原值"), .init(longText), .init("—")])
        check(longRow.height > 400, "Long multiline values increase cached height rather than truncate")
        check(SMARTPresentation(base).revision != SMARTPresentation(base).revision, "Each fresh read generates a new presentation revision")
        var editedDisk = detailed; editedDisk.nvmeFields["host_reads"] = 999
        let editedPresentation = SMARTPresentation(editedDisk)
        check(editedPresentation.rows.contains { $0.id == "host_reads" && $0.cells[1].text == "999" } && prepared.rows.contains { $0.id == "host_reads" && $0.cells[1].text == "123" }, "Updated snapshot rebuilds cache without mutating prior data")
        if CommandLine.arguments.contains("--require-engine-data") {
            let live = DiskService.scan()
            check(!live.disks.isEmpty, "Live disk scan found physical disks")
            for disk in live.disks where disk.isNVMe {
                check(!disk.nvmeFields.isEmpty, "Live \(disk.id) returns extended engine health data")
                check(disk.nvmeFields["critical_warning"] != nil, "Live \(disk.id) has critical warning field, no CLI option failure")
                check(!disk.messages.contains { $0.contains("UNRECOGNIZED OPTION") }, "Live \(disk.id) read options recognized")
                let specs = SMARTDetails.nvmeRows(disk)
                for key in ["host_reads", "host_writes", "controller_busy_time"] { check(specs.contains { $0.id == key && $0.value != "未提供" }, "Live \(disk.id) complete \(key)") }
            }
        }
        print("\nAll \(count) tests passed")
    }
}
