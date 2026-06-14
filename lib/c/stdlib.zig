const builtin = @import("builtin");

const std = @import("std");
const assert = std.debug.assert;
const div_t = std.c.div_t;
const ldiv_t = std.c.ldiv_t;
const lldiv_t = std.c.lldiv_t;

const symbol = @import("../c.zig").symbol;

comptime {
    _ = @import("stdlib/rand.zig");
    _ = @import("stdlib/drand48.zig");

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // Functions specific to musl and wasi-libc.
        symbol(&abs, "abs");
        symbol(&labs, "labs");
        symbol(&llabs, "llabs");

        symbol(&div, "div");
        symbol(&ldiv, "ldiv");
        symbol(&lldiv, "lldiv");

        symbol(&atoi, "atoi");
        symbol(&atol, "atol");
        symbol(&atoll, "atoll");

        symbol(&strtol, "strtol");
        symbol(&strtoll, "strtoll");
        symbol(&strtoul, "strtoul");
        symbol(&strtoull, "strtoull");
        symbol(&strtoimax, "strtoimax");
        symbol(&strtoumax, "strtoumax");

        symbol(&strtol, "__strtol_internal");
        symbol(&strtoll, "__strtoll_internal");
        symbol(&strtoul, "__strtoul_internal");
        symbol(&strtoull, "__strtoull_internal");
        symbol(&strtoimax, "__strtoimax_internal");
        symbol(&strtoumax, "__strtoumax_internal");

        symbol(&qsort_r, "qsort_r");
        symbol(&qsort, "qsort");

        symbol(&bsearch, "bsearch");
    }
}

fn abs(a: c_int) callconv(.c) c_int {
    return @intCast(@abs(a));
}

fn labs(a: c_long) callconv(.c) c_long {
    return @intCast(@abs(a));
}

fn llabs(a: c_longlong) callconv(.c) c_longlong {
    return @intCast(@abs(a));
}

fn div(a: c_int, b: c_int) callconv(.c) div_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn ldiv(a: c_long, b: c_long) callconv(.c) ldiv_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn lldiv(a: c_longlong, b: c_longlong) callconv(.c) lldiv_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}

fn atoi(str: [*:0]const c_char) callconv(.c) c_int {
    return asciiToInteger(c_int, @ptrCast(str));
}

fn atol(str: [*:0]const c_char) callconv(.c) c_long {
    return asciiToInteger(c_long, @ptrCast(str));
}

fn atoll(str: [*:0]const c_char) callconv(.c) c_longlong {
    return asciiToInteger(c_longlong, @ptrCast(str));
}

fn asciiToInteger(comptime T: type, buf: [*:0]const u8) T {
    comptime assert(std.math.isPowerOfTwo(@bitSizeOf(T)));

    var current = buf;
    while (std.ascii.isWhitespace(current[0])) : (current += 1) {}

    // The behaviour *is* undefined if the result cannot be represented
    // but as they are usually called with untrusted input we can just handle overflow gracefully.
    if (current[0] == '-') return parseDigitsWithSignGenericCharacter(T, u8, current + 1, null, 10, .neg) catch std.math.minInt(T);
    if (current[0] == '+') current += 1;
    return parseDigitsWithSignGenericCharacter(T, u8, current, null, 10, .pos) catch std.math.maxInt(T);
}

fn strtol(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_long {
    return stringToInteger(c_long, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoll(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_longlong {
    return stringToInteger(c_longlong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoul(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulong {
    return stringToInteger(c_ulong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoull(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulonglong {
    return stringToInteger(c_ulonglong, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

// XXX: These belong in inttypes.zig but we'd have to make stringToInteger pub or move it somewhere else.
fn strtoimax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.intmax_t {
    return stringToInteger(std.c.intmax_t, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn strtoumax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.uintmax_t {
    return stringToInteger(std.c.uintmax_t, @ptrCast(str), if (str_end) |end| @ptrCast(end) else null, base);
}

fn stringToInteger(comptime T: type, noalias buf: [*:0]const u8, noalias maybe_end: ?*[*:0]const u8, base: c_int) T {
    comptime assert(std.math.isPowerOfTwo(@bitSizeOf(T)));

    if (base < 0 or base == 1 or base > 36) {
        if (maybe_end) |end| {
            end.* = buf;
        }

        std.c._errno().* = @intFromEnum(std.c.E.INVAL);
        return 0;
    }

    var current = buf;
    while (std.ascii.isWhitespace(current[0])) : (current += 1) {}

    const negative: bool = switch (current[0]) {
        '-' => blk: {
            current += 1;
            break :blk true;
        },
        '+' => blk: {
            current += 1;
            break :blk false;
        },
        else => false,
    };

    // The prefix is allowed iff base == 0 or base == base of the prefix
    const real_base: u6, const digits = blk: {
        if (current[0] == '0') {
            if ((base == 0 or base == 16) and std.ascii.toLower(current[1]) == 'x' and std.ascii.isHex(current[2])) {
                break :blk .{ 16, current[2..] };
            } else if (base == 0) {
                break :blk .{ 8, current };
            } else {
                break :blk .{
                    switch (base) {
                        0 => 10,
                        else => @intCast(base),
                    },
                    current,
                };
            }
        } else {
            const real_base: u6 = switch (base) {
                0 => 10,
                else => @intCast(base),
            };

            _ = std.fmt.charToDigit(current[0], real_base) catch {
                // No digits to parse. Setting errno to .INVAL is optional in this case.
                if (maybe_end) |end| {
                    end.* = buf;
                }
                return 0;
            };
            break :blk .{ real_base, current };
        }
    };

    if (@typeInfo(T).int.signedness == .unsigned) {
        const result = parseDigitsWithSignGenericCharacter(T, u8, digits, maybe_end, real_base, .pos) catch {
            std.c._errno().* = @intFromEnum(std.c.E.RANGE);
            return std.math.maxInt(T);
        };

        return if (negative) -%result else result;
    }

    if (negative) return parseDigitsWithSignGenericCharacter(T, u8, digits, maybe_end, real_base, .neg) catch blk: {
        std.c._errno().* = @intFromEnum(std.c.E.RANGE);
        break :blk std.math.minInt(T);
    };

    return parseDigitsWithSignGenericCharacter(T, u8, digits, maybe_end, real_base, .pos) catch blk: {
        std.c._errno().* = @intFromEnum(std.c.E.RANGE);
        break :blk std.math.maxInt(T);
    };
}

fn parseDigitsWithSignGenericCharacter(
    comptime T: type,
    comptime Char: type,
    noalias buf: [*:0]const Char,
    noalias maybe_end: ?*[*:0]const Char,
    base: u6,
    comptime sign: enum { pos, neg },
) error{Overflow}!T {
    assert(base >= 2 and base <= 36);

    var current = buf;
    defer if (maybe_end) |end| {
        end.* = current;
    };

    const add = switch (sign) {
        .pos => std.math.add,
        .neg => std.math.sub,
    };

    var value: T = 0;
    while (true) {
        const c: u8 = std.math.cast(u8, current[0]) orelse break;

        const digit: u6 = @intCast(std.fmt.charToDigit(c, base) catch break);
        defer current += 1;

        value = try std.math.mul(T, value, base);
        value = try add(T, value, digit);
    }

    return value;
}

// NOTE: Despite its name, `qsort` doesn't have to use quicksort or make any complexity or stability guarantee.
fn qsort_r(base: *anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) void {
    const Context = struct {
        base: [*]u8,
        size: usize,
        compare: *const fn (a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int,
        arg: ?*anyopaque,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.compare(&ctx.base[a * ctx.size], &ctx.base[b * ctx.size], ctx.arg) < 0;
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            const a_bytes: []u8 = ctx.base[a * ctx.size ..][0..ctx.size];
            const b_bytes: []u8 = ctx.base[b * ctx.size ..][0..ctx.size];

            for (a_bytes, b_bytes) |*ab, *bb| {
                const tmp = ab.*;
                ab.* = bb.*;
                bb.* = tmp;
            }
        }
    };

    std.mem.sortUnstableContext(0, n, Context{
        .base = @ptrCast(base),
        .size = size,
        .compare = compare,
        .arg = arg,
    });
}

fn qsort(base: *anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int) callconv(.c) void {
    return qsort_r(base, n, size, (struct {
        fn wrap(a: *const anyopaque, b: *const anyopaque, arg: ?*anyopaque) callconv(.c) c_int {
            const cmp: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(arg.?));
            return cmp(a, b);
        }
    }).wrap, @constCast(compare));
}

// NOTE: Despite its name, `bsearch` doesn't need to be implemented using binary search or make any complexity guarantee.
fn bsearch(key: *const anyopaque, base: *const anyopaque, n: usize, size: usize, compare: *const fn (a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int) callconv(.c) ?*anyopaque {
    const base_bytes: [*]const u8 = @ptrCast(base);
    var low: usize = 0;
    var high: usize = n;

    while (low < high) {
        // Avoid overflowing in the midpoint calculation
        const mid = low + (high - low) / 2;
        const elem = &base_bytes[mid * size];

        switch (std.math.order(compare(key, elem), 0)) {
            .eq => return @constCast(elem),
            .gt => low = mid + 1,
            .lt => high = mid,
        }
    }
    return null;
}
