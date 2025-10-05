const std = @import("std");

pub fn main() !void {
    std.debug.print("Frontier Zig demo bootstrap\n", .{});
}

test "builtin sanity" {
    try std.testing.expectEqual(@as(u8, 1), 1);
}
