const std = @import("std");
var out: *std.Io.Writer = undefined;

pub fn init(out_writer: *std.Io.Writer) void {
    out = out_writer;
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    out.print("{s}", .{message_level.asText()}) catch {};
    if (scope != .default) out.print("@{s}", .{@tagName(scope)}) catch {};
    out.print(": "++format++"\n", args) catch {};
    out.flush() catch {};
}
