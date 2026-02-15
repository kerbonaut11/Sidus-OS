const std = @import("std");
const mem = @import("../mem.zig");

const l4_idx = 256+2;
pub const start_addr = 0xffff800000000000 | (l4_idx << (12+9*3));
pub const max_size = mem.gib*mem.paging.table_size;
var l3_table: mem.paging.Table = undefined;
var l3_idx: u9 = 0;
var l2_idx: u9 = 0;
var addr: usize = start_addr;

pub fn init() !void {
    const l3_addr = try mem.page_allocator.alloc();
    mem.paging.getL4()[l4_idx] = .{
        .addr = mem.paging.Entry.createAddr(l3_addr),
    };
    l3_table = mem.physToVirt(mem.paging.Table, l3_addr);
}

pub fn create(comptime T: type, paddr: usize, len: usize) !T {
    const start = std.mem.alignBackward(usize, paddr, mem.huge_page_size);
    const end = std.mem.alignForward(usize, paddr+len, mem.huge_page_size);
    const num_huge_pages = @divExact(end-start, mem.huge_page_size);
    const result = addr + paddr%mem.huge_page_size;

    var map_paddr = start;
    for (0..num_huge_pages) |_| {
        const l2_table = mem.physToVirt(mem.paging.Table, try l3_table[l3_idx].getOrCreateChildTable());
        l2_table[l2_idx] = mem.paging.Entry{
            .leaf = true,
            //.chace_disable = true,
            //.write_through = true,
            .addr = mem.paging.Entry.createAddr(map_paddr),
        };

        map_paddr += mem.huge_page_size;
        addr += mem.huge_page_size;
        l2_idx +%= 1;
        if (l2_idx == 0) {
            l3_idx += 1;
        }
    }

    return @ptrFromInt(result);
}


