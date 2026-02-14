const std = @import("std");
const boot = @import("boot");
const mem = @import("../mem.zig");
pub const Error = std.mem.Allocator.Error;
const BitSet = std.DynamicBitSetUnmanaged;
const BitSetSlice = std.bit_set.ArrayBitSet(usize, pages_per_huge_page);
const pages_per_huge_page = mem.huge_page_size/mem.page_size;

var base_addr: usize = undefined;

var free_pages: []BitSetSlice = &.{};
var free_huge_pages: BitSet = .{};
var partialy_free_huge_pages: BitSet = .{};


pub fn init() void {
    base_addr = std.math.maxInt(usize);
    var max_addr: usize = 0;
    var biggest_range: *[]u8 = @constCast(&@as([]u8, &.{}));

    for (boot.info.free_phys_memory) |*range| {
        base_addr = @min(base_addr, @intFromPtr(range.ptr));
        max_addr = @max(max_addr, @intFromPtr(range.ptr+range.len));
        if (range.len > biggest_range.len) biggest_range = @ptrCast(range);
    }

    const len = std.mem.alignBackward(usize, (max_addr-base_addr), 512*mem.page_size);

    var allocator = std.heap.FixedBufferAllocator.init(biggest_range.*);
    const num_huge_pages = @divExact(len, mem.huge_page_size);

    free_pages = allocator.allocator().alloc(BitSetSlice, num_huge_pages) catch unreachable;
    @memset(std.mem.sliceAsBytes(free_pages), 0);
    free_huge_pages = BitSet.initFull(allocator.allocator(), num_huge_pages) catch unreachable;
    partialy_free_huge_pages = BitSet.initFull(allocator.allocator(), num_huge_pages) catch unreachable;

    biggest_range.* = biggest_range.*[std.mem.alignForward(usize, allocator.end_index, mem.page_size)..];

    std.log.debug("{Bi}", .{len});
}

pub fn alloc() Error!usize {
    const huge_idx = partialy_free_huge_pages.findFirstSet() orelse return Error.OutOfMemory;
    const free_pages_slice: *BitSetSlice = free_pages[huge_idx];

    free_huge_pages.unset(huge_idx);
    const sub_idx = free_pages_slice.toggleFirstSet().?;

    if (std.mem.allEqual(usize, &free_pages_slice.masks, std.math.maxInt(usize))) partialy_free_huge_pages.unset(huge_idx);

    return base_addr + (huge_idx*pages_per_huge_page + sub_idx) * mem.page_size;
}

pub fn free(addr: usize) void {
    const idx = @divExact(addr-base_addr, mem.page_size);
    const huge_idx = idx / pages_per_huge_page;
    const sub_idx = idx % pages_per_huge_page;

    const free_pages_slice: *BitSetSlice = free_pages[huge_idx];
    free_pages_slice.unset(sub_idx);
    partialy_free_huge_pages.set(huge_idx);

    if (std.mem.allEqual(usize, &free_pages_slice.masks, 0)) free_huge_pages.unset(huge_idx);
}
