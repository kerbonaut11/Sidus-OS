const std = @import("std");
pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logFn,
};
const uefi = std.os.uefi;
const mem = @import("mem.zig");
const BootInfo = @import("BootInfo.zig");
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

    try BootInfo.alloc();
    try BootInfo.initFrameBuffer();
    const memory_map = try mem.getMemoryMap();
    try BootInfo.initFreePhysMemory(memory_map);
    try boot_services.exitBootServices(uefi.handle, memory_map.info.key);

    asm volatile (
        \\mov %rdi, %[boot_info]
        \\jmp *%[kernel_entry]
        :: [kernel_entry] "r" (kernel_entry), [boot_info] "r" (BootInfo.instance)
    );

    unreachable;
}
