const std = @import("std");
const boot = @import("boot");

pub const Entry = packed struct(u64) {
    present: bool = true,
    write: bool = true,
    user: bool = false,
    write_through: bool = false,
    chace_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    leaf: bool = false,
    global: bool = false,
    _pad0: u3 = 0,
    addr: u40,
    _pad: u11 = 0,
    execute_disable: bool = false,

    pub fn getAddr(e: Entry) usize {
        return @as(usize, e.addr) << 12;
    }
};

pub const page_size = 4096;
pub const huge_page_size= table_size*page_size;
pub const table_size = 512;
pub const Table = [table_size]Entry;

pub fn physToVirt(comptime T: type, paddr: usize) ?T {
    if (paddr > boot.phys_mirror_len) return null;

    return @bitCast(boot.phys_mirror_start+paddr);
}

