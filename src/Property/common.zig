const std = @import("std");
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
pub const PropTrieNodeHeader = extern struct {
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
};

pub const PropInfoHeader = extern struct {
    // Read only properties will not set anything but the bottom most bit of serial and the top byte.
    // We borrow the 2nd from the top byte for extra flags, and use the bottom most bit of that for
    // our first user, kLongFlag.
    pub const long_flag: u32 = 1 << 16;
    pub const prop_value_max: usize = 92;

    // The error message fits in part of a union with the previous 92 char property value so there
    // must be room left over after the error message for the offset to the new longer property value
    // and future expansion fields if needed. Note that this value cannot ever increase.  The offset
    // to the new longer property value appears immediately after it, so an increase of this size will
    // break compatibility.
    pub const long_error_buf_size: usize = 56;

    serial: std.atomic.Value(u32),
    // we need to keep this buffer around because the property
    // value can be modified whereas name is constant.
    property: extern union {
        value: [prop_value_max]u8,
        long_property: extern struct {
            error_message: [long_error_buf_size]u8,
            offset: u32,
        },
    },

    pub fn isLong(self: *const PropInfoHeader) bool {
        return self.serial.load(.Monotonic) & long_flag != 0;
    }
};
