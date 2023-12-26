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
        .name = "ro.product.locale",
        .allocator = testing.allocator,
    });
    defer pi.deinit();
    try testing.expectEqualSlices(
        u8,
        "en-US",
        pi.value(), // long_value is supported
    );
}
