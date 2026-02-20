const std = @import("std");
const mem = @import("../mem.zig");
const log = std.log.scoped(.PageAllocator);
const PageAllocator = @This();
const Allocator = std.mem.Allocator;

const Node = struct {
    const max_len = 128;
    const K = usize;
    const V = usize;

    _: void align(mem.page_size) = {},

    len: u32 = 0,
    min_key: K = 0,
    max_key: K = std.math.maxInt(usize),
    keys: [max_len]K = undefined,
    vals: [max_len]V = undefined,
    next: ?*Node = null,

    fn order(a: K, b: K) std.math.Order {
        return std.math.order(a, b);
    }
    
    comptime {
        std.debug.assert(max_len % 2 == 0);
        std.debug.assert(@sizeOf(Node) <= mem.page_size);
    }

    pub fn insert(node: *Node, key: K, val: V) !void {
        std.debug.assert(key >= node.min_key);

        if (key > node.max_key) {
            try node.next.?.insert(key, val);
            return;
        }

        if (node.len == max_len) {
            const split_key = node.keys[max_len/2];

            const new = mem.physToVirt(*Node, try mem.phys_page_allocator.alloc());
            new.* = .{
                .len = max_len/2,
                .min_key = split_key,
                .max_key = node.max_key,
                .next = node.next,
            };
            @memcpy(new.keys[0..max_len/2], node.keys[max_len/2..]);
            @memcpy(new.vals[0..max_len/2], node.vals[max_len/2..]);

            node.len = max_len/2;
            node.max_key = split_key-1;
            node.next = new;
        }

        const idx = std.sort.lowerBound(K, node.keys[0..node.len], key, order);

        @memmove(node.keys[idx..node.len], node.keys[idx+1..node.len+1]);
        @memmove(node.vals[idx..node.len], node.vals[idx+1..node.len+1]);
        node.len += 1;

        node.keys[idx] = key;
        node.vals[idx] = val;
    }

    pub fn getAndRemove(node: *Node, key: K, upper_bound: bool) ?struct{K,V} {
        std.debug.assert(key >= node.min_key);

        if (key <= node.max_key) {
            const idx = if (upper_bound) 
                std.sort.upperBound(K, node.keys[0..node.len], key, order)
            else
                std.sort.binarySearch(K, node.keys[0..node.len], key, order) orelse return null;

            const val = node.vals[idx];
            const found_key = node.keys[idx];

            //TODO merge

            @memmove(node.keys[idx+1..node.len], node.keys[idx..node.len-1]);
            @memmove(node.vals[idx+1..node.len], node.vals[idx..node.len-1]);
            node.len -= 1;

            return .{found_key, val};
        }

        if (node.next) |next| return next.getAndRemove(key, upper_bound);

        return null;
    }

    pub fn dump(node: *Node) void {
        for (0..node.len) |i| {
            log.debug("{x: >16} => {x: >16}", .{node.keys[i], node.vals[i]});
        }
        log.debug("-> {*}\n", .{node.next});

        if (node.next) |next| next.dump();
    }
};

free_by_size: *Node = undefined,
free_by_addr: *Node = undefined,

pub fn init(min_vaddr: usize, len: usize) !PageAllocator {
    const num_pages = @divExact(len, mem.page_size);
    const min_page_idx = @divExact(min_vaddr, mem.page_size);

    const free_by_size = mem.physToVirt(*Node, try mem.phys_page_allocator.alloc());
    free_by_size.* = .{};
    try free_by_size.insert(num_pages, min_page_idx);

    const free_by_addr = mem.physToVirt(*Node, try mem.phys_page_allocator.alloc());
    free_by_addr.* = .{.min_key = min_page_idx, .max_key = min_page_idx+num_pages-1};
    try free_by_addr.insert(min_page_idx, num_pages);

    return .{.free_by_size = free_by_size, .free_by_addr = free_by_addr};
}

fn allocPages(self: *PageAllocator, num_pages: usize) ?[*]align(mem.page_size) u8 {
    const num_pages_allocated, const page_idx = self.free_by_size.getAndRemove(num_pages, true) orelse return null;
    _ = self.free_by_addr.getAndRemove(page_idx, false).?;

    if (num_pages != num_pages_allocated) {
        self.free_by_size.insert(num_pages_allocated-num_pages, page_idx+num_pages) catch return null;
        self.free_by_addr.insert(page_idx+num_pages, num_pages_allocated-num_pages, ) catch return null;
    }

    mem.paging.map(page_idx*mem.page_size, num_pages, .{}) 
        catch |err| if (err == mem.paging.MapError.AlreadyPresent) unreachable else return null;

    return @ptrFromInt(page_idx*mem.page_size);
}

fn freePages(self: *PageAllocator, vaddr: usize, num_pages: usize) void {
    _ = self;
    _ = vaddr;
    _ = num_pages;
    @panic("todo");
}

fn alloc(self_opaque: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    std.debug.assert(@intFromEnum(alignment) < std.math.log2_int(usize, mem.page_size));

    const self: *PageAllocator = @ptrCast(@alignCast(self_opaque));
    const num_pages = std.mem.alignForward(usize, len, mem.page_size)/mem.page_size;
    return self.allocPages(num_pages);
}

fn free(self_opaque: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) ?[*]u8 {
    const self: *PageAllocator = @ptrCast(@alignCast(self_opaque));
    const num_pages = std.mem.alignForward(usize, memory.len, mem.page_size)/mem.page_size;
    self.freePages(@ptrFromInt(memory.ptr), num_pages);
}

pub fn allocator(self: *PageAllocator) Allocator {
    return .{
        .ptr = @ptrCast(self),
        .vtable = &.{
            .alloc = alloc,
            .resize = Allocator.noResize,
            .remap = Allocator.noRemap,
            .free = Allocator.noFree,
        }
    };
}
