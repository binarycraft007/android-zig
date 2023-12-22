const std = @import("std");
const testing = std.testing;
pub const Property = @import("Property.zig");

test "basic add functionality" {
    const prop = try Property.init(.{ .path = "testdata/dev/__properties__" });
    _ = prop;
}
