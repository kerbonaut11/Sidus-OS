const std = @import("std");
pub var writer: *std.Io.Writer = undefined;

pub fn init(out: *std.Io.Writer) void {
    writer = out;
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    writer.print("{s}", .{message_level.asText()}) catch {};
    if (scope != .default) writer.print("@{s}", .{@tagName(scope)}) catch {};
    writer.print(": "++format++"\n", args) catch {};
    writer.flush() catch {};
}
