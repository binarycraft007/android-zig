const std = @import("std");
const testing = std.testing;
pub const Property = @import("Property.zig");

test "basic functionality" {
    const path = "testdata/dev/__properties__";
    var prop = try Property.init(.{
        .path = path,
        .allocator = testing.allocator,
    });
    defer prop.deinit();
    const pa = prop.getPropArea("ro.product.locale");
    std.debug.print("{any}\n", .{pa});
}
