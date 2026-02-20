const std = @import("std");
const mem = @import("../mem.zig");

const l4_idx = 256+2;
pub const start_addr = mem.heap_start+mem.heap_len;
pub const max_size = mem.gib*mem.paging.table_size;
var l3_table: mem.paging.Table = undefined;
var l3_idx: u9 = 0;
var l2_idx: u9 = 0;
var addr: usize = start_addr;

pub fn init() !void {
    const l3_addr = try mem.phys_page_allocator.alloc();
    mem.paging.getL4()[l4_idx] = .{
        .addr = mem.paging.Entry.createAddr(l3_addr),
    };
    l3_table = mem.physToVirt(mem.paging.Table, l3_addr);
}

pub fn createSlice(comptime T: type, paddr: usize, len: usize) ![]volatile T {
    const start = std.mem.alignBackward(usize, paddr, mem.huge_page_size);
    const end = std.mem.alignForward(usize, paddr+len*@sizeOf(T), mem.huge_page_size);
    try mem.paging.map(
        addr, @divExact(end-start, mem.page_size),
        .{.forced_paddr = start, .chace_disable = true, .write_through = false, .write = true}
    );
    addr += end-start;

    return @as([*]volatile T, @ptrFromInt(start + paddr%mem.huge_page_size))[0..len];
}


pub fn create(comptime T: type, paddr: usize) !*volatile T {
    return @ptrCast((try createSlice(T, paddr, 1)).ptr);
}


