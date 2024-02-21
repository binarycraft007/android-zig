file: std.fs.File,
size: usize,
header: Header,
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
        return (image_size + boot_image_pagesize - 1) / boot_image_pagesize;
    }
};

pub const avb_footer_magic = "AVBf";
pub const avb_magic = "AVB0";
pub const avb_footer_magic_len = 4;
pub const avb_magic_len = 4;
pub const avb_release_string_size = 48;

pub const AvbFooter = extern struct {
    magic: [avb_footer_magic_len]u8 align(1),
    version_major: u32 align(1),
    version_minor: u32 align(1),
    original_image_size: u32 align(1),
    vbmeta_offset: u32 align(1),
    vbmeta_size: u32 align(1),
    reserved: [28]u8 align(1),
};

pub const AvbVBMetaImageHeader = extern struct {
    magic: [avb_magic_len]u8 align(1),
    required_libavb_version_major: u32 align(1),
    required_libavb_version_minor: u32 align(1),
    authentication_data_block_size: u64 align(1),
    auxiliary_data_block_size: u64 align(1),
    algorithm_type: u32 align(1),
    hash_offset: u64 align(1),
    hash_size: u64 align(1),
    signature_offset: u64 align(1),
    signature_size: u64 align(1),
    public_key_offset: u64 align(1),
    public_key_size: u64 align(1),
    public_key_metadata_offset: u64 align(1),
    public_key_metadata_size: u64 align(1),
    descriptors_offset: u64 align(1),
    descriptors_size: u64 align(1),
    rollback_index: u64 align(1),
    flags: u32 align(1),
    rollback_index_location: u32 align(1),
    release_string: [avb_release_string_size]u8 align(1),
    reserved: [80]u8 align(1),
};

pub fn unpack(path: []const u8) !BootImage {
    var image: BootImage = undefined;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const metadata = try file.metadata();
    const header = try file.reader().readBytesNoEof(boot_image_pagesize);
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
}

fn padFile(file: std.fs.File) !void {
    const pos = try file.getPos();
    var buffer: [boot_image_pagesize]u8 = undefined;
    const pad = mem.alignForward(usize, pos, boot_image_pagesize) - pos;
    @memset(buffer[0..pad], 0x0);
    try file.writer().writeAll(buffer[0..pad]);
}

const PumpOptions = struct {
    src_reader: std.fs.File.Reader,
    dest_writer: std.fs.File.Writer,
    size: usize,
};

fn unpackBootImage(self: *BootImage) !void {
    const kernel_pages = self.header.pageNumber(.kernel);
    const ramdisk_pages = self.header.pageNumber(.ramdisk);
    self.image_infos.kernel = .{
        // The first page contains the boot header
        .offset = boot_image_pagesize * 1,
        .size = self.header.base.kernel_size,
    };
    self.image_infos.ramdisk = .{
        .offset = boot_image_pagesize * (1 + kernel_pages),
        .size = self.header.base.ramdisk_size,
    };
    if (self.header.signature_size > 0) {
        self.image_infos.signature = .{
            .offset = boot_image_pagesize *
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
