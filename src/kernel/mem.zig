const std = @import("std");
const boot = @import("boot");

pub const paging = @import("mem/paging.zig");
pub const page_allocator = @import("mem/page_allocator.zig");

pub const phys_mirror_start = boot.phys_mirror_start;
pub const phys_mirror_len = boot.phys_mirror_len;
pub const page_size = paging.page_size;
pub const huge_page_size = paging.huge_page_size;
pub const physToVirt = paging.physToVirt;
pub const virtToPhys = paging.virtToPhys;

pub const kib = 1024;
pub const mib = kib*1024;
pub const gib = mib*1024;

pub var init_allocator: std.mem.Allocator = undefined;
pub var init_allocator_instance: std.heap.FixedBufferAllocator = undefined;
var init_allocator_range_idx: usize = 0;

pub fn init() void {
    for (boot.info.free_phys_memory, 0..) |*range, i| {
        if (range.len > boot.info.free_phys_memory[init_allocator_range_idx].len) init_allocator_range_idx = i;
    }

    init_allocator_instance = .init(boot.info.free_phys_memory[init_allocator_range_idx]);
    init_allocator = init_allocator_instance.allocator();
}

pub fn initAllocators() void {
    page_allocator.initAlloc() catch unreachable;

    const init_range: *[]align(page_size) u8 = &boot.info.free_phys_memory[init_allocator_range_idx];
    init_range.* = @alignCast(init_range.*[std.mem.alignForward(usize, init_allocator_instance.end_index, page_size)..]);
    init_allocator = std.testing.failing_allocator;
    init_allocator_instance = .init(&.{});

    page_allocator.initFreeSet();
}
