const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const InfoHeader = android.InfoHeader;
const TrieNodeInternal = android.TrieNodeInternal;
const InfoContext = @This();
const TrieNode = @import("TrieNode.zig");
const ContextNode = @import("ContextNode.zig");

raw: []u8,
header: InfoHeader,

pub const EntryIndex = struct {
    // This is the context match for this node_; ~0u if it
    // doesn't correspond to any.
    context_index: usize = 0xFFFFFFFF,
    // This is the type for this node_; ~0u if it doesn't
    // correspond to any.
    type_index: usize = 0xFFFFFFFF,

    pub fn checkPrefixMatch(
        self: *EntryIndex,
        remaining_name: []const u8,
        trie_node: *const TrieNode,
    ) void {
        for (0..trie_node.numOfPrefixes()) |i| {
            const prefix_len = trie_node.prefix(i).namelen;
            if (prefix_len > remaining_name.len) continue;
            const name = trie_node.prefixName(i);
            if (mem.eql(u8, name[0..prefix_len], remaining_name[0..prefix_len])) {
                if (trie_node.prefix(i).context_index != 0xFFFFFFFF) {
                    self.context_index = trie_node.prefix(i).context_index;
                }
                if (trie_node.prefix(i).type_index != 0xFFFFFFFF) {
                    self.type_index = trie_node.prefix(i).type_index;
                }
                return;
            }
        }
    }
};

pub fn init(gpa: mem.Allocator, path: []const u8) !InfoContext {
    const header_size = @sizeOf(InfoHeader);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const meta = try file.metadata();
    if (meta.size() < header_size) return error.FileTooSmall;
    var raw = try file.readToEndAlloc(gpa, meta.size());
    errdefer gpa.free(raw);
    const header: InfoHeader = @bitCast(raw[0..header_size].*);
    if (header.min_version > 1) return error.Unsupported;
    return .{ .raw = raw, .header = header };
}

pub fn deinit(self: *InfoContext, gpa: mem.Allocator) void {
    gpa.free(self.raw);
}

pub const GetContextNodeOptions = struct {
    index: usize,
    dirname: []const u8,
};

pub fn getContextNode(self: *InfoContext, options: GetContextNodeOptions) ContextNode {
    const offset = self.header.contexts_offset + @sizeOf(u32);
    const context = self.parseType([*]u32, offset);
    const context_cstr = self.parseType([*c]const u8, context[options.index]);
    return .{
        .context = mem.span(context_cstr),
        .dirname = options.dirname,
    };
}

pub fn size(self: *InfoContext) usize {
    return self.header.size;
}

pub fn rootNode(self: *InfoContext) TrieNode {
    std.debug.assert(self.header.root_offset < self.header.size);
    return .{
        .serialized_data = self,
        .trie_node_base = self.parseType(*TrieNodeInternal, self.header.root_offset),
    };
}

pub fn getPropInfoIndexes(self: *InfoContext, name: []const u8) EntryIndex {
    var entry_indexes: EntryIndex = .{};
    var trie_node = self.rootNode();
    var remaining_name: []const u8 = name;
    var it = mem.split(u8, remaining_name, ".");
    while (it.next()) |name_const| {
        remaining_name = name_const;
        if (trie_node.contextIndex() != 0xFFFFFFFF) {
            entry_indexes.context_index = trie_node.contextIndex();
        }
        if (trie_node.typeIndex() != 0xFFFFFFFF) {
            entry_indexes.type_index = trie_node.typeIndex();
        }
        entry_indexes.checkPrefixMatch(name_const, &trie_node);
        const child = trie_node.getChild(name_const) catch break;
        trie_node = child;
    }
    for (0..trie_node.numOfExtactMatches()) |i| {
        const name_match = trie_node.extactMatchName(i);
        if (mem.eql(u8, name_match, remaining_name)) {
            if (trie_node.extactMatch(i).context_index != 0xFFFFFFFF) {
                entry_indexes.context_index = trie_node.extactMatch(i).context_index;
            }
            if (trie_node.extactMatch(i).type_index != 0xFFFFFFFF) {
                entry_indexes.type_index = trie_node.extactMatch(i).type_index;
            }
            return entry_indexes;
        }
    }
    entry_indexes.checkPrefixMatch(remaining_name, &trie_node);
    return entry_indexes;
}

pub fn numContexts(self: *InfoContext) usize {
    const offset = self.header.contexts_offset;
    const context = self.parseType([*]u32, offset);
    return @intCast(context[0]);
}

pub fn parseType(self: *InfoContext, comptime T: type, offset: usize) T {
    return @ptrCast(@alignCast(&self.raw[offset]));
}
