pub const DlOpenFn = *const fn ([*c]const u8, c_int, ?*const anyopaque) callconv(.C) ?*anyopaque;
pub const basename = "linker64";
