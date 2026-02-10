export var boot_info: usize = 0;

export fn _start() callconv(.naked) noreturn {
    @export(&boot_info, .{.name = "__boot_info", .linkage = .link_once});
    _ = &boot_info;
    asm volatile (
        \\outb %[val], %[port]
        :: [val] "{al} "(@as(u8, 'a')), [port] "N{dx} "(@as(u16, 0x3f8))
    );

    while (true) {}
}
