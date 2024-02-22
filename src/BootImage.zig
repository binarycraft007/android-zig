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

pub const boot_magic = "ANDROID!";
pub const boot_magic_size = 8;
pub const boot_name_size = 16;
pub const boot_args_size = 512;
pub const boot_extra_args_size = 1024;
pub const pagesize = 4096;
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

pub const HeaderBase = extern struct {
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
};

pub const Header = extern struct {
    base: HeaderBase,
    signature_size: u32 align(1) = 0,

    pub const PageNumberKind = enum {
        header,
        kernel,
        ramdisk,
    };

    pub fn version(self: Header) HeaderVersion {
        return @enumFromInt(self.base.header_version);
    }

    pub fn pageNumber(self: Header, kind: PageNumberKind) usize {
        const image_size = switch (kind) {
            .header => return 1,
            .kernel => self.base.kernel_size,
            .ramdisk => self.base.ramdisk_size,
        };
        return (image_size + pagesize - 1) / pagesize;
    }
};

pub const VerifiedBoot = struct {
    footer: Footer = .{},
    meta: MetaImageHeader = .{},
    payload: [pagesize]u8 = [1]u8{0} ** pagesize,

    pub fn vbmeta(self: VerifiedBoot) Footer.VbMeta {
        return self.footer.vbmeta();
    }

    pub fn read(stream: anytype) !VerifiedBoot {
        var vb: VerifiedBoot = .{};
        if (std.meta.hasMethod(@TypeOf(stream), "seekFromEnd")) {
            try stream.seekFromEnd(-(@sizeOf(Footer)));
        } else {
            const end = try stream.seekableStream.getEndPos();
            try stream.seekableStream.seekTo(end - @sizeOf(Footer));
        }
        vb.footer = try Footer.read(stream.reader());
        if (vb.footer.check()) {
            const meta_size = vb.vbmeta().size;
            const meta_offset = vb.vbmeta().offset;
            if (std.meta.hasMethod(@TypeOf(stream), "seekTo")) {
                try stream.seekTo(meta_offset);
            } else {
                try stream.seekableStream.seekTo(meta_offset);
            }
            vb.meta = try MetaImageHeader.read(stream.reader());
            if (vb.meta.check()) {
                const size = meta_size - @sizeOf(MetaImageHeader);
                _ = try stream.reader().readAll(vb.payload[0..size]);
                return vb;
            }
            return error.NoMetaImageHeader;
        }
        return error.NoFooter;
    }

    pub fn writeMeta(self: VerifiedBoot, writer: anytype) !void {
        try writer.writeStruct(self.meta);
        const size = self.vbmeta().size - @sizeOf(MetaImageHeader);
        try writer.writeAll(self.payload[0..size]);
    }

    pub fn writeFooter(self: VerifiedBoot, writer: anytype) !void {
        const footer_start = pagesize - @sizeOf(Footer);
        var buffer: [pagesize]u8 = [1]u8{0} ** pagesize;
        @memcpy(buffer[footer_start..], mem.asBytes(&self.footer));
        try writer.writeAll(&buffer);
    }

    pub const Footer = extern struct {
        pub const magic = "AVBf";

        magic: [magic.len]u8 align(1) = [1]u8{0} ** magic.len,
        version_major: u32 align(1) = 0,
        version_minor: u32 align(1) = 0,
        original_image_size: u64 align(1) = 0,
        vbmeta_offset: u64 align(1) = 0,
        vbmeta_size: u64 align(1) = 0,
        reserved: [28]u8 align(1) = [1]u8{0} ** 28,

        pub fn read(reader: anytype) !Footer {
            return try reader.readStruct(Footer);
        }

        pub fn check(self: Footer) bool {
            return mem.eql(u8, &self.magic, Footer.magic);
        }

        pub const VbMeta = struct {
            offset: usize,
            size: usize,
        };

        pub fn vbmeta(self: Footer) VbMeta {
            return .{
                .offset = @byteSwap(self.vbmeta_offset),
                .size = @byteSwap(self.vbmeta_size),
            };
        }

        pub fn metaOffset(self: Footer) usize {
            return @byteSwap(self.vbmeta_offset);
        }

        pub fn originalImageSize(self: Footer) usize {
            return @byteSwap(self.original_image_size);
        }

        pub const PatchOptions = struct {
            original_image_size: u64,
            vbmeta_offset: u64,
        };

        pub fn patch(self: *Footer, options: PatchOptions) void {
            self.setOriginalImageSize(options.original_image_size);
            self.setMetaOffset(options.vbmeta_offset);
        }

        pub fn setMetaOffset(self: *Footer, offset: usize) void {
            self.vbmeta_offset = @byteSwap(offset);
        }

        pub fn setOriginalImageSize(self: *Footer, size: usize) void {
            self.original_image_size = @byteSwap(size);
        }
    };

    pub const MetaImageHeader = extern struct {
        pub const magic = "AVB0";
        pub const release_size = 48;

        magic: [magic.len]u8 align(1) = [1]u8{0} ** magic.len,
        required_libavb_version_major: u32 align(1) = 0,
        required_libavb_version_minor: u32 align(1) = 0,
        authentication_data_block_size: u64 align(1) = 0,
        auxiliary_data_block_size: u64 align(1) = 0,
        algorithm_type: u32 align(1) = 0,
        hash_offset: u64 align(1) = 0,
        hash_size: u64 align(1) = 0,
        signature_offset: u64 align(1) = 0,
        signature_size: u64 align(1) = 0,
        public_key_offset: u64 align(1) = 0,
        public_key_size: u64 align(1) = 0,
        public_key_metadata_offset: u64 align(1) = 0,
        public_key_metadata_size: u64 align(1) = 0,
        descriptors_offset: u64 align(1) = 0,
        descriptors_size: u64 align(1) = 0,
        rollback_index: u64 align(1) = 0,
        flags: u32 align(1) = 0,
        rollback_index_location: u32 align(1) = 0,
        release_string: [release_size]u8 align(1) = [1]u8{0} ** release_size,
        reserved: [80]u8 align(1) = [1]u8{0} ** 80,

        pub fn read(reader: anytype) !MetaImageHeader {
            return try reader.readStruct(MetaImageHeader);
        }

        pub fn check(self: MetaImageHeader) bool {
            return mem.eql(u8, &self.magic, MetaImageHeader.magic);
        }
    };
};

pub fn unpack(path: []const u8) !BootImage {
    var image: BootImage = undefined;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const metadata = try file.metadata();
    const header = try file.reader().readBytesNoEof(pagesize);
    var stream = std.io.fixedBufferStream(&header);
    const kind_raw = try stream.reader().readBytesNoEof(8);
    if (std.mem.eql(u8, &kind_raw, boot_magic)) {
        try stream.reader().skipBytes(8 * 4, .{});
        const header_version_raw = try stream.reader().readBytesNoEof(4);
        const header_version: u32 = @bitCast(header_version_raw);
        stream.reset();
        switch (@as(HeaderVersion, @enumFromInt(header_version))) {
            .v0, .v1, .v2 => return error.UnsupportedBootImageVersion,
            .v3 => {
                image = .{
                    .file = file,
                    .size = metadata.size(),
                    .header = .{
                        .base = try stream.reader().readStruct(HeaderBase),
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
            const field_name = field.name ++ "_size";
            if (@hasField(@TypeOf(self.header.base), field_name)) {
                @field(self.header.base, field_name) = @intCast(stat.size);
            } else if (@hasField(@TypeOf(self.header), field_name)) {
                @field(self.header, field_name) = @intCast(stat.size);
            }
        }
    }
    switch (self.header.version()) {
        .v3 => try file.writer().writeStruct(self.header.base),
        .v4 => try file.writer().writeStruct(self.header),
        else => unreachable,
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
    if (self.avb.footer.check() and self.avb.meta.check()) {
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
    var buffer: [pagesize]u8 = undefined;
    const pad = mem.alignForward(usize, pos, pagesize) - pos;
    @memset(buffer[0..pad], 0x0);
    try file.writer().writeAll(buffer[0..pad]);
}

fn padToOriginalSize(size: usize, file: std.fs.File, avb: bool) !void {
    try padFile(file);
    const pos = try file.getPos();
    const pages = (size - pos) / pagesize - @intFromBool(avb);
    var buffer: [pagesize]u8 = [1]u8{0} ** pagesize;
    try file.writer().writeBytesNTimes(&buffer, pages);
}

fn unpackBootImage(self: *BootImage) !void {
    const kernel_pages = self.header.pageNumber(.kernel);
    const ramdisk_pages = self.header.pageNumber(.ramdisk);
    self.image_infos.kernel = .{
        // The first page contains the boot header
        .offset = pagesize * 1,
        .size = self.header.base.kernel_size,
    };
    self.image_infos.ramdisk = .{
        .offset = pagesize * (1 + kernel_pages),
        .size = self.header.base.ramdisk_size,
    };
    if (self.header.signature_size > 0) {
        self.image_infos.signature = .{
            .offset = pagesize *
                (1 + kernel_pages + ramdisk_pages),
            .size = self.header.signature_size,
        };
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
    const avb = VerifiedBoot.read(self.file) catch |err| switch (err) {
        error.NoMetaImageHeader, error.NoFooter => return,
        else => |e| return e,
    };
    self.avb = avb;
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
