const std = @import("std");
const mem = std.mem;
const testing = std.testing;
pub const ElfDynLib = @import("ElfDynLib.zig");
pub const BootImage = @import("BootImage.zig");
pub const Property = @import("Property.zig");

pub const ApiLevel = enum(u16) {
    gingerbread = 9,
    ice_cream_sandwich = 14,
    jellybean = 16,
    jellybean_mr1,
    jellybean_mr2,
    kitkat,
    lollipop = 21,
    lollipop_mr1,
    marshmallow,
    nougat,
    nougat_mr1,
    oreo,
    oreo_mr1,
    pie,
    quince_tart, // android 10
    red_velvet_cake, // android 11
    snowcone, // android 12
    tiramisu = 33, // android 13
    upside_down_cake, // android 14
};

pub fn getApiLevel(allocator: mem.Allocator) !ApiLevel {
    var prop = try Property.init(.{ .allocator = allocator });
    defer prop.deinit();
    const pi = try prop.find(.{
        .name = "ro.build.version.sdk",
        .allocator = allocator,
    });
    defer pi.deinit();
    const level = try std.fmt.parseInt(u16, pi.value(), 10);
    return @enumFromInt(level);
}
