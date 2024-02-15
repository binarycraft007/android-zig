file: std.fs.File,
header: Header,
image_infos: ImageInfos = .{},

pub const ImageInfo = struct {
    offset: usize = 0,
    size: usize = 0,

    pub fn nextAligned(self: ImageInfo) usize {
        const page_size = boot_image_pagesize;
        return mem.alignForward(usize, self.offset + self.size, page_size);
    }
};

pub const ImageInfos = struct {
    kernel: ImageInfo = .{},
    ramdisk: ImageInfo = .{},
    signature: ImageInfo = .{},
};

pub const boot_magic = "ANDROID!";
pub const boot_magic_size = 8;
pub const boot_name_size = 16;
pub const boot_args_size = 512;
pub const boot_extra_args_size = 1024;
pub const boot_image_pagesize = 4096;
pub const vendor_boot_magic = "VNDRBOOT";
pub const vendor_boot_magic_size = 8;
pub const vendor_boot_args_size = 2048;
pub const vendor_boot_name_size = 16;
pub const vendor_ramdisk_type_none = 0;
pub const vendor_ramdisk_type_platform = 1;
pub const vendor_ramdisk_type_recovery = 2;
pub const vendor_ramdisk_type_dlkm = 3;
pub const vendor_ramdisk_name_size = 32;
pub const vendor_ramdisk_table_entry_board_id_size = 16;

pub const HeaderVersion = enum {
    v0,
    v1,
    v2,
    v3,
    v4,
};

pub const Header = union(HeaderVersion) {
    v0: extern struct { magic: [boot_magic_size]u8 align(1) },
    v1: extern struct { magic: [boot_magic_size]u8 align(1) },
    v2: extern struct { magic: [boot_magic_size]u8 align(1) },
    v3: extern struct {
        magic: [boot_magic_size]u8 align(1),
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
        cmdline: [boot_args_size + boot_extra_args_size]u8 align(1),
    },
    v4: extern struct {
        magic: [boot_magic_size]u8 align(1),
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
        cmdline: [boot_args_size + boot_extra_args_size]u8 align(1),
        signature_size: u32 align(1),
    },
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
    if (std.mem.eql(u8, &kind_raw, boot_magic)) {
        try file.reader().skipBytes(8 * 4, .{});
        const header_version_raw = try file.reader().readBytesNoEof(4);
        const header_version: u32 = @bitCast(header_version_raw);
        switch (@as(HeaderVersion, @enumFromInt(header_version))) {
            .v0, .v1, .v2 => return error.UnsupportedBootImageVersion,
            .v3 => {
                image = .{ .file = file, .header = .{ .v3 = undefined } };
            },
            .v4 => {
                image = .{ .file = file, .header = .{ .v4 = undefined } };
            },
        }
        try image.unpackBootImage();
    } else if (std.mem.eql(u8, &kind_raw, vendor_boot_magic)) {
        return error.VendorBootUnsupported;
    } else {
        return error.NotAndroidBootImage;
    }
    return image;
}

pub fn repack(self: *BootImage) !void {
    var file = try std.fs.cwd().createFile("new_boot.img", .{});
    defer file.close();
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            const stat = try std.fs.cwd().statFile(field.name);
            switch (self.header) {
                inline .v3, .v4 => |*value| {
                    const field_name = field.name ++ "_size";
                    if (@hasField(@TypeOf(value.*), field_name)) {
                        @field(value, field_name) = @intCast(stat.size);
                        try file.writer().writeStruct(value.*);
                    }
                },
                else => return error.UnsupportedBootImageVersion,
            }
        }
    }
    try padFile(file);
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            const img = try std.fs.cwd().openFile(field.name, .{});
            defer img.close();
            var pumper: Pumper = Pumper.init();
            try pumper.pump(img.reader(), file.writer());
            try padFile(file);
        }
    }
}

fn padFile(file: std.fs.File) !void {
    const pos = try file.getPos();
    const padding = boot_image_pagesize;
    var buffer: [boot_image_pagesize]u8 = undefined;
    const pad = (padding - (pos & (padding - 1))) & (padding - 1);
    @memset(buffer[0..pad], 'x');
    try file.writer().writeAll(buffer[0..pad]);
}

const PumpOptions = struct {
    src_reader: std.fs.File.Reader,
    dest_writer: std.fs.File.Writer,
    size: usize,
};

fn pump(pumper: *Pumper, options: PumpOptions) !void {
    std.debug.assert(pumper.buf.len > 0);
    const size = options.size;
    const src_reader = options.src_reader;
    const dest_writer = options.dest_writer;
    var i: usize = 0;
    while (i != size) {
        if (pumper.writableLength() > 0) {
            const len = blk: {
                if ((size - i) < pumper.writableLength()) {
                    break :blk pumper.writableLength() - (size - i);
                }
                break :blk 0;
            };
            const n = try src_reader.read(pumper.writableSlice(len));
            if (n == 0) break; // EOF
            i += n;
            pumper.update(n);
        }
        pumper.discard(try dest_writer.write(pumper.readableSlice(0)));
    }
    // flush remaining data
    while (pumper.readableLength() > 0) {
        pumper.discard(try dest_writer.write(pumper.readableSlice(0)));
    }
}

fn unpackBootImage(self: *BootImage) !void {
    switch (self.header) {
        inline .v3, .v4 => |*value, tag| {
            const T = std.meta.TagPayload(Header, tag);
            try self.file.seekTo(0);
            value.* = try self.reader().readStruct(T);
            self.image_infos.kernel = .{
                // The first page contains the boot header
                .offset = boot_image_pagesize * 1,
                .size = value.kernel_size,
            };
            self.image_infos.ramdisk = .{
                .offset = self.image_infos.kernel.nextAligned(),
                .size = value.ramdisk_size,
            };
            if (@hasField(T, "signature_size")) {
                self.image_infos.signature = .{
                    .offset = self.image_infos.ramdisk.nextAligned(),
                    .size = value.signature_size,
                };
            }
        },
        else => return error.UnsupportedBootImageVersion,
    }
    inline for (@typeInfo(ImageInfos).Struct.fields) |field| {
        const image_info = @field(self.image_infos, field.name);
        if (image_info.offset != 0 and image_info.size != 0) {
            try self.file.seekTo(image_info.offset);
            var file = try std.fs.cwd().createFile(field.name, .{});
            defer file.close();
            var pumper: Pumper = Pumper.init();
            try pump(&pumper, .{
                .src_reader = self.file.reader(),
                .dest_writer = file.writer(),
                .size = image_info.size,
            });
        }
    }
}

test {
    var image: BootImage = undefined;
    image = try BootImage.unpack("testdata/boot.img");
    try image.repack();
}

const std = @import("std");
const io = std.io;
const os = std.os;
const mem = std.mem;
const testing = std.testing;
const BootImage = @This();
const Pumper = std.fifo.LinearFifo(u8, .{ .Static = 4096 });
