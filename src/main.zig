export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\outb %[val], %[port]
        :: [val] "{al} "(@as(u8, 'a')), [port] "N{dx} "(@as(u16, 0x3f8))
    );

    while (true) {}
}
