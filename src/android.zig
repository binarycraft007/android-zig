const std = @import("std");
const mem = std.mem;

/// The below structs intentionally do not end with char name[0] or other tricks to allocate
/// with a dynamic size, such that they can be added onto in the future without breaking
/// backwards compatibility.
pub const PropertyEntry = extern struct {
    name_offset: u32,
    namelen: u32,

    // This is the context match for this node_; ~0u if it doesn't correspond to any.
    context_index: u32,
    // This is the type for this node_; ~0u if it doesn't correspond to any.
    type_index: u32,
};

pub const TrieNodeInternal = extern struct {
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

pub const InfoHeader = extern struct {
    // The current version of this data as created by property service.
    current_version: u32,
    // The lowest version of libc that can properly parse this data.
    min_version: u32,
    size: u32,
    contexts_offset: u32,
    types_offset: u32,
    root_offset: u32,
};

pub const PropAreaHeader = extern struct {
    bytes_used: u32,
    serial: std.atomic.Value(u32),
    magic: u32,
    version: u32,
    reserved: [28]u32,

    pub const magic: u32 = 0x504f5250;
    pub const version: u32 = 0xfc6ed0ab;

    pub fn versionCheck(self: *const PropAreaHeader) !void {
        if (self.magic != PropAreaHeader.magic) return error.MaigcUnmatch;
        if (self.version != PropAreaHeader.version) return error.VersionUnmatch;
    }
};

pub const PropArea = struct {
    header: PropAreaHeader,
    raw: []const u8,

    const header_size = @sizeOf(PropAreaHeader);

    pub fn init(path: []const u8, gpa: mem.Allocator) !PropArea {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const meta = try file.metadata();
        if (meta.size() < header_size) return error.FileTooSmall;
        var raw = try file.readToEndAlloc(gpa, meta.size());
        errdefer gpa.free(raw);
        const header: PropAreaHeader = @bitCast(raw[0..header_size].*);
        try header.versionCheck();
        return .{ .header = header, .raw = raw };
    }

    pub fn data(self: *const PropArea) []const u8 {
        return self.raw[header_size..];
    }

    pub fn deinit(self: PropArea, gpa: mem.Allocator) void {
        gpa.free(self.raw);
    }
};

/// Properties are stored in a hybrid trie/binary tree structure.
/// Each property's name is delimited at '.' characters, and the tokens are put
/// into a trie structure.  Siblings at each level of the trie are stored in a
/// binary tree.  For instance, "ro.secure"="1" could be stored as follows:
///
/// +-----+   children    +----+   children    +--------+
/// |     |-------------->| ro |-------------->| secure |
/// +-----+               +----+               +--------+
///                       /    \                /   |
///                 left /      \ right   left /    |  prop   +===========+
///                     v        v            v     +-------->| ro.secure |
///                  +-----+   +-----+     +-----+            +-----------+
///                  | net |   | sys |     | com |            |     1     |
///                  +-----+   +-----+     +-----+            +===========+

// Represents a node in the trie.
pub const PropTrieNode = extern struct {
    namelen: u32,

    // The property trie is updated only by the init process (single threaded) which provides
    // property service. And it can be read by multiple threads at the same time.
    // As the property trie is not protected by locks, we use atomic_uint_least32_t types for the
    // left, right, children "pointers" in the trie node. To make sure readers who see the
    // change of "pointers" can also notice the change of prop_trie_node structure contents pointed by
    // the "pointers", we always use release-consume ordering pair when accessing these "pointers".

    // prop "points" to prop_info structure if there is a propery associated with the trie node.
    // Its situation is similar to the left, right, children "pointers". So we use
    // atomic_uint_least32_t and release-consume ordering to protect it as well.

    // We should also avoid rereading these fields redundantly, since not
    // all processor implementations ensure that multiple loads from the
    // same field are carried out in the right order.
    prop: std.atomic.Value(u32),

    left: std.atomic.Value(u32),
    right: std.atomic.Value(u32),

    children: std.atomic.Value(u32),

    name: [*]u8,
};
