const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropAreaHeader = android.PropAreaHeader;
const PropTrieNodeHeader = android.PropTrieNodeHeader;
const PropTrieNode = @This();

offset: usize,
header: *const PropTrieNodeHeader,
data: []const u8,

pub const header_size = @sizeOf(PropTrieNodeHeader);

pub const Member = enum {
    left,
    right,
    children,
};

pub fn getNode(self: *const PropTrieNode, comptime member: Member) PropTrieNode {
    const off = @field(self.header, @tagName(member)).load(.SeqCst);
    return .{
        .offset = off,
        .data = self.data,
        .header = self.parseType(*const PropTrieNodeHeader, off),
    };
}

pub fn name(self: *const PropTrieNode) []const u8 {
    const ptr = self.parseType([*]const u8, self.offset + header_size);
    return ptr[0..self.header.namelen];
}

pub fn parseType(self: *const PropTrieNode, comptime T: type, off: usize) T {
    return @ptrCast(@alignCast(&self.data[off]));
}
