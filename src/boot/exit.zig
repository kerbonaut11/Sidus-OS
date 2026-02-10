const std = @import("std");
const uefi = std.os.uefi;

fn getMemoryMapKey() !uefi.tables.MemoryMapKey {
    const boot_services = uefi.system_table.boot_services.?;

    const info = try boot_services.getMemoryMapInfo();
    const pool = try boot_services.allocatePool(.boot_services_data, info.len*(info.descriptor_size+8));
    const slice = try boot_services.getMemoryMap(pool);
    return slice.info.key;
}

pub fn exitBootServices() !void {
    const boot_services = uefi.system_table.boot_services.?;
    try boot_services.exitBootServices(uefi.handle, try getMemoryMapKey());
}
