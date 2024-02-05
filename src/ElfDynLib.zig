strings: [*:0]u8,
syms: [*]elf.Sym,
hashtab: HashTable,
versym: ?[*]u16,
verdef: ?*elf.Verdef,
memory: []align(mem.page_size) u8,

pub const HashTable = union(enum) {
    sysv: [*]os.Elf_Symndx,
    gnu: [*]os.Elf_Symndx,
};

pub const Error = error{
    FileTooBig,
    NotElfFile,
    NotDynamicLibrary,
    MissingDynamicLinkingInformation,
    ElfStringSectionNotFound,
    ElfSymSectionNotFound,
    ElfHashTableNotFound,
};

/// Trusts the file. Malicious file will be able to execute arbitrary code.
pub fn open(path: []const u8) !ElfDynLib {
    const fd = try os.open(path, 0, os.O.RDONLY | os.O.CLOEXEC);
    defer os.close(fd);

    const stat = try os.fstat(fd);
    const size = std.math.cast(usize, stat.size) orelse return error.FileTooBig;

    // This one is to read the ELF info. We do more mmapping later
    // corresponding to the actual LOAD sections.
    const file_bytes = try os.mmap(
        null,
        mem.alignForward(usize, size, mem.page_size),
        os.PROT.READ,
        os.MAP.PRIVATE,
        fd,
        0,
    );
    defer os.munmap(file_bytes);

    const eh = @as(*elf.Ehdr, @ptrCast(file_bytes.ptr));
    if (!mem.eql(u8, eh.e_ident[0..4], elf.MAGIC)) return error.NotElfFile;
    if (eh.e_type != elf.ET.DYN) return error.NotDynamicLibrary;

    const elf_addr = @intFromPtr(file_bytes.ptr);

    // Iterate over the program header entries to find out the
    // dynamic vector as well as the total size of the virtual memory.
    var maybe_dynv: ?[*]usize = null;
    var virt_addr_end: usize = 0;
    {
        var i: usize = 0;
        var ph_addr: usize = elf_addr + eh.e_phoff;
        while (i < eh.e_phnum) : ({
            i += 1;
            ph_addr += eh.e_phentsize;
        }) {
            const ph = @as(*elf.Phdr, @ptrFromInt(ph_addr));
            switch (ph.p_type) {
                elf.PT_LOAD => virt_addr_end = @max(virt_addr_end, ph.p_vaddr + ph.p_memsz),
                elf.PT_DYNAMIC => maybe_dynv = @as([*]usize, @ptrFromInt(elf_addr + ph.p_offset)),
                else => {},
            }
        }
    }
    const dynv = maybe_dynv orelse return error.MissingDynamicLinkingInformation;

    // Reserve the entire range (with no permissions) so that we can do MAP.FIXED below.
    const all_loaded_mem = try os.mmap(
        null,
        virt_addr_end,
        os.PROT.NONE,
        os.MAP.PRIVATE | os.MAP.ANONYMOUS,
        -1,
        0,
    );
    errdefer os.munmap(all_loaded_mem);

    const base = @intFromPtr(all_loaded_mem.ptr);

    // Now iterate again and actually load all the program sections.
    {
        var i: usize = 0;
        var ph_addr: usize = elf_addr + eh.e_phoff;
        while (i < eh.e_phnum) : ({
            i += 1;
            ph_addr += eh.e_phentsize;
        }) {
            const ph = @as(*elf.Phdr, @ptrFromInt(ph_addr));
            switch (ph.p_type) {
                elf.PT_LOAD => {
                    // The VirtAddr may not be page-aligned; in such case there will be
                    // extra nonsense mapped before/after the VirtAddr,MemSiz
                    const aligned_addr = (base + ph.p_vaddr) & ~(@as(usize, mem.page_size) - 1);
                    const extra_bytes = (base + ph.p_vaddr) - aligned_addr;
                    const extended_memsz = mem.alignForward(usize, ph.p_memsz + extra_bytes, mem.page_size);
                    const ptr = @as([*]align(mem.page_size) u8, @ptrFromInt(aligned_addr));
                    const prot = elfToMmapProt(ph.p_flags);
                    if ((ph.p_flags & elf.PF_W) == 0) {
                        // If it does not need write access, it can be mapped from the fd.
                        _ = try os.mmap(
                            ptr,
                            extended_memsz,
                            prot,
                            os.MAP.PRIVATE | os.MAP.FIXED,
                            fd,
                            ph.p_offset - extra_bytes,
                        );
                    } else {
                        const sect_mem = try os.mmap(
                            ptr,
                            extended_memsz,
                            prot,
                            os.MAP.PRIVATE | os.MAP.FIXED | os.MAP.ANONYMOUS,
                            -1,
                            0,
                        );
                        @memcpy(sect_mem[0..ph.p_filesz], file_bytes[0..ph.p_filesz]);
                    }
                },
                else => {},
            }
        }
    }

    var maybe_strings: ?[*:0]u8 = null;
    var maybe_syms: ?[*]elf.Sym = null;
    var maybe_hashtab: ?HashTable = null;
    var maybe_versym: ?[*]u16 = null;
    var maybe_verdef: ?*elf.Verdef = null;

    {
        var i: usize = 0;
        while (dynv[i] != 0) : (i += 2) {
            const p = base + dynv[i + 1];
            switch (dynv[i]) {
                elf.DT_STRTAB => maybe_strings = @as([*:0]u8, @ptrFromInt(p)),
                elf.DT_SYMTAB => maybe_syms = @as([*]elf.Sym, @ptrFromInt(p)),
                elf.DT_HASH => maybe_hashtab = .{ .sysv = @ptrFromInt(p) },
                elf.DT_GNU_HASH => maybe_hashtab = .{ .gnu = @ptrFromInt(p) },
                elf.DT_VERSYM => maybe_versym = @as([*]u16, @ptrFromInt(p)),
                elf.DT_VERDEF => maybe_verdef = @as(*elf.Verdef, @ptrFromInt(p)),
                else => {},
            }
        }
    }

    return ElfDynLib{
        .memory = all_loaded_mem,
        .strings = maybe_strings orelse return error.ElfStringSectionNotFound,
        .syms = maybe_syms orelse return error.ElfSymSectionNotFound,
        .hashtab = maybe_hashtab orelse return error.ElfHashTableNotFound,
        .versym = maybe_versym,
        .verdef = maybe_verdef,
    };
}

/// Trusts the file. Malicious file will be able to execute arbitrary code.
pub fn openZ(path_c: [*:0]const u8) !ElfDynLib {
    return open(mem.sliceTo(path_c, 0));
}

/// Trusts the file
pub fn close(self: *ElfDynLib) void {
    os.munmap(self.memory);
    self.* = undefined;
}

pub fn lookup(self: *ElfDynLib, comptime T: type, name: [:0]const u8) ?T {
    if (self.lookupAddress("", name)) |symbol| {
        return @as(T, @ptrFromInt(symbol));
    } else {
        return null;
    }
}

/// Returns the address of the symbol
pub fn lookupAddress(self: *const ElfDynLib, vername: []const u8, name: []const u8) ?usize {
    switch (self.hashtab) {
        .sysv => return self.lookupAddressSysv(vername, name),
        .gnu => return self.lookupAddressGnu(vername, name),
    }
}

pub fn lookupAddressSysv(self: *const ElfDynLib, vername: []const u8, name: []const u8) ?usize {
    const maybe_versym = if (self.verdef == null) null else self.versym;

    const OK_TYPES = (1 << elf.STT_NOTYPE | 1 << elf.STT_OBJECT | 1 << elf.STT_FUNC | 1 << elf.STT_COMMON);
    const OK_BINDS = (1 << elf.STB_GLOBAL | 1 << elf.STB_WEAK | 1 << elf.STB_GNU_UNIQUE);

    const hash = sysvHash(name);
    const nbucket = self.hashtab.sysv[0];
    const nchain = self.hashtab.sysv[1];
    const bucket: [*]u32 = @ptrCast(&self.hashtab.sysv[2]);
    const chain_ptr: [*]u32 = @ptrCast(&bucket[nbucket]);
    const chain: []u32 = chain_ptr[0..nchain];

    var i: usize = bucket[hash % nbucket];
    while (i > 0) : (i = chain[i]) {
        if (0 == (@as(u32, 1) << @as(u5, @intCast(self.syms[i].st_info & 0xf)) & OK_TYPES)) continue;
        if (0 == (@as(u32, 1) << @as(u5, @intCast(self.syms[i].st_info >> 4)) & OK_BINDS)) continue;
        if (0 == self.syms[i].st_shndx) continue;
        if (!mem.eql(u8, name, mem.sliceTo(self.strings + self.syms[i].st_name, 0))) continue;
        if (maybe_versym) |versym| {
            if (!checkver(self.verdef.?, versym[i], vername, self.strings))
                continue;
        }
        return @intFromPtr(self.memory.ptr) + self.syms[i].st_value;
    }

    return null;
}

pub fn lookupAddressGnu(self: *const ElfDynLib, vername: []const u8, name: []const u8) ?usize {
    _ = vername;

    const namehash = gnuHash(name);
    const nbuckets = self.hashtab.gnu[0];
    const symoffset = self.hashtab.gnu[1];
    const bloom_size = self.hashtab.gnu[2];
    const bloom_shift = self.hashtab.gnu[3];
    const bloom: [*]elf.Addr = @ptrCast(@alignCast(&self.hashtab.gnu[4]));
    const buckets: [*]u32 = @ptrCast(&bloom[bloom_size]);
    const chain: [*]u32 = @ptrCast(&buckets[nbuckets]);
    const elf_class_bits = @bitSizeOf(elf.Addr);

    const word = bloom[(namehash / elf_class_bits) % bloom_size];
    const mask = 0 |
        @as(elf.Addr, 1) << @intCast(namehash % elf_class_bits) |
        @as(elf.Addr, 1) << @intCast((namehash >> @intCast(bloom_shift)) % elf_class_bits);

    if ((word & mask) != mask) {
        return null;
    }

    var i: usize = buckets[namehash % nbuckets];
    if (i < symoffset) {
        return null;
    }

    var hash: u32 = 0;
    while ((hash & 1) == 0) : (i += 1) {
        const symname = mem.sliceTo(self.strings + self.syms[i].st_name, 0);
        hash = chain[i - symoffset];

        if ((namehash | 1) == (hash | 1) and mem.eql(u8, name, symname)) {
            return @intFromPtr(self.memory.ptr) + self.syms[i].st_value;
        }
    }

    return null;
}

fn elfToMmapProt(elf_prot: u64) u32 {
    var result: u32 = os.PROT.NONE;
    if ((elf_prot & elf.PF_R) != 0) result |= os.PROT.READ;
    if ((elf_prot & elf.PF_W) != 0) result |= os.PROT.WRITE;
    if ((elf_prot & elf.PF_X) != 0) result |= os.PROT.EXEC;
    return result;
}

fn checkver(def_arg: *elf.Verdef, vsym_arg: i32, vername: []const u8, strings: [*:0]u8) bool {
    var def = def_arg;
    const vsym = @as(u32, @bitCast(vsym_arg)) & 0x7fff;
    while (true) {
        if (0 == (def.vd_flags & elf.VER_FLG_BASE) and (def.vd_ndx & 0x7fff) == vsym)
            break;
        if (def.vd_next == 0)
            return false;
        def = @as(*elf.Verdef, @ptrFromInt(@intFromPtr(def) + def.vd_next));
    }
    const aux = @as(*elf.Verdaux, @ptrFromInt(@intFromPtr(def) + def.vd_aux));
    return mem.eql(u8, vername, mem.sliceTo(strings + aux.vda_name, 0));
}

fn sysvHash(name: []const u8) usize {
    var h: u32, var g: u32 = .{ 0, 0 };
    for (name) |c| {
        h = (h << 4) + c;
        g = h & 0xf0000000;
        if (g > 0) {
            h ^= g >> 24;
        }
        h &= ~g;
    }
    return h;
}

fn gnuHash(name: []const u8) usize {
    var h: u32 = 5381;

    for (name) |c| {
        h = (h << 5) +% h + c;
    }

    return h;
}

test "hash functions" {
    try testing.expectEqual(sysvHash(""), 0x00000000);
    try testing.expectEqual(sysvHash("printf"), 0x077905a6);
    try testing.expectEqual(sysvHash("exit"), 0x0006cf04);
    try testing.expectEqual(sysvHash("syscall"), 0x0b09985c);

    try testing.expectEqual(gnuHash(""), 0x00001505);
    try testing.expectEqual(gnuHash("printf"), 0x156b2bb8);
    try testing.expectEqual(gnuHash("exit"), 0x7c967e3f);
    try testing.expectEqual(gnuHash("syscall"), 0xbac212a0);
}

const std = @import("std");
const os = std.os;
const elf = std.elf;
const mem = std.mem;
const testing = std.testing;
const ElfDynLib = @This();
