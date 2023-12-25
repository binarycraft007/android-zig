const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropArea = android.PropArea;
const PropTrieNode = android.PropTrieNode;
const SerialContext = @This();

raw: []u8, // do we need to store this or we just need header?
header: PropArea,

pub fn init(gpa: mem.Allocator, path: []const u8) !SerialContext {
    const header_size = @sizeOf(PropArea);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const meta = try file.metadata();
    if (meta.size() < header_size) return error.FileTooSmall;
    var raw = try file.readToEndAlloc(gpa, meta.size());
    errdefer gpa.free(raw);
    const header: PropArea = @bitCast(raw[0..header_size].*);
    try header.versionCheck(); // is header supported?
    return .{ .raw = raw, .header = header };
}

// TODO: move this to PropArea
// pub fn rootNode(self: *SerialContext) *PropTrieNode {
//     return self.toPropObj(*PropTrieNode, 0);
// }
//
// pub fn toPropObj(self: *SerialContext, comptime T: type, off: u32) T {
//     return @ptrCast(@alignCast(self.raw[off]));
// }

pub fn deinit(self: *SerialContext, gpa: mem.Allocator) void {
    gpa.free(self.raw);
}
