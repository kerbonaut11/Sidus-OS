const std = @import("std");
const boot = @import("boot");
const mem = @import("../mem.zig");
const log = std.log.scoped(.paging);

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

    pub fn getOrCreateChildTable(e: *Entry, level: u8, overwrite: bool) MapError!Table {
        std.debug.assert(level > 1);

        if (e.present) {
            if (!e.leaf) return mem.physToVirt(Table, e.getAddr());

            if (!overwrite) {
                return error.AlreadyPresent;
            }

            freeTable(e.getAddr(), level-1);
        }

        e.* = .{
            .addr = createAddr(try allocTable()),
        };

        return mem.physToVirt(Table, e.getAddr());
    }
};

pub fn allocTable() !usize {
    const new = try mem.phys_page_allocator.alloc();
    @memset(mem.physToVirt(Table, new), Entry.not_present);
    return new;
}

pub fn freeTable(paddr: usize, level: u8) void {
    if (level == 0) return;

    defer mem.phys_page_allocator.free(paddr);

    for (mem.physToVirt(Table, paddr)) |*e| {
        if (e.leaf or !e.present) continue;
        freeTable(e.getAddr(), level-1);
    }
}


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
        return entry.getAddr() + (vaddr & mask);
    }

    return virtToPhysInner(vaddr, flags, level-1, entry.getAddr());
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

pub const MapFlags = packed struct {
    forced_paddr: usize = std.math.maxInt(usize),
    write: bool = true,
    execute: bool = true,
    overwrite: bool = false,
    chace_disable: bool = false,
    write_through: bool = false,

    pub fn forcePaddr(flags: MapFlags) bool {
        return flags.forced_paddr != std.math.maxInt(usize);
    }
};

pub const MapError = error {AlreadyPresent} || std.mem.Allocator.Error;

pub fn map(vaddr: usize, num_pages: usize, flags: MapFlags) !void {
    var l4_idx: u9 = @truncate(vaddr >> (12+9*3));
    var l3_idx: u9 = @truncate(vaddr >> (12+9*2));
    var l2_idx: u9 = @truncate(vaddr >> (12+9*1));
    var l1_idx: u9 = @truncate(vaddr >> (12+9*0));
    const l4_table = getL4();
    var l3_table = try l4_table[l4_idx].getOrCreateChildTable(4, flags.overwrite);
    var l2_table = try l3_table[l3_idx].getOrCreateChildTable(3, flags.overwrite);

    var pages_mapped: usize = 0;

    while (true) {
        const forced_paddr = flags.forced_paddr +% pages_mapped*mem.page_size;

        const map_huge_page = l1_idx == 0 and (num_pages-pages_mapped) >= table_size and flags.forcePaddr() and std.mem.isAligned(forced_paddr, mem.huge_page_size);
        const l1_table = if (!map_huge_page) try l2_table[l2_idx].getOrCreateChildTable(2, flags.overwrite) else null;

        if (!flags.overwrite) {
            const already_present  = if (map_huge_page) l2_table[l2_idx].present else l1_table.?[l1_idx].present;
            if (already_present) return error.AlreadyPresent;
        }


        const paddr = if(flags.forcePaddr())
            flags.forced_paddr + pages_mapped*mem.page_size
        else if (map_huge_page)
            @panic("todo")
        else 
            try mem.phys_page_allocator.alloc();

        const new_entry = Entry{
            .addr = @truncate(paddr >> 12),
            .write = flags.write,
            .execute_disable = !flags.execute,
            .leaf = map_huge_page,
            .chace_disable = flags.chace_disable,
            .write_through = flags.write_through,
        };

        log.debug("mapped 0x{x} to 0x{x}", .{vaddr+pages_mapped*mem.page_size, paddr});

        if (map_huge_page) {
            l2_table[l2_idx] = new_entry;
            pages_mapped += table_size;
        } else {
            l1_table.?[l1_idx] = new_entry;
            pages_mapped += 1;
            l1_idx +%= 1;
        }

        if (pages_mapped == num_pages) return;

        if (l1_idx == 0 or map_huge_page) {
            l2_idx +%= 1;

            if (l2_idx == 0) {
                l3_idx +%= 1;

                if (l3_idx == 0) {
                    l4_idx += 1;
                    l3_table = try l4_table[l4_idx].getOrCreateChildTable(4, flags.overwrite);
                }

                l2_table = try l3_table[l3_idx].getOrCreateChildTable(3, flags.overwrite);
            }
        }
    }
}
