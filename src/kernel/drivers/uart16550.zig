const std = @import("std");
const Writer = std.Io.Writer;
const io = @import("../io.zig");

const data_port = 0x03f8;

var buffer: [0]u8 = undefined;
var writer: Writer = .{
    .buffer = &buffer,
    .end = 0,
    .vtable = &.{
        .drain = &drain,
    }
};

pub fn init() *Writer {
    return &writer;
}

fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    var bytes_written = w.end;
    outStr(w.buffer[0..w.end]);
    w.end = 0;

    for (data[0..data.len-1]) |str| {
        outStr(str);
        bytes_written += str.len;
    }

    const splat_str = data[data.len-1];
    for (0..splat) |_| outStr(splat_str);
    bytes_written += splat*splat_str.len;
    
    return bytes_written;
}

fn outStr(str: []const u8) void {
    for (str) |ch| {
        if (ch == '\n') {
            outByte('\n');
            outByte('\r');
        } else {
            outByte(ch);
        }
    }
}

fn outByte(x: u8) void {
    io.outb(data_port, x);
}
