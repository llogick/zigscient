pub const J20 = packed struct(u32) { b0_4: u5, j20: u20, b25_31: u7 };
pub const K12 = packed struct(u32) { b0_9: u10, k12: u12, b22_31: u10 };
pub const K16 = packed struct(u32) { b0_9: u10, k16: u16, b26_31: u6 };
pub const D5K16 = packed struct(u32) { d5: u5, b5_9: u5, k16: u16, b26_31: u6 };
pub const D10K16 = packed struct(u32) { d10: u10, k16: u16, b26_31: u6 };

pub fn pcalaHi20(target: u64, pc: u64) u20 {
    return @truncate(((target +% 0x800) >> 12) -% (pc >> 12));
}

pub fn pcala64Lo20(target: u64, pc: u64) u20 {
    const fixup = if (target & 0x800 != 0) (@as(u64, 0x1000) -% @as(u64, 0x100000000)) else 0;
    const hi32 = (((target +% 0x80000000 +% fixup) >> 12) -% ((pc -% 8) >> 12)) >> 20;
    return @truncate(hi32);
}

pub fn pcala64Hi12(target: u64, pc: u64) u12 {
    const fixup = if (target & 0x800 != 0) (@as(u64, 0x1000) -% @as(u64, 0x100000000)) else 0;
    const hi32 = (((target +% 0x80000000 +% fixup) >> 12) -% ((pc -% 12) >> 12)) >> 20;
    return @truncate(hi32 >> 20);
}
