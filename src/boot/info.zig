const std = @import("std");
const uefi = std.os.uefi;
const mem = @import("mem.zig");
const BootInfo = @This();

free_phys_memory: [][]u8,

var inst: BootInfo = undefined;
var free_phys_memory_buffer: [64][]u8 = undefined;

pub fn setFreePhysMemory(memory_map: uefi.tables.MemoryMapSlice, log: bool) !void {
    var free_phys_memory = std.ArrayList([]u8).initBuffer(@ptrCast(&free_phys_memory_buffer));

    var iter = memory_map.iterator();
    while (iter.next()) |e| {
        const usable = switch (e.type) {
            .boot_services_data, .boot_services_code, .conventional_memory, .persistent_memory => true,
            else => false,
        };
        if (!usable or e.physical_start == 0) continue;

        const slice = @as([*]u8, @ptrFromInt(e.physical_start))[0..e.number_of_pages*mem.page_size];

        if (free_phys_memory.getLastOrNull()) |last| {
            if (@intFromPtr(last.ptr)+last.len == e.physical_start) {
                free_phys_memory.items[free_phys_memory.items.len-1].len += e.number_of_pages*mem.page_size;
                continue;
            }
        }
        free_phys_memory.appendAssumeCapacity(slice);
    }

    if (!log) return;

    var total_free: usize = 0;
    for (free_phys_memory.items) |e| {
        total_free += e.len;
        std.log.info("free memory: 0x{x}..0x{x} ({Bi})", .{@intFromPtr(e.ptr), @intFromPtr(e.ptr)+e.len, e.len});
    }

    std.log.info("total free memory: {Bi}", .{total_free});
}


pub fn logFreeMemory() !void {
    const memory_map = try mem.getMemoryMap();
    setFreePhysMemory(memory_map, true);
}
