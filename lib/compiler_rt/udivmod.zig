const builtin = @import("builtin");

const std = @import("std");
const Log2Int = std.math.Log2Int;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const HalveInt = compiler_rt.HalveInt;

comptime {
    symbol(&__umodti3, "__umodti3");
    symbol(&__modti3, "__modti3");
    symbol(&__udivti3, "__udivti3");
    symbol(&__divti3, "__divti3");
    symbol(&__udivmodti4, "__udivmodti4");
}

pub fn __udivmodti4(a: u128, b: u128, maybe_rem: ?*u128) callconv(.c) u128 {
    return udivmod(u128, a, b, maybe_rem);
}

pub fn __divti3(a: i128, b: i128) callconv(.c) i128 {
    return div(a, b);
}

inline fn div(a: i128, b: i128) i128 {
    const s_a = a >> (128 - 1);
    const s_b = b >> (128 - 1);

    const an = (a ^ s_a) -% s_a;
    const bn = (b ^ s_b) -% s_b;

    const r = udivmod(u128, @bitCast(an), @bitCast(bn), null);
    const s = s_a ^ s_b;
    return (@as(i128, @bitCast(r)) ^ s) -% s;
}

pub fn __udivti3(a: u128, b: u128) callconv(.c) u128 {
    return udivmod(u128, a, b, null);
}

pub fn __modti3(a: i128, b: i128) callconv(.c) i128 {
    return mod(a, b);
}

inline fn mod(a: i128, b: i128) i128 {
    const s_a = a >> (128 - 1); // s = a < 0 ? -1 : 0
    const s_b = b >> (128 - 1); // s = b < 0 ? -1 : 0

    const an = (a ^ s_a) -% s_a; // negate if s == -1
    const bn = (b ^ s_b) -% s_b; // negate if s == -1

    var r: u128 = undefined;
    _ = udivmod(u128, @as(u128, @bitCast(an)), @as(u128, @bitCast(bn)), &r);
    return (@as(i128, @bitCast(r)) ^ s_a) -% s_a; // negate if s == -1
}

pub fn __umodti3(a: u128, b: u128) callconv(.c) u128 {
    var r: u128 = undefined;
    _ = udivmod(u128, a, b, &r);
    return r;
}

// Let _u1 and _u0 be the high and low limbs of U respectively.
// Returns U / v_ and sets r = U % v_.
fn divwide_generic(comptime T: type, _u1: T, _u0: T, v_: T, r: *T) T {
    const HalfT = HalveInt(T, false).HalfT;
    @setRuntimeSafety(compiler_rt.test_safety);
    var v = v_;

    const b = @as(T, 1) << (@bitSizeOf(T) / 2);
    var un64: T = undefined;
    var un10: T = undefined;

    const s: Log2Int(T) = @intCast(@clz(v));
    if (s > 0) {
        // Normalize divisor
        v <<= s;
        un64 = (_u1 << s) | (_u0 >> @intCast((@bitSizeOf(T) - @as(T, @intCast(s)))));
        un10 = _u0 << s;
    } else {
        // Avoid undefined behavior of (u0 >> @bitSizeOf(T))
        un64 = _u1;
        un10 = _u0;
    }

    // Break divisor up into two 32-bit digits
    const vn1 = v >> (@bitSizeOf(T) / 2);
    const vn0 = v & std.math.maxInt(HalfT);

    // Break right half of dividend into two digits
    const un1 = un10 >> (@bitSizeOf(T) / 2);
    const un0 = un10 & std.math.maxInt(HalfT);

    // Compute the first quotient digit, q1
    var q1 = un64 / vn1;
    var rhat = un64 -% q1 *% vn1;

    // q1 has at most error 2. No more than 2 iterations
    while (q1 >= b or q1 * vn0 > b * rhat + un1) {
        q1 -= 1;
        rhat += vn1;
        if (rhat >= b) break;
    }

    const un21 = un64 *% b +% un1 -% q1 *% v;

    // Compute the second quotient digit
    var q0 = un21 / vn1;
    rhat = un21 -% q0 *% vn1;

    // q0 has at most error 2. No more than 2 iterations.
    while (q0 >= b or q0 * vn0 > b * rhat + un0) {
        q0 -= 1;
        rhat += vn1;
        if (rhat >= b) break;
    }

    r.* = (un21 *% b +% un0 -% q0 *% v) >> s;
    return q1 *% b +% q0;
}

fn divwide(comptime T: type, _u1: T, _u0: T, v: T, r: *T) T {
    @setRuntimeSafety(compiler_rt.test_safety);
    if (T == u64 and builtin.target.cpu.arch == .x86_64 and builtin.target.os.tag != .windows) {
        var rem: T = undefined;
        const quo = asm (
            \\divq %[v]
            : [_] "={rax}" (-> T),
              [_] "={rdx}" (rem),
            : [v] "r" (v),
              [_] "{rax}" (_u0),
              [_] "{rdx}" (_u1),
        );
        r.* = rem;
        return quo;
    } else {
        return divwide_generic(T, _u1, _u0, v, r);
    }
}

// Returns a_ / b_ and sets maybe_rem = a_ % b.
pub fn udivmod(comptime T: type, a_: T, b_: T, maybe_rem: ?*T) T {
    @setRuntimeSafety(compiler_rt.test_safety);
    const HalfT = HalveInt(T, false).HalfT;
    const half_bits = @bitSizeOf(HalfT);

    if (b_ > a_) {
        if (maybe_rem) |rem| {
            rem.* = a_;
        }
        return 0;
    }

    const a: [2]HalfT = @bitCast(a_); // [0] is low bits, [1] is high bits
    const b: [2]HalfT = @bitCast(b_); // [0] is low bits, [1] is high bits
    var q: [2]HalfT = undefined;
    var r: [2]HalfT = undefined;

    // When the divisor fits in 64 bits, we can use an optimized path
    if (b[1] == 0) {
        r[1] = 0;
        if (a[1] < b[0]) {
            // The result fits in 64 bits
            q[1] = 0;
            q[0] = divwide(HalfT, a[1], a[0], b[0], &r[0]);
        } else {
            // First, divide with the high part to get the remainder. After that a_hi < b_lo.
            q[1] = a[1] / b[0];
            q[0] = divwide(HalfT, a[1] % b[0], a[0], b[0], &r[0]);
        }
        if (maybe_rem) |rem| {
            rem.* = @bitCast(r);
        }
        return @bitCast(q);
    }

    // Large-divisor case: b[1] != 0, so the quotient fits in one HalfT word.
    //
    // Trial quotient via divwide (Knuth Vol 2, Section 4.3.1):
    // Normalize the divisor so its high half has the MSB set, then use divwide
    // on the top bits to get a trial quotient that is at most 1 too large.
    // This replaces the O(shift) bit-by-bit loop with O(1) operations.
    const s: Log2Int(HalfT) = @intCast(@clz(b[1]));

    if (s == 0) {
        // b[1] already has its MSB set, so b >= 2^(T_bits - 1). Since a >= b
        // (we passed the b_ > a_ check), a >= 2^(T_bits - 1) too, meaning
        // a[1] also has its MSB set. Therefore a / b < 2, and the quotient
        // is exactly 1.
        q = @bitCast(@as(T, 0));
        q[0] = 1;
        if (maybe_rem) |rem| {
            rem.* = a_ - b_;
        }
        return @bitCast(q);
    }

    // Normalize b: shift left by s so bn_hi has its MSB set.
    const sr: Log2Int(HalfT) = @intCast(half_bits - @as(
        std.math.IntFittingRange(0, half_bits),
        @intCast(s),
    ));
    const bn_hi: HalfT = (b[1] << s) | (b[0] >> sr);

    // Trial numerator: the top (half_bits + s) bits of (a << s), as [a2:a1].
    // a2 < bn_hi is guaranteed since a2 < 2^s and bn_hi >= 2^(half_bits - 1).
    const a2: HalfT = a[1] >> sr;
    const a1: HalfT = (a[1] << s) | (a[0] >> sr);

    // Trial quotient via divwide: q_hat = floor([a2:a1] / bn_hi).
    // By Knuth's theorem (normalized divisor), q <= q_hat <= q + 1.
    var r_tmp: HalfT = undefined;
    var q_hat: HalfT = divwide(HalfT, a2, a1, bn_hi, &r_tmp);

    // Verify: q_hat * b must not exceed a.
    // Compute the product using HalfT * HalfT -> T widening multiplications,
    // which are native single-instruction ops when HalfT fits in a register
    // (e.g. u64 * u64 -> u128 via mulq on x86_64, mul on aarch64).
    // product = q_hat * [b[1]:b[0]] = [p_top : p_mid : p_lo] (3 half-words)
    const prod_lo: T = @as(T, q_hat) * @as(T, b[0]);
    const prod_hi: T = @as(T, q_hat) * @as(T, b[1]);

    const prod_lo_parts: [2]HalfT = @bitCast(prod_lo);
    const prod_hi_parts: [2]HalfT = @bitCast(prod_hi);

    const mid_add = @addWithOverflow(prod_hi_parts[0], prod_lo_parts[1]);
    var p_mid: HalfT = mid_add[0];
    const p_top: HalfT = prod_hi_parts[1] +% @as(HalfT, mid_add[1]);
    var p_lo: HalfT = prod_lo_parts[0];

    // If product > a, decrement q_hat (at most once, guaranteed by Knuth).
    if (p_top > 0 or p_mid > a[1] or (p_mid == a[1] and p_lo > a[0])) {
        q_hat -= 1;
        // Subtract b from the product for correct remainder computation.
        // After correction, (q_hat * b) fits in T bits, so borrows into
        // p_top cancel it to zero -- we only need [p_mid:p_lo].
        const sub_lo = @subWithOverflow(p_lo, b[0]);
        p_lo = sub_lo[0];
        const sub_mid = @subWithOverflow(p_mid, b[1]);
        const sub_mid2 = @subWithOverflow(sub_mid[0], @as(HalfT, sub_lo[1]));
        p_mid = sub_mid2[0];
    }

    q = @bitCast(@as(T, 0));
    q[0] = q_hat;

    if (maybe_rem) |rem| {
        // remainder = a - q_hat * b = [a[1]:a[0]] - [p_mid:p_lo]
        // This subtraction is non-negative since q_hat <= true quotient.
        const rem_lo = @subWithOverflow(a[0], p_lo);
        r[0] = rem_lo[0];
        const rem_hi = @subWithOverflow(a[1], p_mid);
        const rem_hi2 = @subWithOverflow(rem_hi[0], @as(HalfT, rem_lo[1]));
        r[1] = rem_hi2[0];
        rem.* = @bitCast(r);
    }
    return @bitCast(q);
}

test {
    _ = @import("modti3_test.zig");
    _ = @import("divti3_test.zig");
    _ = @import("udivmodti4_test.zig");
}
