const mem = @import("mem.zig");
pub const Info = @import("BootInfo.zig"); 
pub var info: *Info = undefined;
pub const phys_mirror_start = mem.phys_mirror_start;
pub const phys_mirror_len = mem.phys_mirror_len;
