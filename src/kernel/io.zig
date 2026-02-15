pub const ports = @import("io/ports.zig");
pub const mmapped = @import("io/mmapped.zig");
pub const pci = @import("io/pci.zig");

pub const outb = ports.outb;
pub const outw = ports.outw;
pub const outl = ports.outl;
pub const inb = ports.inb;
pub const inw = ports.inw;
pub const inl = ports.inl;
