const std = @import("std");
pub const std_options: std.Options = .{
    .logFn = @import("log.zig").logFn,
};
const uefi = std.os.uefi;
const mem = @import("mem.zig");
const utils = @import("util.zig");
const BootInfo = @import("BootInfo.zig");
const DevicePath = uefi.protocol.DevicePath;

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    const boot_services = uefi.system_table.boot_services.?;
    const log = @import("log.zig");
    log.stdout.print("panic: {s}\n", .{msg}) catch {};
    log.stdout.flush() catch {};

    boot_services.stall(5*1000*1000) catch {};
    while (true) {
        boot_services.exit(uefi.handle, .aborted, null) catch {};
    }
}

pub const panic = std.debug.FullPanic(panicFn);

pub fn main() uefi.Error!void {
    const boot_services = uefi.system_table.boot_services.?;
    std.log.debug("Hello, World!", .{});

    try mem.init();
    const kernel_entry = try @import("load_kernel.zig").loadKernel();
    std.log.info("succesfully loaded kernel", .{});

    try BootInfo.alloc();
    try BootInfo.initFrameBuffer();
    const memory_map = try mem.getMemoryMap();
    try BootInfo.initFreePhysMemory(memory_map);
    try boot_services.exitBootServices(uefi.handle, memory_map.info.key);

    asm volatile (
        \\jmp *%[kernel_entry]
        :: [kernel_entry] "{rax}" (kernel_entry), [boot_info] "{rdi}" (BootInfo.instance) 
        : .{.rdi = true}
    );

    unreachable;
}
