const std = @import("std");
const mem = std.mem;

pub fn writeK12(code: *[4]u8, target_value: u12) void {
    var inst = std.mem.readInt(u32, code, .little);
    inst &= 0b11111111110000000000001111111111;
    inst |= (@as(u32, target_value) << 10);
    std.mem.writeInt(u32, code, inst, .little);
}

pub fn writeK16(code: *[4]u8, target_value: u16) void {
    var inst = std.mem.readInt(u32, code, .little);
    inst &= 0b11111100000000000000001111111111;
    inst |= (@as(u32, target_value) << 10);
    std.mem.writeInt(u32, code, inst, .little);
}

pub fn writeJ20(code: *[4]u8, target_value: u20) void {
    var inst = std.mem.readInt(u32, code, .little);
    inst &= 0b11111110000000000000000000011111;
    inst |= (@as(u32, target_value) << 5);
    std.mem.writeInt(u32, code, inst, .little);
}

pub fn writeD5K16(code: *[4]u8, target_value: u21) void {
    var inst = std.mem.readInt(u32, code, .little);
    inst &= 0b11111100000000000000001111100000;
    inst |= @as(u32, target_value >> 16);
    inst |= (@as(u32, target_value << 5) << 5);
    std.mem.writeInt(u32, code, inst, .little);
}

pub fn writeD10K16(code: *[4]u8, target_value: u26) void {
    var inst = std.mem.readInt(u32, code, .little);
    inst &= 0b11111100000000000000000000000000;
    inst |= @as(u32, target_value >> 16);
    inst |= @as(u32, target_value << 10);
    std.mem.writeInt(u32, code, inst, .little);
}

pub fn toPcalaHi20(target: u64, pc: u64) u20 {
    return @truncate(((target +% 0x800) >> 12) -% (pc >> 12));
}

pub fn toPcala64Lo20(target: u64, pc: u64) u20 {
    const fixup = if (target & 0x800 != 0) (@as(u64, 0x1000) -% @as(u64, 0x100000000)) else 0;
    const hi32 = (((target +% 0x80000000 +% fixup) >> 12) -% ((pc -% 8) >> 12)) >> 20;
    return @truncate(hi32);
}

pub fn toPcala64Hi12(target: u64, pc: u64) u12 {
    const fixup = if (target & 0x800 != 0) (@as(u64, 0x1000) -% @as(u64, 0x100000000)) else 0;
    const hi32 = (((target +% 0x80000000 +% fixup) >> 12) -% ((pc -% 12) >> 12)) >> 20;
    return @truncate(hi32 >> 20);
}
