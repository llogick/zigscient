//! drand48 functions are based off a 48-bit lcg prng: https://pubs.opengroup.org/onlinepubs/9799919799/functions/drand48.html

const builtin = @import("builtin");

const std = @import("std");
const Lcg = std.Random.lcg.Wrapping(u48);

const symbol = @import("../../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&erand48, "erand48");
        symbol(&jrand48, "jrand48");
        symbol(&nrand48, "nrand48");
        symbol(&drand48, "drand48");
        symbol(&lrand48, "lrand48");
        symbol(&mrand48, "mrand48");
        symbol(&lcong48, "lcong48");
        symbol(&seed48, "seed48");
        symbol(&srand48, "srand48");
    }
}

// NOTE: all "magic" numbers and tests are extracted and adapted from the source above

const default_multiplier = 0x5DEECE66D;
const default_addend = 0xB;

var lcg: Lcg = .init(0, default_multiplier, default_addend);
var seed48_xi: [3]c_ushort = undefined;

fn erand48(xsubi: *[3]c_ushort) callconv(.c) f64 {
    const xi = @as(u48, @as(u16, @truncate(xsubi[0])) | (@as(u48, @as(u16, @truncate(xsubi[1])))) << 16) | (@as(u48, @as(u16, @truncate(xsubi[2]))) << 32);

    var separate_lcg: Lcg = .init(xi, lcg.a, lcg.c);
    const next_xi = separate_lcg.next();

    xsubi.* = .{ @truncate(next_xi & 0xFFFF), @truncate((next_xi >> 16) & 0xFFFF), @truncate((next_xi >> 32) & 0xFFFF) };
    return @as(f64, @bitCast(0x3ff0000000000000 | (@as(u64, next_xi) << 4))) - 1.0;
}

fn jrand48(xsubi: *[3]c_ushort) callconv(.c) c_long {
    const xi = @as(u48, @as(u16, @truncate(xsubi[0])) | (@as(u48, @as(u16, @truncate(xsubi[1])))) << 16) | (@as(u48, @as(u16, @truncate(xsubi[2]))) << 32);

    var separate_lcg: Lcg = .init(xi, lcg.a, lcg.c);
    const next_xi = separate_lcg.next();

    xsubi.* = .{ @truncate(next_xi & 0xFFFF), @truncate((next_xi >> 16) & 0xFFFF), @truncate((next_xi >> 32) & 0xFFFF) };
    return @as(i32, @bitCast(@as(u32, @truncate(next_xi >> 16))));
}

fn nrand48(xsubi: *[3]c_ushort) callconv(.c) c_long {
    const xi = @as(u48, @as(u16, @truncate(xsubi[0])) | (@as(u48, @as(u16, @truncate(xsubi[1])))) << 16) | (@as(u48, @as(u16, @truncate(xsubi[2]))) << 32);

    var separate_lcg: Lcg = .init(xi, lcg.a, lcg.c);
    const next_xi = separate_lcg.next();

    xsubi.* = .{ @truncate(next_xi & 0xFFFF), @truncate((next_xi >> 16) & 0xFFFF), @truncate((next_xi >> 32) & 0xFFFF) };
    return @intCast(next_xi >> 17); // a c_long is always at least 32-bits, this is never UB
}

fn drand48() callconv(.c) f64 {
    return @as(f64, @bitCast(0x3ff0000000000000 | (@as(u64, lcg.next()) << 4))) - 1.0;
}

fn lrand48() callconv(.c) c_long {
    return @intCast(lcg.next() >> 17);
}

fn mrand48() callconv(.c) c_long {
    return @as(i32, @bitCast(@as(u32, @truncate(lcg.next() >> 16))));
}

// 0..3 is `Xi`, 3..6 is `a`, 6 is `c`
// first low 16-bits, then mid, then high.
fn lcong48(param: *[7]c_ushort) callconv(.c) void {
    lcg.xi = (@as(u48, @as(u16, @truncate(param[0]))) | (@as(u48, @as(u16, @truncate(param[1])))) << 16) | (@as(u48, @as(u16, @truncate(param[2]))) << 32);
    lcg.a = (@as(u48, @as(u16, @truncate(param[3]))) | (@as(u48, @as(u16, @truncate(param[4])))) << 16) | (@as(u48, @as(u16, @truncate(param[5]))) << 32);
    lcg.c = @as(u16, @truncate(param[6]));
}

fn seed48(seed16v: *[3]c_ushort) callconv(.c) *[3]c_ushort {
    seed48_xi = .{ @truncate(lcg.xi & 0xFFFF), @truncate((lcg.xi >> 16) & 0xFFFF), @truncate((lcg.xi >> 32) & 0xFFFF) };
    const xi = (@as(u48, @as(u16, @truncate(seed16v[0]))) | (@as(u48, @as(u16, @truncate(seed16v[1])))) << 16) | (@as(u48, @as(u16, @truncate(seed16v[2]))) << 32);
    lcg = .init(xi, default_multiplier, default_addend);
    return &seed48_xi;
}

fn srand48(seedval: c_long) callconv(.c) void {
    const xi = (@as(u32, @truncate(@as(c_ulong, @bitCast(seedval)))) << 16) | 0x330E;
    lcg = .init(xi, default_multiplier, default_addend);
}
