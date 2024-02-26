footer: Footer = .{},
meta: MetaImageHeader = .{},
payload: [page_size]u8 = [1]u8{0} ** page_size,

pub fn isValid(self: VerifiedBoot) bool {
    return self.footer.isValid() and self.meta.isValid();
}

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
    if (vb.footer.isValid()) {
        const meta_size = vb.vbmeta().size;
        const meta_offset = vb.vbmeta().offset;
        if (std.meta.hasMethod(@TypeOf(stream), "seekTo")) {
            try stream.seekTo(meta_offset);
        } else {
            try stream.seekableStream.seekTo(meta_offset);
        }
        vb.meta = try MetaImageHeader.read(stream.reader());
        if (vb.meta.isValid()) {
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
    const footer_start = page_size - @sizeOf(Footer);
    var buffer: [page_size]u8 = [1]u8{0} ** page_size;
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

    pub fn isValid(self: Footer) bool {
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

    pub fn isValid(self: MetaImageHeader) bool {
        return mem.eql(u8, &self.magic, MetaImageHeader.magic);
    }
};

const VerifiedBoot = @This();
const std = @import("std");
const mem = std.mem;
const page_size = @import("../BootImage.zig").page_size;
