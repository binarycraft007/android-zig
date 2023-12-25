const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropArea = android.PropArea;
const ContextNode = @This();

context: []const u8,
dirname: []const u8,

pub fn propArea(self: *const ContextNode) !PropArea {
    var buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const path = try std.fs.path.join(allocator, &.{
        self.dirname,
        self.context,
    });
    const header_size = @sizeOf(PropArea);
    var header_buf: [header_size]u8 = undefined;
    std.debug.print("{s}\n", .{path});
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const read = try file.readAll(&header_buf);
    if (read != header_size) return error.ShortRead;
    const prop_area: PropArea = @bitCast(header_buf);
    try prop_area.versionCheck();
    return prop_area;
}
