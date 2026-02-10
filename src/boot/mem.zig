const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.vmem);

pub const page_size = std.heap.pageSize();
var l4: ?Table = null;

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
};

pub const Table = *align(page_size) [512]Entry;

pub fn allocTable() !Table {
    const boot_services = uefi.system_table.boot_services.?;

    const bytes = try boot_services.allocatePages(.any, .loader_data, 1);
    @memset(&bytes[0], 0);
    return @ptrCast(bytes.ptr);
}

pub fn map(paddr: usize, vaddr: usize, pages: usize) !void {
    for (0..pages) |i| {
        try mapPage(paddr+i*page_size, vaddr+i*page_size);
    }
}

pub fn mapPage(paddr: usize, vaddr: usize) !void {
    log.debug("mapping 0x{x} to 0x{x}", .{paddr, vaddr});
    std.debug.assert(std.mem.isAligned(paddr, page_size));
    std.debug.assert(std.mem.isAligned(vaddr, page_size));

    var table = l4 orelse blk: {
        const uefi_l4 = readCr3();
        l4 = try allocTable();
        @memcpy(l4.?, uefi_l4);
        break :blk l4.?;
    };

    const parts = [4]u9{
        @truncate(vaddr >> (12+9*3)),
        @truncate(vaddr >> (12+9*2)),
        @truncate(vaddr >> (12+9*1)),
        @truncate(vaddr >> (12+9*0)),
    };

    for (parts[0..3]) |part| {
        if (!table[part].present) {
            const new_table = try allocTable();
            table[part] = Entry{.addr = @intCast(@intFromPtr(new_table) >> 12)};
            log.debug("0x{x}", .{@intFromPtr(new_table)});
            table = new_table;
        } else {
            table = @ptrFromInt(@as(usize, table[part].addr) << 12);
        }
    }

    std.debug.assert(!table[parts[3]].present);
    table[parts[3]] = Entry{.addr = @intCast(paddr >> 12)};
}


pub fn getMemoryMap() !uefi.tables.MemoryMapSlice {
    const boot_services = uefi.system_table.boot_services.?;

    const info = try boot_services.getMemoryMapInfo();
    const pool = try boot_services.allocatePool(.loader_data, (info.len+32)*info.descriptor_size);
    return try boot_services.getMemoryMap(pool);

}

pub fn writeCr3() void {
    asm volatile (
        \\movq %rax, %cr3
        :: [l4] "{rax}" (l4)
    );
}

pub fn readCr3() Table {
    return asm volatile (
        \\movq %cr3, %rax
        : [l4] "={rax}" (->Table)
    );
}
