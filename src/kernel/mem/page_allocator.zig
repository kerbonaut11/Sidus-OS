const std = @import("std");
const boot = @import("boot");
const mem = @import("../mem.zig");
pub const Error = std.mem.Allocator.Error;
const BitSet = std.DynamicBitSetUnmanaged;

var base_addr: usize = undefined;

var free_pages: BitSet = undefined;

pub fn initAlloc() !void {
    base_addr = std.math.maxInt(usize);
    var max_addr: usize = 0;

    for (boot.info.free_phys_memory) |*range| {
        base_addr = @min(base_addr, @intFromPtr(range.ptr));
        max_addr = @max(max_addr, @intFromPtr(range.ptr+range.len));
    }

    const len = std.mem.alignBackward(usize, (max_addr-base_addr), mem.page_size);
    const num_pages = @divExact(len, mem.page_size);

    free_pages = try BitSet.initEmpty(mem.init_allocator, num_pages);
}

pub fn initFreeSet() void {
    for (boot.info.free_phys_memory) |*range| {
        const start = @min(free_pages.bit_length, @divExact(@intFromPtr(range.ptr)-base_addr, mem.page_size));
        const end = @min(free_pages.bit_length, start+@divExact(range.len, mem.page_size));
        free_pages.setRangeValue(.{.start = start, .end = end}, true);
    }
    std.log.debug("{}", .{free_pages.bit_length});
}

pub fn alloc() Error!usize {
    const idx = free_pages.toggleFirstSet() orelse return Error.OutOfMemory;
    return base_addr +  idx*mem.page_size;
}

pub fn free(addr: usize) void {
    const idx = @divExact(addr-base_addr, mem.page_size);
    free_pages.unset(idx);
}
