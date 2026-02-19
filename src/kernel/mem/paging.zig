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
    if (paddr > boot.phys_mirror_len) @panic("paddr to high");

    return @ptrFromInt(boot.phys_mirror_start+paddr);
}

const VirtToPhysFlags = packed struct {

};

pub fn virtToPhys(ptr: anytype, flags: VirtToPhysFlags) ?usize {
    const vaddr = @intFromPtr(ptr);
    if (vaddr >= mem.phys_mirror_start and vaddr-mem.phys_mirror_start < mem.phys_mirror_len) return vaddr-boot.phys_mirror_start;

    return virtToPhysInner(vaddr, flags, 3, getL4Addr());
}

fn virtToPhysInner(vaddr: usize, flags: VirtToPhysFlags, level: u6, table: usize) ?usize {
    const entry_idx: u9 = @truncate(vaddr >> (12+9*level));
    const entry = physToVirt(Table, table)[entry_idx];
    if (!entry.present) return null;
    if (entry.leaf or level == 0) {
        const mask = (@as(usize, 1) << (12+9*level))-1;
        std.log.debug("{x} {x}", .{entry.getAddr(), vaddr & mask});
        return entry.getAddr() + (vaddr & mask);
    }

    return virtToPhysInner(vaddr, flags, level-1, entry.getAddr());
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

pub fn getL4Addr() usize {
    return asm volatile (
        \\movq %cr3, %rax
        : [l4] "={rax}" (->usize)
    );
}

pub fn getL4() Table {
    return physToVirt(Table, getL4Addr());
}
