const std = @import("std");
const testing = std.testing;
pub const Property = @import("Property.zig");

test "basic functionality" {
    var prop = try Property.init(.{
        .path = "testdata/dev/__properties__",
        .allocator = testing.allocator,
    });
    defer prop.deinit();
    const pa = try prop.getPropArea(.{
        .name = "ro.product.locale",
        .allocator = testing.allocator,
    });
    defer pa.deinit(testing.allocator);
    try testing.expectEqualSlices(
        u8,
        "DEVICE_PROVISIONED",
        pa.rootNode().getNode(.children).name(),
    );
}
