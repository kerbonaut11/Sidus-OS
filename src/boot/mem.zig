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
pub const mega_page_size= table_size*std.heap.pageSize();
const table_size = 512;
pub const Table = *align(page_size) [table_size]Entry;
var l4_table: Table = undefined;

pub fn init() !void {
    l4_table = try allocTable();
    @memcpy(l4_table, getL4());
    setL4(l4_table);
}

fn allocMegaPage() !usize {
    const boot_services = uefi.system_table.boot_services.?;

    const over_alloc = try boot_services.allocatePages(.any, .loader_data, 2*table_size);
    const alread_aligened = @intFromPtr(over_alloc.ptr) % mega_page_size == 0;
    const num_unaligend_pages_before = if (alread_aligened) 0 else @divExact(mega_page_size-@intFromPtr(over_alloc.ptr)%mega_page_size, page_size);

    try boot_services.freePages(over_alloc[0..num_unaligend_pages_before]);
    try boot_services.freePages(over_alloc[num_unaligend_pages_before+table_size..]);

    return @intFromPtr(over_alloc.ptr)+num_unaligend_pages_before*page_size;
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
    var l1_table = try l2_table[l2_idx].getOrAllocTable();

    var pages_left: usize = pages;
    while (pages_left != 0) {
        const map_2mib_page = l1_idx == 0 and pages_left >= table_size;

        const phys_mem = if (!map_2mib_page)
            @intFromPtr((try boot_services.allocatePages(.any, .loader_data, 1)).ptr)
        else 
            try allocMegaPage();

        if (map_2mib_page) std.debug.assert(std.mem.isAligned(phys_mem, mega_page_size));

        const new_entry = Entry{
            .addr = @truncate(phys_mem >> 12),
            .write = write,
            .execute_disable = !execute,
            .leaf = map_2mib_page,
        };

        if (map_2mib_page) {
            l2_table[l2_idx] = new_entry;
            pages_left -= table_size;
        } else {
            l1_table[l1_idx] = new_entry;
            pages_left -= 1;
            l1_idx +%= 1;
        }

        log.debug(
          "maped {s} page at 0x{x} to 0x{x}000",
          .{if (map_2mib_page) "2Mib" else "4Kib", vaddr+(pages-pages_left)*page_size, new_entry.addr}
        );

        if (l1_idx == 0 or map_2mib_page) {
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
