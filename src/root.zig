const std = @import("std");
const testing = std.testing;
pub const Property = @import("Property.zig");

test "basic functionality" {
    var prop = try Property.init(.{
        .path = "testdata/dev/__properties__",
        .allocator = testing.allocator,
    });
    defer prop.deinit();
    const pi = try prop.find(.{
        .name = "ro.build.version.sdk",
        .allocator = testing.allocator,
    });
    defer pi.deinit();
    try testing.expectEqualSlices(
        u8,
        "34",
        pi.value(), // long_value is supported
    );
}
