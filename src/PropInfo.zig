const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropAreaHeader = android.PropAreaHeader;
const PropInfoHeader = android.PropInfoHeader;
const PropTrieNode = @import("PropTrieNode.zig");
const PropInfo = @This();

const header_size = @sizeOf(PropInfoHeader);

header: *const PropInfoHeader,
offset: usize,
data: []const u8,

pub fn value(self: *const PropInfo) []const u8 {
    if (self.header.isLong()) {
        const offset = self.header.property.long_property.offset;
        const cstr = self.parseType([*c]const u8, offset);
        return mem.span(cstr);
    } else {
        return &self.header.property.value;
    }
}

pub fn name(self: *const PropInfo) []const u8 {
    const offset = self.offset + header_size;
    const cstr = self.parseType([*c]const u8, offset);
    return mem.span(cstr);
}

pub fn parseType(self: *const PropInfo, comptime T: type, off: usize) T {
    return @ptrCast(@alignCast(&self.data[off]));
}
