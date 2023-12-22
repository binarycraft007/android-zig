const std = @import("std");
const posix = std.os;
const fs = std.fs;
const mem = std.mem;
const Property = @This();

const prop_tree_file = "/dev/__properties__/property_info";

info: InfoContext,

pub const InfoContext = struct {
    raw: []align(mem.page_size) u8,
    header: InfoHeader,

    pub fn initContextNodes(self: *InfoContext) !void {
        _ = self;
    }

    pub fn numContexts(self: *InfoContext) usize {
        const context_offset = self.raw[self.header.contexts_offset];
        const context: [*]u32 = @ptrFromInt(context_offset);
        return @intCast(context[0]);
    }
};

pub const InitOptions = struct {
    path: [*:0]const u8,
    load_default: bool = false,
};

pub fn init(options: InitOptions) !Property {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    if (!isDir(options.path)) return error.Unsupported;
    const tree = try std.fs.path.join(allocator, &.{
        mem.span(options.path),
        "property_info",
    });
    const serial = try std.fs.path.join(allocator, &.{
        mem.span(options.path),
        "property_serial",
    });
    try posix.access(tree, posix.F_OK);
    var info_ctx: InfoContext = blk: {
        if (options.load_default) {
            break :blk try loadPath(prop_tree_file);
        } else {
            break :blk try loadPath(tree);
        }
    };
    try info_ctx.initContextNodes();
    mapSerialPropertyArea(serial);
    return .{ .info = info_ctx };
}

fn loadPath(path: []const u8) !InfoContext {
    const header_size = @sizeOf(InfoHeader);
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size < header_size) return error.FileTooSmall;
    var result = try posix.mmap(
        null,
        stat.size,
        posix.PROT.READ,
        posix.MAP.SHARED,
        file.handle,
        0,
    );
    errdefer posix.munmap(result);
    const header: InfoHeader = @bitCast(result[0..header_size].*);
    if (header.min_version > 1 or header.size != stat.size)
        return error.MapInfoAreaFailed;
    return .{ .raw = result, .header = header };
}

fn mapSerialPropertyArea(serial: []const u8) void {
    _ = serial;
}

fn isDir(path: [*:0]const u8) bool {
    var st = mem.zeroes(posix.system.Stat);
    if (posix.system.stat(path, &st) == -1)
        return false;
    const stat = fs.File.Stat.fromSystem(st);
    return switch (stat.kind) {
        .directory => true,
        else => false,
    };
}

const ContextNode = extern struct {
    padding: [12]u8,
};

/// The below structs intentionally do not end with char name[0] or other tricks to allocate
/// with a dynamic size, such that they can be added onto in the future without breaking
/// backwards compatibility.
const PropertyEntry = extern struct {
    name_offset: u32,
    namelen: u32,

    // This is the context match for this node_; ~0u if it doesn't correspond to any.
    context_index: u32,
    // This is the type for this node_; ~0u if it doesn't correspond to any.
    type_index: u32,
};

const TrieNodeInternal = extern struct {
    // This points to a property entry struct, which includes the name for this node
    property_entry: u32,

    // Children are a sorted list of child nodes_; binary search them.
    num_child_nodes: u32,
    child_nodes: u32,

    // Prefixes are terminating prefix matches at this node, sorted longest to smallest
    // Take the first match sequentially found with StartsWith().
    num_prefixes: u32,
    prefix_entries: u32,

    // Exact matches are a sorted list of exact matches at this node_; binary search them.
    num_exact_matches: u32,
    exact_match_entries: u32,
};

const InfoHeader = extern struct {
    // The current version of this data as created by property service.
    current_version: u32,
    // The lowest version of libc that can properly parse this data.
    min_version: u32,
    size: u32,
    contexts_offset: u32,
    types_offset: u32,
    root_offset: u32,
};
