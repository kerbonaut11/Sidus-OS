const std = @import("std");
const log = @import("log.zig");
const boot = @import("boot");
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = log.logFn,
};

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    log.writer.print("panic: {s}\n", .{msg}) catch {};
    log.writer.flush() catch {};

    while (true) {}
}

pub const panic = std.debug.FullPanic(panicFn);

export var stack: [8*1024*1024]u8 align(4096) = undefined;
export const stack_size: usize = @sizeOf(@TypeOf(stack));

export fn _start() callconv(.naked) noreturn {
    const stack_top = @intFromPtr(&stack)+stack_size;

    asm volatile (
        \\movq %[stack_top], %rsp
        \\movq %rsp, %rbp
        \\callq main
        :: [stack_top] "r" (stack_top)
    );
}

export fn main(boot_info: *boot.Info) callconv(.c) noreturn {
    boot.info = boot_info;

    log.init(@import("drivers/uart16550.zig").init());
    std.log.debug("Hello, World!", .{});

    for (boot.info.free_phys_memory) |mem| {
        std.log.debug("free memory {Bi} at 0x{x}", .{mem.len, @intFromPtr(mem.ptr)});
    }

    while (true) {}
}
