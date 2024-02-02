const std = @import("std");
const mem = std.mem;
const android = @import("android");
const testing = std.testing;

fn getApiLevel(allocator: mem.Allocator) !android.ApiLevel {
    var prop = try android.Property.init(.{
        .path = "testdata",
        .allocator = allocator,
    });
    defer prop.deinit();
    const pi = try prop.find(.{
        .name = "ro.build.version.sdk",
        .allocator = allocator,
    });
    defer pi.deinit();
    const level = try std.fmt.parseInt(u16, pi.value(), 10);
    return @enumFromInt(level);
}

test "basic functionality" {
    const api_level = try getApiLevel(testing.allocator);
    try testing.expectEqual(api_level, .upside_down_cake);
}
