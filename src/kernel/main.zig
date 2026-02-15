const std = @import("std");
const log = @import("log.zig");
const boot = @import("boot");
const mem = @import("mem.zig");
const io = @import("io.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = log.logFn,
};

fn panicFn(msg: []const u8, return_addr: ?usize) noreturn {
    if (return_addr) |addr| {
        log.writer.print("panic: {s} at 0x{x}", .{msg, addr}) catch {};
    } else {
        log.writer.print("panic: {s}", .{msg}) catch {};
    }
    log.writer.flush() catch {};

    while (true) {}
}

pub const panic = std.debug.FullPanic(panicFn);

export var stack: [stack_size]u8 align(4096) linksection(".bss") = undefined;
export const stack_size: usize = 8*1024*1024;

export fn _start() callconv(.naked) noreturn {
    boot.info = asm ("" : [info] "={rdi}" (->*boot.Info));

    const stack_top = @intFromPtr(&stack)+stack_size;

    asm volatile (
        \\movq %[stack_top], %rsp
        \\movq %rsp, %rbp
        \\callq main
        :: [stack_top] "r" (stack_top)
    );
}

export fn main() callconv(.c) noreturn {
    log.init(@import("drivers/uart16550.zig").init());
    std.log.debug("Hello, World!", .{});

    for (boot.info.free_phys_memory) |range| {
        std.log.debug("free memory {Bi} at 0x{x}", .{range.len, @intFromPtr(range.ptr)});
    }

    mem.init();
    mem.initAllocators();
    io.mmapped.init() catch {};

    while (true) {}
}
