const std = @import("std");
const mem = std.mem;
const common = @import("common.zig");
const PropAreaHeader = common.PropAreaHeader;
const PropInfoHeader = common.PropInfoHeader;
const PropTrieNode = @import("PropTrieNode.zig");
const PropArea = @import("PropArea.zig");
const PropInfo = @This();

const header_size = @sizeOf(PropInfoHeader);

header: *const PropInfoHeader,
offset: usize,
prop_area: PropArea,

pub fn value(self: *const PropInfo) []const u8 {
    if (self.header.isLong()) {
        const offset = self.header.property.long_property.offset;
        const cstr = self.prop_area.parseType([*c]const u8, offset);
        return mem.span(cstr);
    } else {
        return mem.sliceTo(self.header.property.value[0..], 0x0);
    }
}

pub fn name(self: *const PropInfo) []const u8 {
    const offset = self.offset + header_size;
    const cstr = self.prop_area.parseType([*c]const u8, offset);
    return mem.span(cstr);
}

pub fn deinit(self: *const PropInfo) void {
    self.prop_area.deinit();
}
