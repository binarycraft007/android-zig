const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropAreaHeader = android.PropAreaHeader;
const PropArea = @This();

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
