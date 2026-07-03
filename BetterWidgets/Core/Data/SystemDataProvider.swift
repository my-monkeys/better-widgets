import Foundation
import IOKit.ps

struct SystemDataProvider: DataProvider {
    static let type = "system"
    let minimumInterval: TimeInterval = 30

    func fetch(spec: SourceSpec, paramValues: [String: String]) async throws -> Any {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        var memStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        _ = withUnsafeMutablePointer(to: &memStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = Double(vm_kernel_page_size)
        let memFree = Double(memStats.free_count + memStats.inactive_count) * pageSize

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey])

        var result: [String: Any] = [
            "datetime": ISO8601DateFormatter().string(from: Date()),
            "uptime": ProcessInfo.processInfo.systemUptime,
            "cpuLoad1m": loads[0],
            "memTotal": Double(ProcessInfo.processInfo.physicalMemory),
            "memFree": memFree,
            "diskTotal": Double(values?.volumeTotalCapacity ?? 0),
            "diskFree": Double(values?.volumeAvailableCapacityForImportantUsage ?? 0),
        ]
        if let battery = batteryInfo() {
            result["battery"] = battery
        }
        return result
    }

    /// nil on desktops without battery.
    private func batteryInfo() -> [String: Any]? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any],
              let capacity = info[kIOPSCurrentCapacityKey] as? Int,
              let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let charging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return ["level": Double(capacity) / Double(max), "charging": charging]
    }
}
