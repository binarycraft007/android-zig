file: std.fs.File,
info: struct {
    kind: Kind,
    header_version: u32 = 0,
    kernel_size: u32 = 0,
    kernel_load_address: u32 = 0,
    ramdisk_size: u32 = 0,
    ramdisk_load_address: u32 = 0,
    second_size: u32 = 0,
    second_load_address: u32 = 0,
    tags_load_address: u32 = 0,
    page_size: u32 = 0,
    os_version: u32 = 0,
    os_patch_level: u32 = 0,
},

pub const Kind = enum {
    android,
    vendor,
};

pub const ReadError = os.ReadError;
pub const WriteError = os.WriteError;
pub const Reader = io.Reader(BootImage, ReadError, read);
pub const Writer = io.Writer(BootImage, WriteError, write);

pub fn reader(image: BootImage) Reader {
    return .{ .context = image };
}

pub fn read(self: BootImage, buffer: []u8) ReadError!usize {
    return self.file.read(buffer);
}

pub fn writer(image: BootImage) Writer {
    return .{ .context = image };
}

pub fn write(self: BootImage, buffer: []const u8) WriteError!usize {
    return self.file.write(buffer);
}

pub fn unpack(path: []const u8) !BootImage {
    var image: BootImage = undefined;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const kind_raw = try file.reader().readBytesNoEof(8);
    if (std.mem.eql(u8, &kind_raw, "ANDROID!")) {
        image = .{
            .file = file,
            .info = .{ .kind = .android },
        };
        try image.unpackBootImage();
    } else if (std.mem.eql(u8, &kind_raw, "VNDRBOOT")) {
        image = .{
            .file = file,
            .info = .{ .kind = .vendor },
        };
        try image.unpackVendorImage();
    } else {
        return error.NotAndroidBootImage;
    }
    return image;
}

fn unpackBootImage(self: *BootImage) !void {
    const buffer = try self.reader().readBytesNoEof(9 * 4);
    self.info.header_version = @bitCast(buffer[buffer.len - 4 ..].*);
    if (self.info.header_version < 3) {
        self.info.kernel_size = @bitCast(buffer[0..4].*);
        self.info.kernel_load_address = @bitCast(buffer[4..8].*);
        self.info.ramdisk_size = @bitCast(buffer[8..12].*);
        self.info.ramdisk_load_address = @bitCast(buffer[12..16].*);
    } else {
        self.info.kernel_size = @bitCast(buffer[0..4].*);
    }
}

fn unpackVendorImage(self: *BootImage) !void {
    _ = try self.reader().readBytesNoEof(4);
}

test {
    var image: BootImage = undefined;
    image = try BootImage.unpack("testdata/boot.img");
    try testing.expectEqual(image.info.kind, .android);

    image = try BootImage.unpack("testdata/vendor_boot.img");
    try testing.expectEqual(image.info.kind, .vendor);
}

const std = @import("std");
const io = std.io;
const os = std.os;
const testing = std.testing;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();
const BootImage = @This();
