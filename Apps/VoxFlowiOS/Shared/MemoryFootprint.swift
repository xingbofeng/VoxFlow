// DictusCore/MemoryFootprint.swift
import Foundation
import Darwin

/// Reads the resident memory footprint of the current process via Mach task info.
///
/// Keyboard extensions have a hard ~50 MB budget — iOS terminates the process
/// when it gets close. Logging RSS at lifecycle boundaries lets us see where
/// the spend goes (baseline vs transient peaks during rebuild) so we can
/// target reductions instead of guessing.
public enum MemoryFootprint {
    /// Current resident size (MB, integer). Returns -1 on failure.
    public static func residentMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        // phys_footprint is what iOS uses for the jetsam budget — closer to the
        // "real" number than resident_size, which excludes compressed pages.
        return Int(info.phys_footprint / (1024 * 1024))
    }
}
