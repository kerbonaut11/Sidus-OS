const std = @import("std");
const uefi = std.os.uefi;
const File = uefi.protocol.File;

pub fn uefiStringLit(comptime str: []const u8) [:0]const u16 {
    comptime var out: []const u16 = &.{};
    inline for (str) |ch| out = out ++ &[1]u16{ch};
    out = out ++ &[1]u16{0};
    return @ptrCast(out);
}


pub fn readAll(file: *File, out: []u8) !void {
    if (try file.read(out) != out.len) {
        return uefi.Error.EndOfFile;
    }
}

pub fn readOne(file: *File, comptime T: type) !T {
    var val: T = undefined;
    try readAll(file, @ptrCast(&val));
    return val;
}
