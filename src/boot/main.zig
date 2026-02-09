const std = @import("std");
const uefi = std.os.uefi;
const GraphicsOutput = uefi.protocol.GraphicsOutput;

pub fn uefiString(comptime str: []const u8) [:0]const u16 {
    comptime var out: []const u16 = &.{};
    inline for (str) |ch| out = out ++ &[1]u16{ch};
    out = out ++ &[1]u16{0};
    return @ptrCast(out);
}

pub fn main() uefi.Error!void {
    const out = uefi.system_table.con_out.?;
    //const in = uefi.system_table.con_in.?;
    const boot_services = uefi.system_table.boot_services.?;

    const fs = (try boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null)).?;
    const volume = try fs.openVolume();
    const kernel = try volume.open(uefiString("EFI"), .read, .{});
    _ = kernel;

    const graphics = (try boot_services.locateProtocol(GraphicsOutput, null)).?;
    const frame_buffer: []u8 = @as([*]u8, @ptrFromInt(graphics.mode.frame_buffer_base))[0..graphics.mode.frame_buffer_size];

    var memory_map: [*]uefi.tables.MemoryDescriptor = undefined;
    var memory_map_size: usize = 0;
    var memory_map_key: uefi.tables.MemoryMapKey = undefined;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;
    std.debug.assert(boot_services._getMemoryMap(&memory_map_size, @ptrCast(&memory_map), &memory_map_key, &descriptor_size, &descriptor_version) == .buffer_too_small);

    const memory_map_slice = try boot_services.getMemoryMap(try boot_services.allocatePool(.boot_services_data, memory_map_size));
    var iter = memory_map_slice.iterator();
    var fmt_buf: [1024]u8 = undefined;
    while (iter.next()) |e| {
        const fmt = std.fmt.bufPrint(&fmt_buf, "{x}..{x}\r\n", .{e.physical_start, e.physical_start+e.number_of_pages*4096}) catch unreachable;
        for (fmt) |ch| _ = try out.outputString(&.{ch, 0});
    }

    try boot_services.exitBootServices(uefi.handle, memory_map_slice.info.key);

    @memset(frame_buffer, 0xff);
    //try uefi.system_table.boot_services.?.stall(5*1000*1000);
}
