const std = @import("std");
const log = std.log;
const uefi = std.os.uefi;
const Writer = std.Io.Writer;

pub var stdout: Writer = .{
    .buffer = &.{},
    .vtable = &.{
        .drain = drain,
    },
};

pub fn logFn(
    comptime message_level: log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    stdout.print("{s}", .{message_level.asText()}) catch {};
    if (scope != .default) stdout.print("@{s}", .{@tagName(scope)}) catch {};
    stdout.print(": "++format++"\n", args) catch {};
    stdout.flush() catch {};
}

fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    var bytes_written = w.end;
    try outStr(w.buffer[0..w.end]);
    w.end = 0;

    for (data[0..data.len-1]) |str| {
        try outStr(str);
        bytes_written += str.len;
    }

    const splat_str = data[data.len-1];
    for (0..splat) |_| try outStr(splat_str);
    bytes_written += splat*splat_str.len;
    
    return bytes_written;
}

fn outStr(str: []const u8) Writer.Error!void {
    for (str) |ch| try outCh(ch);
}

fn outCh(ch: u8) Writer.Error!void {
    if (ch == '\n') {
        try outRaw('\n');
        try outRaw('\r');
    } else {
        try outRaw(ch);
    }
}

fn outRaw(byte: u8) Writer.Error!void {
    const out = uefi.system_table.con_out orelse return error.WriteFailed;
    if (!(out.outputString(&.{byte}) catch false)) return error.WriteFailed;
}

