pathname: []const u8,
load_bias: usize,
dlpi_phdr: *elf.Phdr,
dlpi_phnum: elf.Half,

next: *DynLib, // to next xdl obj for cache in xdl_addr()
linker_handle: Linker.DlOpenFn, // hold handle returned by xdl_linker_force_dlopen()

//
// (1) for searching symbols from .dynsym
//

dynsym_try_load: bool,
dynsym: *elf.Sym, // .dynsym
dynstr: []const u8, // .dynstr

// .hash (SYSV hash for .dynstr)
sysv_hash: struct {
    buckets: *const u32,
    buckets_cnt: u32,
    chains: *const u32,
    chains_cnt: u32,
},

// .gnu.hash (GNU hash for .dynstr)
gnu_hash: struct {
    buckets: *const u32,
    buckets_cnt: u32,
    chains: *const u32,
    symoffset: u32,
    bloom: *elf.Addr,
    bloom_cnt: u32,
    bloom_shift: u32,
},

//
// (2) for searching symbols from .symtab
//

symtab_try_load: bool,
base: usize,

symtab: []elf.Sym, // .symtab
symtab_cnt: usize,
strtab: [][]const u8, // .strtab
strtab_sz: usize,

pub const OpenFlags = enum {
    default,
    always_force,
    try_force,
};

pub fn open(path: []const u8, flags: OpenFlags) !DynLib {
    _ = path;
    switch (flags) {
        .default => {},
        .always_force => {},
        .try_force => {},
    }
}

pub fn close(self: *DynLib) void {
    _ = self;
}

const std = @import("std");
const elf = std.elf;
const DynLib = @This();
const Linker = @import("DynLib/Linker.zig");
