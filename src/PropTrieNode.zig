const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropAreaHeader = android.PropAreaHeader;
const PropTrieNodeHeader = android.PropTrieNodeHeader;
const PropInfoHeader = android.PropInfoHeader;
const PropInfo = @import("PropInfo.zig");
const PropArea = @import("PropArea.zig");
const PropTrieNode = @This();

offset: usize,
header: *const PropTrieNodeHeader,
prop_area: PropArea,

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
        .prop_area = self.prop_area,
        .header = self.prop_area.parseType(*const PropTrieNodeHeader, off),
    };
}

pub fn name(self: *const PropTrieNode) []const u8 {
    const ptr = self.prop_area.parseType([*]const u8, self.offset + header_size);
    return ptr[0..self.header.namelen];
}

pub fn find(self: PropTrieNode, name_in: []const u8) !PropTrieNode {
    var current: PropTrieNode = self;
    while (true) {
        switch (comparePropName(name_in, current.name())) {
            .eq => return current,
            .lt => {
                const left_offset = current.header.left.load(.Monotonic);
                if (left_offset != 0) {
                    current = current.getNode(.left);
                } else {
                    break;
                }
            },
            .gt => {
                const right_offset = current.header.right.load(.Monotonic);
                if (right_offset != 0) {
                    current = current.getNode(.right);
                } else {
                    break;
                }
            },
        }
    }
    return error.NotFound;
}

fn comparePropName(name_in: []const u8, current: []const u8) std.math.Order {
    if (name_in.len < current.len) return .lt;
    if (name_in.len > current.len) return .gt;
    return mem.order(u8, name_in, current[0..name_in.len]);
}

pub fn toPropInfo(self: *const PropTrieNode, offset: usize) PropInfo {
    return .{
        .offset = offset,
        .prop_area = self.prop_area,
        .header = self.prop_area.parseType(*const PropInfoHeader, offset),
    };
}

pub fn parseType(self: *const PropTrieNode, comptime T: type, off: usize) T {
    return @ptrCast(@alignCast(&self.data[off]));
}
