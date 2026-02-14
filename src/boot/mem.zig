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

    pub fn getOrAllocTable(e: *Entry) !Table {
        if (e.present) {
            std.debug.assert(!e.leaf);
            return @ptrFromInt(e.getAddr());
        }

        const new = try allocTable();
        e.* = .{.addr = @truncate(@intFromPtr(new) >> 12)};
        return new;
    }
};

pub const page_size = 4096;
pub const huge_page_size= table_size*page_size;
pub const huge_gib_page_size = table_size*huge_page_size;
const table_size = 512;
pub const Table = *align(page_size) [table_size]Entry;
var l4_table: Table = undefined;

pub fn init() !void {
    l4_table = try allocTable();
    @memcpy(l4_table, getL4());
    setL4(l4_table);
    try createPhysMirror();
}

var huge_page_alloc_addr: usize = 0;

fn allocHugePage() !usize {
    const boot_services = uefi.system_table.boot_services.?;

    if (huge_page_alloc_addr == 0) {
        var iter = (try getMemoryMap()).iterator();
        var biggest_free_range = std.mem.zeroes(uefi.tables.MemoryDescriptor);
        while (iter.next()) |range| {
            if (range.type != .conventional_memory) continue;
            if (range.number_of_pages <= biggest_free_range.number_of_pages) continue;
            biggest_free_range = range.*;
        }
        log.info("found {Bi} for allocating huge pages", .{biggest_free_range.number_of_pages*page_size});
        huge_page_alloc_addr = std.mem.alignForward(usize, biggest_free_range.physical_start, huge_page_size);
    }

    const max_retries = 128;
    for (0..max_retries) |_| {
        defer huge_page_alloc_addr += huge_page_size;
        const alloc_result = boot_services.allocatePages(.{ .address = @ptrFromInt(huge_page_alloc_addr) }, .loader_data, table_size);
        const pages = alloc_result catch |err| if (err == error.NotFound) continue else return err;
        const addr = @intFromPtr(pages.ptr);
        std.debug.assert(std.mem.isAligned(addr, huge_page_size));
        return addr;
    }

    return uefi.Error.OutOfResources;
}

pub fn createMap(vaddr: usize, pages: usize, write: bool, execute: bool) !void {
    const boot_services = uefi.system_table.boot_services.?;
    std.debug.assert(std.mem.isAligned(vaddr, page_size));

    const l4_idx: u9 = @truncate(vaddr >> (12+9*3));
    var l3_idx: u9 = @truncate(vaddr >> (12+9*2));
    var l2_idx: u9 = @truncate(vaddr >> (12+9*1));
    var l1_idx: u9 = @truncate(vaddr >> (12+9*0));
    var l3_table = try l4_table[l4_idx].getOrAllocTable();
    var l2_table = try l3_table[l3_idx].getOrAllocTable();

    var pages_left: usize = pages;
    while (pages_left != 0) {
        const map_huge_page = l1_idx == 0 and pages_left >= table_size;
        const l1_table = if (!map_huge_page) try l2_table[l2_idx].getOrAllocTable() else null;

        const already_present = if (map_huge_page) l2_table[l2_idx].present else l1_table.?[l1_idx].present;
        if (map_huge_page and already_present) std.debug.assert(l2_table[l2_idx].leaf);

        if (!already_present) {
            const phys_mem = if (map_huge_page)
                try allocHugePage()
            else 
                @intFromPtr((try boot_services.allocatePages(.any, .loader_data, 1)).ptr);

            const new_entry = Entry{
                .addr = @truncate(phys_mem >> 12),
                .write = write,
                .execute_disable = !execute,
                .leaf = map_huge_page,
            };

            if (map_huge_page) {
                l2_table[l2_idx] = new_entry;
            } else {
                l1_table.?[l1_idx] = new_entry;
            }

            log.debug(
            "maped {s} page at 0x{x} to 0x{x}000",
            .{if (map_huge_page) "2Mib" else "4Kib", vaddr+(pages-pages_left)*page_size, new_entry.addr}
            );
        }

        if (map_huge_page) {
            pages_left -= table_size;
        } else {
            pages_left -= 1;
            l1_idx +%= 1;
        }

        if (l1_idx == 0 or map_huge_page) {
            l2_idx +%= 1;
            if (l2_idx == 0) {
                l3_idx += 1;
                l2_table = try l3_table[l3_idx].getOrAllocTable();
            }
        }
    }
}

pub const phys_mirror_start = 0xffff800000000000 | (1 << (12+9*3));
pub const phys_mirror_len = huge_gib_page_size*table_size;

pub fn createPhysMirror() !void {
    const l4_idx: u9 = @truncate(phys_mirror_start >> (12+9*3));
    std.debug.assert(!l4_table[l4_idx].present);
    const l3_table = try l4_table[l4_idx].getOrAllocTable();

    var addr: usize = 0;
    for (l3_table) |*entry| {
        entry.* = .{
            .leaf = true,
            .addr = @truncate(addr >> 12),
        };
        addr += huge_gib_page_size;
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
    const pool = try boot_services.allocatePool(.loader_code, (info.len+32)*info.descriptor_size);
    return try boot_services.getMemoryMap(pool);
}
