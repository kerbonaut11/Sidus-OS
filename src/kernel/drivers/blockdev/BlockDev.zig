pub const Error = error {};
const mem = @import("../../mem.zig");
const Inteface = @This();

pub const Buffer = []align(mem.page_size) [mem.page_size]u8;
pub const BufferConst = []const align(mem.page_size) [mem.page_size]u8;

block_size: u64,
vtable: struct {
    read:*const fn (self: *Inteface, start_block: u64, buffer: Buffer) Error!void,
    write: *const fn (self: *Inteface, start_block: u64, buffer: BufferConst) Error!void,
},

pub fn read(self: *Inteface, start_block: u64, buffer: Buffer) Error!void {
    return self.vtable.read(self, start_block, buffer);
}

pub fn write(self: *Inteface, start_block: u64, buffer: BufferConst) Error!void {
    return self.vtable.write(self, start_block, buffer);
}
