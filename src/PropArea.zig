const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropAreaHeader = android.PropAreaHeader;
const PropTrieNodeHeader = android.PropTrieNodeHeader;
const PropTrieNode = @import("PropTrieNode.zig");
const PropArea = @This();

header: PropAreaHeader,
raw: []const u8,
allocator: mem.Allocator,

pub const header_size = @sizeOf(PropAreaHeader);

pub fn init(path: []const u8, gpa: mem.Allocator) !PropArea {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const meta = try file.metadata();
    if (meta.size() < header_size) return error.FileTooSmall;
    var raw = try file.readToEndAlloc(gpa, meta.size());
    errdefer gpa.free(raw);
    const header: PropAreaHeader = @bitCast(raw[0..header_size].*);
    try header.versionCheck();
    return .{ .header = header, .raw = raw, .allocator = gpa };
}

pub fn data(self: *const PropArea) []const u8 {
    return self.raw[header_size..];
}

pub fn dirtyBackupArea(self: *const PropArea) []const u8 {
    return self.data()[0..PropTrieNode.header_size];
}

pub fn parseType(self: *const PropArea, comptime T: type, off: usize) T {
    return @ptrCast(@alignCast(&self.data()[off]));
}

pub fn rootNode(self: *const PropArea) PropTrieNode {
    return .{
        .offset = 0,
        .prop_area = self.*,
        .header = self.parseType(*const PropTrieNodeHeader, 0),
    };
}

pub fn deinit(self: PropArea) void {
    self.allocator.free(self.raw);
}
