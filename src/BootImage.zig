file: std.fs.File,
size: usize,
header: Header,
avb: VerifiedBoot = .{},
image_infos: ImageInfos = .{},

pub const ImageInfo = struct {
    offset: usize = 0,
    size: usize = 0,
};

pub const ImageInfos = struct {
    kernel: ImageInfo = .{},
    ramdisk: ImageInfo = .{},
    signature: ImageInfo = .{},
};

pub const magic = "ANDROID!";
pub const name_size = 16;
pub const args_size = 512;
pub const page_size = 4096;
pub const extra_args_size = 1024;

pub const VerifiedBoot = @import("BootImage/VerifiedBoot.zig");
pub const Header = extern struct {
    base: Base,
    signature_size: u32 align(1) = 0,

    pub const Base = extern struct {
        magic: [magic.len]u8 align(1),
        kernel_size: u32 align(1),
        ramdisk_size: u32 align(1),
        os_version: packed struct {
            month: u4,
            year: u7,
            patch: u7,
            minor: u7,
            major: u7,
        } align(1),
        header_size: u32 align(1),
        reserved: [4]u32 align(1),
        header_version: u32 align(1),
        cmdline: [args_size + extra_args_size]u8 align(1),
    };

    pub const Version = enum {
        v0,
        v1,
        v2,
        v3,
        v4,
    };

    pub const PageKind = enum {
        header,
        kernel,
        ramdisk,
    };

    pub fn version(self: Header) Version {
        return @enumFromInt(self.base.header_version);
    }

    pub fn pageNumber(self: Header, kind: PageKind) usize {
        const image_size = switch (kind) {
            .header => return 1,
            .kernel => self.base.kernel_size,
            .ramdisk => self.base.ramdisk_size,
        };
        return (image_size + page_size - 1) / page_size;
    }
};

pub fn unpack(path: []const u8) !BootImage {
    var image: BootImage = undefined;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const metadata = try file.metadata();
    const header = try file.reader().readBytesNoEof(page_size);
    var stream = std.io.fixedBufferStream(&header);
    const kind_raw = try stream.reader().readBytesNoEof(8);
    if (!std.mem.eql(u8, &kind_raw, magic)) return error.NotBootImage;
    try stream.reader().skipBytes(8 * 4, .{});
    const header_version_raw = try stream.reader().readBytesNoEof(4);
    const header_version: u32 = @bitCast(header_version_raw);
    stream.reset();
    switch (@as(Header.Version, @enumFromInt(header_version))) {
        .v3 => {
            image = .{
                .file = file,
                .size = metadata.size(),
                .header = .{
                    .base = try stream.reader().readStruct(Header.Base),
                },
            };
        },
        .v4 => {
            image = .{
                .file = file,
                .size = metadata.size(),
                .header = try stream.reader().readStruct(Header),
            };
        },
        else => |version| {
            std.log.err("unsupported image version: {}\n", .{version});
            return error.UnsupportedBootImageVersion;
        },
    }
    try image.unpackImpl();
    return image;
}

pub fn repack(self: *BootImage) !void {
    var file = try std.fs.cwd().createFile("new_boot.img", .{});
    defer file.close();
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            const stat = try std.fs.cwd().statFile(field.name);
            const field_name = field.name ++ "_size";
            if (@hasField(@TypeOf(self.header.base), field_name)) {
                @field(self.header.base, field_name) = @intCast(stat.size);
            } else if (@hasField(@TypeOf(self.header), field_name)) {
                @field(self.header, field_name) = @intCast(stat.size);
            } else {
                continue;
            }
            @field(self.image_infos, field.name).size = @intCast(stat.size);
        }
    }
    switch (self.header.version()) {
        .v3 => try file.writer().writeStruct(self.header.base),
        .v4 => try file.writer().writeStruct(self.header),
        else => |version| {
            std.log.err("unsupported image version: {}\n", .{version});
            return error.UnsupportedBootImageVersion;
        },
    }
    try padFile(file);
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            const img = try std.fs.cwd().openFile(field.name, .{});
            defer img.close();
            const pos = try file.getPos();
            _ = try img.copyRangeAll(0, file, pos, image_info.size);
            try file.seekBy(@intCast(image_info.size));
            try padFile(file);
        }
    }
    if (self.avb.isValid()) {
        const cur_pos = try file.getPos();
        self.avb.footer.patch(.{
            .original_image_size = cur_pos,
            .vbmeta_offset = cur_pos,
        });
        try self.avb.writeMeta(file.writer());
        try padToOriginalSize(self.size, file, true);
        try self.avb.writeFooter(file.writer());
    } else {
        try padToOriginalSize(self.size, file, false);
    }
}

fn padFile(file: std.fs.File) !void {
    const pos = try file.getPos();
    var buffer: [page_size]u8 = undefined;
    const pad = mem.alignForward(usize, pos, page_size) - pos;
    @memset(buffer[0..pad], 0x0);
    try file.writer().writeAll(buffer[0..pad]);
}

fn padToOriginalSize(size: usize, file: std.fs.File, avb: bool) !void {
    try padFile(file);
    const pos = try file.getPos();
    const pages = (size - pos) / page_size - @intFromBool(avb);
    var buffer: [page_size]u8 = [1]u8{0} ** page_size;
    try file.writer().writeBytesNTimes(&buffer, pages);
}

fn unpackImpl(self: *BootImage) !void {
    var num_pages: usize = page_size;
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        defer {
            if (std.meta.stringToEnum(Header.PageKind, field.name)) |kind| {
                num_pages += page_size * self.header.pageNumber(kind);
            }
        }
        const field_name = field.name ++ "_size";
        var size: usize = 0;
        if (@hasField(@TypeOf(self.header.base), field_name)) {
            size = @field(self.header.base, field_name);
        } else if (@hasField(@TypeOf(self.header), field_name)) {
            size = @field(self.header, field_name);
        } else {
            continue;
        }
        @field(self.image_infos, field.name).size = size;
        @field(self.image_infos, field.name).offset = num_pages;
    }
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            var file = try std.fs.cwd().createFile(field.name, .{});
            defer file.close();
            const offset = image_info.offset;
            const size = image_info.size;
            _ = try self.file.copyRangeAll(offset, file, 0, size);
        }
    }
    self.avb = VerifiedBoot.read(self.file) catch |err| switch (err) {
        error.NoMetaImageHeader, error.NoFooter => return,
        else => |e| return e,
    };
}

test {
    var image = try BootImage.unpack("testdata/boot.img");
    try image.repack();
}

const std = @import("std");
const io = std.io;
const os = std.os;
const mem = std.mem;
const testing = std.testing;
const BootImage = @This();
