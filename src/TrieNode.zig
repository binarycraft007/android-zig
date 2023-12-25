const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const InfoHeader = android.InfoHeader;
const PropertyEntry = android.PropertyEntry;
const TrieNodeInternal = android.TrieNodeInternal;
const InfoContext = @import("InfoContext.zig");
const TrieNode = @This();

serialized_data: *InfoContext,
trie_node_base: *TrieNodeInternal,

pub fn getName(self: *const TrieNode) []const u8 {
    const off = self.nodePropertyEntry().name_offset;
    const cstr = self.serialized_data.parseType([*c]const u8, off);
    return mem.span(cstr);
}

pub fn prefix(self: *const TrieNode, n: usize) *PropertyEntry {
    const offset = self.trie_node_base.prefix_entries;
    return self.parseType(*PropertyEntry, offset, n);
}

pub fn contextIndex(self: *const TrieNode) usize {
    return self.nodePropertyEntry().context_index;
}

pub fn typeIndex(self: *const TrieNode) usize {
    return self.nodePropertyEntry().type_index;
}

pub fn numOfChildNodes(self: *const TrieNode) usize {
    return self.trie_node_base.num_child_nodes;
}

pub fn numOfExtactMatches(self: *const TrieNode) usize {
    return self.trie_node_base.num_exact_matches;
}

pub fn numOfPrefixes(self: *const TrieNode) usize {
    return self.trie_node_base.num_prefixes;
}

pub fn extactMatch(self: *const TrieNode, n: usize) *PropertyEntry {
    const offset = self.trie_node_base.exact_match_entries;
    return self.parseType(*PropertyEntry, offset, n);
}

pub fn childNode(self: *const TrieNode, n: usize) TrieNode {
    const off = self.trie_node_base.child_nodes;
    const node = self.parseType(*TrieNodeInternal, off, n);
    return .{
        .serialized_data = self.serialized_data,
        .trie_node_base = node,
    };
}

/// Binary search the list of children nodes to find a TrieNode for
/// a given property piece. Used to traverse the Trie
/// in GetPropertyInfoIndexes().
pub fn getChild(self: *const TrieNode, name: []const u8) !TrieNode {
    const Context = struct {
        name: []const u8,
        node: *const TrieNode,
        const Self = @This();

        pub fn f(ctx: *const Self, offset: usize) std.math.Order {
            const child_name = ctx.node.childNode(offset).getName();
            return mem.order(u8, child_name, ctx.name);
        }
    };
    const index = try find(self.trie_node_base.num_child_nodes, Context, .{
        .name = name,
        .node = self,
    });
    return self.childNode(index);
}

pub fn nodePropertyEntry(self: *const TrieNode) *PropertyEntry {
    const index = self.trie_node_base.property_entry;
    return self.serialized_data.parseType(*PropertyEntry, index);
}

pub fn parseType(self: *const TrieNode, comptime T: type, off: usize, n: usize) T {
    const target_offset = self.serialized_data.parseType([*]u32, off)[n];
    return self.serialized_data.parseType(T, target_offset);
}

pub fn prefixName(self: *const TrieNode, n: usize) []const u8 {
    const offset = self.prefix(n).name_offset;
    const cstr = self.serialized_data.parseType([*c]const u8, offset);
    return mem.span(cstr);
}

pub fn extactMatchName(self: *const TrieNode, n: usize) []const u8 {
    const offset = self.extactMatch(n).name_offset;
    const cstr = self.serialized_data.parseType([*c]const u8, offset);
    return mem.span(cstr);
}

fn find(len: usize, comptime T: type, context: T) !usize {
    var bottom: usize = 0;
    var top: usize = len - 1;
    while (top >= bottom) {
        const search = (top + bottom) / 2;
        switch (context.f(search)) {
            .eq => return search,
            .lt => bottom = search + 1,
            .gt => top = search - 1,
        }
    }
    return error.NotFound;
}
