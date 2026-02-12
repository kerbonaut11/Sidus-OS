const std = @import("std");
const log = @import("log.zig");
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = log.logFn,
};

var stack: [8*1024*1024]u8 align(4096) = undefined;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\movq %[stack_top], %rsp
        \\movq %rsp, %rbp
        \\call main
        :: [stack_top] "r" (@intFromPtr(&stack)+@sizeOf(@TypeOf(stack))),
    );
}

export fn main(boot_info: *@import("BootInfo")) callconv(.c) noreturn {
    log.init(@import("drivers/uart16550.zig").init());
    std.log.debug("Hello, World!", .{});
    std.log.debug("{*}", .{boot_info});
    @import("pci.zig").lspci();
    while (true) {}
}
