pub fn outb(port: u16, val: u8) void {
    asm volatile (
        \\outb %[val], %[port]
        :: [port] "N{dx} "(port), [val] "{al}" (val),
    );
}

pub fn outw(port: u16, val: u16) void {
    asm volatile (
        \\outw %[val], %[port]
        :: [port] "N{dx} "(port), [val] "{ax}" (val),
    );
}

pub fn outd(port: u16, val: u32) void {
    asm volatile (
        \\outd %[val], %[port]
        :: [port] "N{dx} "(port), [val] "{eax}" (val),
    );
}

pub fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[val]
        : [val] "={al}" (->u8) : [port] "N{dx} "(port)
    );
}

pub fn inw(port: u16) u16 {
    return asm volatile (
        \\inb %[port], %[val]
        : [val] "={ax}" (->u16) : [port] "N{dx} "(port)
    );
}

pub fn ind(port: u16) u32 {
    return asm volatile (
        \\inb %[port], %[val]
        : [val] "={eax}" (->u32) : [port] "N{dx} "(port)
    );
}
