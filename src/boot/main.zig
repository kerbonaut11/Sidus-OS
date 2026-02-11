const std = @import("std");
pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logFn,
};
const uefi = std.os.uefi;
const mem = @import("mem.zig");
const BootInfo = @import("info.zig");
const GraphicsOutput = uefi.protocol.GraphicsOutput;
const DevicePath = uefi.protocol.DevicePath;

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    const log = @import("log.zig");
    log.stdout.print("panic: {s}\n", .{msg}) catch {};
    log.stdout.flush() catch {};
    std.process.exit(1);
}

pub const panic = std.debug.FullPanic(panicFn);

pub fn main() uefi.Error!void {
    const boot_services = uefi.system_table.boot_services.?;
    std.log.debug("Hello, World!", .{});

    try mem.init();
    const kernel_entry = @import("load_kernel.zig").loadKernel() catch unreachable;
    std.log.info("succesfully loaded kernel", .{});

    const graphics = (try boot_services.locateProtocol(GraphicsOutput, null)).?;
    const info = graphics.mode.info;
    const frame_buffer: []u8 = @as([*]u8, @ptrFromInt(graphics.mode.frame_buffer_base))[0..graphics.mode.frame_buffer_size];
    std.log.info(
        "detected {}x{} {} frame buffer at 0x{x}",
        .{info.horizontal_resolution, info.vertical_resolution, info.pixel_format, @intFromPtr(frame_buffer.ptr)}
    );

    const log_memory_map = try mem.getMemoryMap();
    try BootInfo.setFreePhysMemory(log_memory_map, true);
    try boot_services.freePool(log_memory_map.ptr);

    const memory_map = try mem.getMemoryMap();
    try boot_services.exitBootServices(uefi.handle, memory_map.info.key);
    try BootInfo.setFreePhysMemory(memory_map, false);

    asm volatile (
        \\jmp *%rax
        :: [kernel_entry] "{rax}" (kernel_entry)
    );

    unreachable;
}
