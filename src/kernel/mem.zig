pub const virt = @import("mem/virt.zig");
pub const page_allocator = @import("mem/page_allocator.zig");

pub const page_size = virt.page_size;
pub const huge_page_size = virt.huge_page_size;
pub const physToVirt = virt.physToVirt;

pub const kib = 1024;
pub const mib = kib*1024;
pub const gib = mib*1024;
