const std = @import("std");
const posix = std.os;
const fs = std.fs;
const mem = std.mem;
const android = @import("android.zig");
const PropArea = @import("PropArea.zig");
const ContextNode = @import("ContextNode.zig");
const InfoHeader = android.InfoHeader;
const InfoContext = @import("InfoContext.zig");
const Property = @This();

const prop_tree_file = "/dev/__properties__/property_info";

info: InfoContext,
path: []const u8,
allocator: mem.Allocator,

pub const InitOptions = struct {
    path: []const u8 = prop_tree_file,
    allocator: mem.Allocator,
};

pub fn init(options: InitOptions) !Property {
    var buf: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const tree = try std.fs.path.join(allocator, &.{
        options.path,
        "property_info",
    });
    const serial = try std.fs.path.join(allocator, &.{
        options.path,
        "properties_serial",
    });
    try posix.access(tree, posix.F_OK);
    const prop_area = try PropArea.init(serial, options.allocator);
    prop_area.deinit(options.allocator);
    return .{
        .path = options.path,
        .info = try InfoContext.init(options.allocator, tree),
        .allocator = options.allocator,
    };
}

pub const GetPropareaOptions = struct {
    name: []const u8,
    allocator: mem.Allocator,
};

pub fn getPropArea(self: *Property, options: GetPropareaOptions) !PropArea {
    const indexes = self.info.getPropInfoIndexes(options.name);
    const node = self.info.getContextNode(.{
        .dirname = self.path,
        .index = indexes.context_index,
    });
    return try node.propArea(options.allocator);
}

pub fn deinit(self: *Property) void {
    self.info.deinit(self.allocator);
}
