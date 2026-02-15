const std = @import("std");
const boot = @import("boot");
const mem = @import("../mem.zig");

pub const Entry = packed struct(u64) {
    pub const not_present = std.mem.zeroes(Entry);

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

    pub fn createAddr(paddr: usize) u40 {
        return @truncate(@divExact(paddr, mem.page_size));
    }

    pub fn getOrCreateChildTable(e: *Entry) !usize {
        if (e.present) {
            std.debug.assert(!e.leaf);
            return e.getAddr();
        } 

        e.* = .{
            .addr = createAddr(try allocTable()),
        };

        return e.getAddr();
    }
};

pub const page_size = 4096;
pub const huge_page_size= table_size*page_size;
pub const table_size = 512;
pub const Table = *align(4096) [table_size]Entry;

pub fn physToVirt(comptime T: type, paddr: usize) T {
    if (paddr > boot.phys_mirror_len) @panic("padd to high");

    return @ptrFromInt(boot.phys_mirror_start+paddr);
}

pub fn allocTable() !usize {
    const new = try mem.page_allocator.alloc();
    @memset(mem.physToVirt(Table, new), Entry.not_present);
    return new;
}

pub fn setL4(table: usize) void {
    asm volatile (
        \\movq %rax, %cr3
        :: [l4] "{rax}" (table)
    );
}

pub fn getL4() Table {
    return physToVirt(Table, asm volatile (
        \\movq %cr3, %rax
        : [l4] "={rax}" (->usize)
    ));
}
