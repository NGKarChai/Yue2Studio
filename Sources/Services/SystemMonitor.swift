import Foundation
import Darwin

public struct MemoryStats: Sendable {
    public let usedGB: Double
    public let totalGB: Double
    public let percentage: Double

    public var displayString: String {
        return String(format: "RAM: %.1f / %.0f GB (%.0f%%)", usedGB, totalGB, percentage)
    }
}

public struct SystemMonitor {
    public static func getUnifiedMemoryStats() -> MemoryStats {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / (1024 * 1024 * 1024)

        if kerr == KERN_SUCCESS {
            let activePages = UInt64(vmStat.active_count)
            let wiredPages = UInt64(vmStat.wire_count)
            let compressedPages = UInt64(vmStat.compressor_page_count)
            let usedBytes = (activePages + wiredPages + compressedPages) * UInt64(pageSize)
            let usedGB = Double(usedBytes) / (1024 * 1024 * 1024)
            let pct = (usedGB / totalGB) * 100.0
            return MemoryStats(usedGB: usedGB, totalGB: totalGB, percentage: pct)
        }

        return MemoryStats(usedGB: 0.0, totalGB: totalGB, percentage: 0.0)
    }
}
