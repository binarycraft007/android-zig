file: std.fs.File,
header: Header,

pub const boot_magic = "ANDROID!";
pub const boot_magic_size = 8;
pub const boot_name_size = 16;
pub const boot_args_size = 512;
pub const boot_extra_args_size = 1024;
pub const boot_image_header_v3_pagesize = 4096;
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

// When a boot header is of version 0, the structure of
// boot image is as follows:
//
// +-----------------+
// | boot header     | 1 page
// +-----------------+
// | kernel          | n pages
// +-----------------+
// | ramdisk         | m pages
// +-----------------+
// | second stage    | o pages
// +-----------------+
//
// n = (kernel_size + page_size - 1) / page_size
// m = (ramdisk_size + page_size - 1) / page_size
// o = (second_size + page_size - 1) / page_size
//
// 0. all entities are page_size aligned in flash
// 1. kernel and ramdisk are required (size != 0)
// 2. second is optional (second_size == 0 -> no second)
// 3. load each element (kernel, ramdisk, second) at
//    the specified physical address (kernel_addr, etc)
// 4. prepare tags at tag_addr.  kernel_args[] is
//    appended to the kernel commandline in the tags.
// 5. r0 = 0, r1 = MACHINE_TYPE, r2 = tags_addr
// 6. if second_size != 0: jump to second_addr
//    else: jump to kernel_addr

pub const HeaderVersion = enum {
    v0,
    v1,
    v2,
    v3,
    v4,
};

pub const Header = union(HeaderVersion) {
    v0: extern struct {
        // Must be BOOT_MAGIC.
        magic: [boot_magic_size]u8 align(1),
        kernel_size: u32 align(1), // size in bytes
        kernel_addr: u32 align(1), // physical load addr
        ramdisk_size: u32 align(1), // size in bytes
        ramdisk_addr: u32 align(1), // physical load addr
        second_size: u32 align(1), // size in bytes
        second_addr: u32 align(1), // physical load addr
        tags_addr: u32 align(1), // physical addr for kernel tags (if required)
        page_size: u32 align(1), // flash page size we assume
        // Version of the boot image header.
        header_version: u32 align(1),
        // Operating system version and security patch level.
        // For version "A.B.C" and patch level "Y-M-D":
        //   (7 bits for each of A, B, C; 7 bits for (Y-2000), 4 bits for M)
        //   os_version = A[31:25] B[24:18] C[17:11] (Y-2000)[10:4] M[3:0]
        os_version: u32 align(1),
        name: [boot_name_size]u8 align(1), // asciiz product name
        cmdline: [boot_args_size]u8 align(1), // asciiz kernel commandline
        id: [8]u32 align(1), // timestamp / checksum / sha1 / etc
        // Supplemental command line data; kept here to maintain
        // binary compatibility with older versions of mkbootimg.
        // Asciiz.
        extra_cmdline: [boot_extra_args_size]u8 align(1),
    },
    v1: extern struct {
        // Must be BOOT_MAGIC.
        magic: [boot_magic_size]u8 align(1),
        kernel_size: u32 align(1), // size in bytes
        kernel_addr: u32 align(1), // physical load addr
        ramdisk_size: u32 align(1), // size in bytes
        ramdisk_addr: u32 align(1), // physical load addr
        second_size: u32 align(1), // size in bytes
        second_addr: u32 align(1), // physical load addr
        tags_addr: u32 align(1), // physical addr for kernel tags (if required)
        page_size: u32 align(1), // flash page size we assume
        // Version of the boot image header.
        header_version: u32 align(1),
        // Operating system version and security patch level.
        // For version "A.B.C" and patch level "Y-M-D":
        //   (7 bits for each of A, B, C; 7 bits for (Y-2000), 4 bits for M)
        //   os_version = A[31:25] B[24:18] C[17:11] (Y-2000)[10:4] M[3:0]
        os_version: u32 align(1),
        name: [boot_name_size]u8 align(1), // asciiz product name
        cmdline: [boot_args_size]u8 align(1), // asciiz kernel commandline
        id: [8]u32 align(1), // timestamp / checksum / sha1 / etc
        // Supplemental command line data; kept here to maintain
        // binary compatibility with older versions of mkbootimg.
        // Asciiz.
        extra_cmdline: [boot_extra_args_size]u8 align(1),
        recovery_dtbo_size: u32 align(1), // size in bytes for recovery DTBO/ACPIO image
        recovery_dtbo_offset: u64 align(1), // offset to recovery dtbo/acpio in boot image
        header_size: u32 align(1),
    },
    v2: extern struct {
        // Must be BOOT_MAGIC.
        magic: [boot_magic_size]u8 align(1),
        kernel_size: u32 align(1), // size in bytes
        kernel_addr: u32 align(1), // physical load addr
        ramdisk_size: u32 align(1), // size in bytes
        ramdisk_addr: u32 align(1), // physical load addr
        second_size: u32 align(1), // size in bytes
        second_addr: u32 align(1), // physical load addr
        tags_addr: u32 align(1), // physical addr for kernel tags (if required)
        page_size: u32 align(1), // flash page size we assume
        // Version of the boot image header.
        header_version: u32 align(1),
        // Operating system version and security patch level.
        // For version "A.B.C" and patch level "Y-M-D":
        //   (7 bits for each of A, B, C; 7 bits for (Y-2000), 4 bits for M)
        //   os_version = A[31:25] B[24:18] C[17:11] (Y-2000)[10:4] M[3:0]
        os_version: u32 align(1),
        name: [boot_name_size]u8 align(1), // asciiz product name
        cmdline: [boot_args_size]u8 align(1), // asciiz kernel commandline
        id: [8]u32 align(1), // timestamp / checksum / sha1 / etc
        // Supplemental command line data; kept here to maintain
        // binary compatibility with older versions of mkbootimg.
        // Asciiz.
        extra_cmdline: [boot_extra_args_size]u8 align(1),
        recovery_dtbo_size: u32 align(1), // size in bytes for recovery DTBO/ACPIO image
        recovery_dtbo_offset: u64 align(1), // offset to recovery dtbo/acpio in boot image
        header_size: u32 align(1),
        dtb_size: u32 align(1), // size in bytes for DTB image
        dtb_addr: u64 align(1), // physical load address for DTB image
    },
    v3: extern struct {
        // Must be BOOT_MAGIC.
        magic: [boot_magic_size]u8 align(1),
        kernel_size: u32 align(1), // size in bytes */
        ramdisk_size: u32 align(1), // size in bytes */
        // Operating system version and security patch level.
        // For version "A.B.C" and patch level "Y-M-D":
        //   (7 bits for each of A, B, C; 7 bits for (Y-2000), 4 bits for M)
        //   os_version = A[31:25] B[24:18] C[17:11] (Y-2000)[10:4] M[3:0]
        os_version: u32 align(1),
        header_size: u32 align(1),
        reserved: [4]u32 align(1),
        // Version of the boot image header.
        header_version: u32 align(1),
        // Asciiz kernel commandline.
        cmdline: [boot_args_size + boot_extra_args_size]u8 align(1),
    },
    v4: extern struct {
        // Must be BOOT_MAGIC.
        magic: [boot_magic_size]u8 align(1),
        kernel_size: u32 align(1), // size in bytes */
        ramdisk_size: u32 align(1), // size in bytes */
        // Operating system version and security patch level.
        // For version "A.B.C" and patch level "Y-M-D":
        //   (7 bits for each of A, B, C; 7 bits for (Y-2000), 4 bits for M)
        //   os_version = A[31:25] B[24:18] C[17:11] (Y-2000)[10:4] M[3:0]
        os_version: u32 align(1),
        header_size: u32 align(1),
        reserved: [4]u32 align(1),
        // Version of the boot image header.
        header_version: u32 align(1),
        // Asciiz kernel commandline.
        cmdline: [boot_args_size + boot_extra_args_size]u8 align(1),
        signature_size: u32 align(1), // size in bytes
    },

    pub const SetOsVersionOptions = struct {
        major: u32,
        minor: u32,
        patch: u32,
    };

    pub fn setOsVersion(self: *Header, options: SetOsVersionOptions) void {
        switch (self.*) {
            inline else => |*value| {
                value.os_version &= ((1 << 11) - 1);
                value.os_version |= ((options.major & 0x7f) << 25) |
                    ((options.minor & 0x7f) << 18) |
                    ((options.patch & 0x7f) << 11);
            },
        }
    }

    pub const SetOsPatchLevelOptions = struct {
        year: u32,
        month: u32,
    };

    pub fn setOsPatchLevel(self: *Header, options: SetOsPatchLevelOptions) void {
        switch (self.*) {
            inline else => |*value| {
                value.os_version &= ~((1 << 11) - 1);
                value.os_version |= (((options.year - 2000) & 0x7f) << 4) |
                    ((options.month & 0xf) << 0);
            },
        }
    }
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
            .v0 => {
                image = .{ .file = file, .header = .{ .v0 = undefined } };
            },
            .v1 => {
                image = .{ .file = file, .header = .{ .v1 = undefined } };
            },
            .v2 => {
                image = .{ .file = file, .header = .{ .v2 = undefined } };
            },
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

fn unpackBootImage(self: *BootImage) !void {
    switch (self.header) {
        inline else => |*value, tag| {
            const T = std.meta.TagPayload(Header, tag);
            try self.file.seekTo(0);
            value.* = try self.reader().readStruct(T);
        },
    }
}

test {
    var image: BootImage = undefined;
    image = try BootImage.unpack("testdata/boot.img");
    switch (image.header) {
        inline else => |value| {
            try testing.expectEqualSlices(u8, &value.magic, boot_magic);
        },
    }
}

const std = @import("std");
const io = std.io;
const os = std.os;
const mem = std.mem;
const testing = std.testing;
const BootImage = @This();
