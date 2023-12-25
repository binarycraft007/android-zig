const std = @import("std");
const mem = std.mem;
const android = @import("android.zig");
const PropArea = android.PropArea;
const ContextNode = @This();

context: []const u8,
dirname: []const u8,

pub fn propArea(self: *const ContextNode, gpa: mem.Allocator) !PropArea {
    var buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const path = try std.fs.path.join(allocator, &.{
        self.dirname,
        self.context,
    });
    return try PropArea.init(path, gpa);
}
