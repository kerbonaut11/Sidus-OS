var stack: [8*1024*1024]u8 align(4096) = undefined;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\movq %[stack_top], %rsp
        :: [stack_top] "r" (@intFromPtr(&stack)+@sizeOf(@TypeOf(stack)))
    );
    asm volatile (
        \\outb %[val], %[port]
        :: [val] "{al} "(@as(u8, 'a')), [port] "N{dx} "(@as(u16, 0x3f8))
    );

    while (true) {}
}
