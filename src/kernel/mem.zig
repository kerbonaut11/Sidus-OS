pub const paging = @import("mem/virt.zig");
pub const page_allocator = @import("mem/page_allocator.zig");

pub const page_size = paging.page_size;
pub const huge_page_size = paging.huge_page_size;
pub const physToVirt = paging.physToVirt;

pub const kib = 1024;
pub const mib = kib*1024;
pub const gib = mib*1024;
