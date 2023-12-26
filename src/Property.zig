const std = @import("std");
const posix = std.os;
const fs = std.fs;
const mem = std.mem;
const android = @import("android.zig");
const PropArea = @import("PropArea.zig");
const PropInfo = @import("PropInfo.zig");
const ContextNode = @import("ContextNode.zig");
const InfoHeader = android.InfoHeader;
const InfoContext = @import("InfoContext.zig");
const PropTrieNode = @import("PropTrieNode.zig");
const Property = @This();

const prop_tree_root = "/dev/__properties__";

info: InfoContext,
path: []const u8,
allocator: mem.Allocator,

pub const InitOptions = struct {
    path: []const u8 = prop_tree_root,
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
    prop_area.deinit();
    return .{
        .path = options.path,
        .info = try InfoContext.init(options.allocator, tree),
        .allocator = options.allocator,
    };
}

pub fn getPropArea(self: *Property, options: FindOptions) !PropArea {
    const indexes = self.info.getPropInfoIndexes(options.name);
    const node = self.info.getContextNode(.{
        .dirname = self.path,
        .index = indexes.context_index,
    });
    return try node.propArea(options.allocator);
}

pub const FindOptions = struct {
    name: []const u8,
    allocator: mem.Allocator,
};

pub fn find(self: *Property, options: FindOptions) !PropInfo {
    const node = try self.getPropArea(options);
    const trie = node.rootNode();
    var remaining_name = options.name;
    var current: PropTrieNode = trie;
    while (true) {
        const sep = mem.indexOf(u8, remaining_name, ".");
        const want_subtree = sep != null;
        const substr_size = if (want_subtree) sep else remaining_name.len;
        const children_offset = current.header.children.load(.Monotonic);
        var root: PropTrieNode = undefined;
        if (children_offset != 0) root = current.getNode(.children);
        current = try root.find(remaining_name[0..substr_size.?]);
        if (!want_subtree) break;
        remaining_name = remaining_name[sep.? + 1 ..];
    }

    const prop_offset = current.header.prop.load(.Monotonic);
    if (prop_offset != 0) return current.toPropInfo(prop_offset);
    return error.NotFound;
}

pub fn deinit(self: *Property) void {
    self.info.deinit(self.allocator);
}
