const std = @import("std");
const uefi = std.os.uefi;
const GraphicsOutput = uefi.protocol.GraphicsOutput;
const mem = @import("mem.zig");
const BootInfo = @This();

free_phys_memory: [][]u8,
frame_buffer: struct {
    width: u32,
    height: u32,
    format: enum {
        rbga8, bgra8,
    },
    bytes_per_row: u32,
    base_addr: usize,
},

pub var instance: *BootInfo = undefined;
var free_phys_memory_buffer: [][]u8 = undefined;

pub fn alloc() !void {
    const boot_services = uefi.system_table.boot_services.?;
    instance = @ptrCast(try boot_services.allocatePool(.loader_data, @sizeOf(BootInfo)));

    const memory_map = try boot_services.getMemoryMapInfo();
    free_phys_memory_buffer = @ptrCast(try boot_services.allocatePool(.loader_data, memory_map.len*@sizeOf([]u8)));
}

pub fn initFrameBuffer() !void {
    const boot_services = uefi.system_table.boot_services.?;
    const graphics = (try boot_services.locateProtocol(GraphicsOutput, null)).?;
    const info = graphics.mode.info;
    const bytes_per_pixel = 4;
    instance.frame_buffer = .{
        .width = info.pixels_per_scan_line,
        .height = info.vertical_resolution,
        .base_addr = graphics.mode.frame_buffer_base,
        .bytes_per_row = info.horizontal_resolution*bytes_per_pixel,
        .format = switch (info.pixel_format) {
            .red_green_blue_reserved_8_bit_per_color => .rbga8,
            .blue_green_red_reserved_8_bit_per_color => .bgra8,
            .blt_only, .bit_mask => @panic("todo"),
        }
    };

    std.log.info(
        "detected {}x{} {} frame buffer at 0x{x}",
        .{instance.frame_buffer.width, instance.frame_buffer.height, instance.frame_buffer.format, instance.frame_buffer.base_addr}
    );

}

pub fn initFreePhysMemory(memory_map: uefi.tables.MemoryMapSlice) !void {
    var free_phys_memory = std.ArrayList([]u8).initBuffer(free_phys_memory_buffer);

    var iter = memory_map.iterator();
    while (iter.next()) |e| {
        const usable = switch (e.type) {
            .loader_data, .boot_services_data, .boot_services_code, .conventional_memory, .persistent_memory => true,
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
    instance.free_phys_memory = free_phys_memory.items;
}
