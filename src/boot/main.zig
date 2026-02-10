const std = @import("std");
pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logFn,
};
const uefi = std.os.uefi;
const vmem = @import("vmem.zig");
const exit = @import("exit.zig");
const GraphicsOutput = uefi.protocol.GraphicsOutput;

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

    const kernel_entry = @import("load_kernel.zig").loadKernel() catch unreachable;
    std.log.info("succesfully loaded kernel", .{});

    const graphics = (try boot_services.locateProtocol(GraphicsOutput, null)).?;
    const frame_buffer: []u8 = @as([*]u8, @ptrFromInt(graphics.mode.frame_buffer_base))[0..graphics.mode.frame_buffer_size];
    const frame_buffer_info = graphics.mode.info;
    std.log.info(
        "detected {}x{} {} frame buffer at 0x{x}",
        .{frame_buffer_info.vertical_resolution, frame_buffer_info.horizontal_resolution, frame_buffer_info.pixel_format, @intFromPtr(frame_buffer.ptr)}
    );

    try exit.exitBootServices();

    vmem.writeCr3();

    asm volatile (
        \\jmp *%rax
        :: [kernel_entry] "{rax}" (kernel_entry)
    );

    unreachable;
}
