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
context_nodes: []ContextNode,
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
    var info_ctx = try InfoContext.init(options.allocator, tree);
    const context_nodes = try info_ctx.initContextNodes(.{
        .allocator = options.allocator,
        .dirname = options.path,
    });
    const prop_area = try PropArea.init(serial, options.allocator);
    prop_area.deinit(options.allocator);
    return .{
        .info = info_ctx,
        .allocator = options.allocator,
        .context_nodes = context_nodes,
    };
}

pub const GetPropareaOptions = struct {
    name: []const u8,
    allocator: mem.Allocator,
};

pub fn getPropArea(self: *Property, options: GetPropareaOptions) !PropArea {
    const indexes = self.info.getPropInfoIndexes(options.name);
    const node = self.context_nodes[indexes.context_index];
    return try node.propArea(options.allocator);
}

pub fn deinit(self: *Property) void {
    self.info.deinit(self.allocator);
    self.allocator.free(self.context_nodes);
}
