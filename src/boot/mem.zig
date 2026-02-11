const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.vmem);

pub fn allocTable() !Table {
    const boot_services = uefi.system_table.boot_services.?;

    const bytes = try boot_services.allocatePages(.any, .loader_data, 1);
    @memset(&bytes[0], 0);
    return @ptrCast(bytes.ptr);
}

pub const Entry = packed struct(u64) {
    present: bool = true,
    read_write: bool = true,
    user: bool = false,
    write_through: bool = false,
    chace_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    leaf: bool = false,
    global: bool = true,
    _pad0: u3 = 0,
    addr: u40,
    _pad: u11 = 0,
    execute_disable: bool = false,

    pub fn getAddr(e: Entry) usize {
        return @as(usize, e.addr) << 12;
    }

    pub fn getOrAllocTable(e: *Entry) !Table {
        if (e.present) {
            return @ptrFromInt(e.getAddr());
        }

        const new = try allocTable();
        e.* = .{.addr = @truncate(@intFromPtr(new) >> 12)};
        return new;
    }
};

pub const page_size = std.heap.pageSize();
const table_size = 512;
pub const Table = *align(page_size) [table_size]Entry;
var l4_table: Table = undefined;

pub fn init() !void {
    l4_table = try allocTable();
    @memcpy(l4_table, getL4());
}

pub fn enableNewMmap() void {
    setL4(l4_table);
}

pub fn map(paddr: usize, vaddr: usize, pages: usize) !void {
    std.debug.assert(std.mem.isAligned(paddr, page_size));
    std.debug.assert(std.mem.isAligned(vaddr, page_size));

    const l4_idx: u9 = @truncate(vaddr >> (12+9*3));
    var l3_idx: u9 = @truncate(vaddr >> (12+9*2));
    var l2_idx: u9 = @truncate(vaddr >> (12+9*1));
    var l1_idx: u9 = @truncate(vaddr >> (12+9*0));
    log.debug("{} {} {} {}", .{l4_idx, l3_idx, l2_idx, l1_idx});
    var l3_table = try l4_table[l4_idx].getOrAllocTable();
    var l2_table = try l3_table[l3_idx].getOrAllocTable();
    var l1_table = try l2_table[l2_idx].getOrAllocTable();
    log.debug("{*} {*} {*} {*}", .{l4_table, l3_table, l2_table, l1_table});

    var pages_maped: usize = 0;
    while (pages_maped != pages) {
        const addr: u40 = @truncate((paddr >> 12) + pages_maped);

        if (l1_idx == 0 and (pages-pages_maped) >= table_size) {
            log.debug("maped 2Mib page at 0x{x} to 0x{x}000", .{vaddr+pages_maped*page_size, addr});
            l2_table[l2_idx] = .{.addr = addr, .leaf = true};
            pages_maped += table_size;
        } else {
            log.debug("maped 1Kib page at 0x{x} to 0x{x}000", .{vaddr+pages_maped*page_size, addr});
            l1_table[l1_idx] = .{.addr = addr};
            pages_maped += 1;
            l1_idx +%= 1;
        }

        if (l1_idx == 0) {
            l2_idx +%= 1;
            l1_table = try l2_table[l2_idx].getOrAllocTable();
        }

        if (l2_idx == 0) {
            l3_idx += 1;
            l2_table = try l3_table[l3_idx].getOrAllocTable();
        }

    }
}


pub fn setL4(table: Table) void {
    asm volatile (
        \\movq %rax, %cr3
        :: [l4] "{rax}" (table)
    );
}

pub fn getL4() Table {
    return asm volatile (
        \\movq %cr3, %rax
        : [l4] "={rax}" (->Table)
    );
}

pub fn getMemoryMap() !uefi.tables.MemoryMapSlice {
    const boot_services = uefi.system_table.boot_services.?;

    const info = try boot_services.getMemoryMapInfo();
    const pool = try boot_services.allocatePool(.loader_data, (info.len+32)*info.descriptor_size);
    return try boot_services.getMemoryMap(pool);
}
