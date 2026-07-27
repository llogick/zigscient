const builtin = @import("builtin");
const std = @import("std");

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

const Unordered = if (builtin.cpu.arch == .avr)
    i8
else if (builtin.cpu.arch.isAARCH64())
    i32
else if (builtin.target.cTypeBitSize(.long).? >= builtin.target.ptrBitWidth())
    c_long
else
    c_longlong;
pub const Order = enum(Unordered) { lt = -1, eq = 0, gt = 1 };
const SparcOrder = enum(i32) { eq = 0, lt = 1, gt = 2, un = 3 };

comptime {
    symbol(&__cmphf2, "__cmphf2");
    symbol(&__cmphf2, "__eqhf2");
    symbol(&__cmphf2, "__nehf2");
    symbol(&__cmphf2, "__lthf2");
    symbol(&__cmphf2, "__lehf2");
    symbol(&__gehf2, "__gthf2");
    symbol(&__gehf2, "__gehf2");
    symbol(&__unordhf2, "__unordhf2");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_fcmpeq, "__aeabi_fcmpeq");
        symbol(&__aeabi_fcmplt, "__aeabi_fcmplt");
        symbol(&__aeabi_fcmple, "__aeabi_fcmple");
        symbol(&__aeabi_fcmpgt, "__aeabi_fcmpgt");
        symbol(&__aeabi_fcmpge, "__aeabi_fcmpge");
        symbol(&__aeabi_fcmpun, "__aeabi_fcmpun");

        symbol(&__aeabi_dcmpeq, "__aeabi_dcmpeq");
        symbol(&__aeabi_dcmplt, "__aeabi_dcmplt");
        symbol(&__aeabi_dcmple, "__aeabi_dcmple");
        symbol(&__aeabi_dcmpgt, "__aeabi_dcmpgt");
        symbol(&__aeabi_dcmpge, "__aeabi_dcmpge");
        symbol(&__aeabi_dcmpun, "__aeabi_dcmpun");
    } else {
        symbol(&__cmpsf2, "__cmpsf2");
        symbol(&__cmpsf2, "__eqsf2");
        symbol(&__cmpsf2, "__nesf2");
        symbol(&__cmpsf2, "__ltsf2");
        symbol(&__cmpsf2, "__lesf2");
        symbol(&__gesf2, "__gtsf2");
        symbol(&__gesf2, "__gesf2");
        symbol(&__unordsf2, "__unordsf2");

        symbol(&__cmpdf2, "__cmpdf2");
        symbol(&__cmpdf2, "__eqdf2");
        symbol(&__cmpdf2, "__nedf2");
        symbol(&__cmpdf2, "__ltdf2");
        symbol(&__cmpdf2, "__ledf2");
        symbol(&__gedf2, "__gtdf2");
        symbol(&__gedf2, "__gedf2");
        symbol(&__unorddf2, "__unorddf2");
    }

    symbol(&__cmpxf2, "__cmpxf2");
    symbol(&__cmpxf2, "__eqxf2");
    symbol(&__cmpxf2, "__nexf2");
    symbol(&__cmpxf2, "__ltxf2");
    symbol(&__cmpxf2, "__lexf2");
    symbol(&__gexf2, "__gtxf2");
    symbol(&__gexf2, "__gexf2");
    symbol(&__unordxf2, "__unordxf2");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__cmptf2, "__eqkf2");
        symbol(&__cmptf2, "__nekf2");
        symbol(&__cmptf2, "__ltkf2");
        symbol(&__cmptf2, "__lekf2");
        symbol(&__getf2, "__gtkf2");
        symbol(&__getf2, "__gekf2");
        symbol(&__unordtf2, "__unordkf2");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_cmp, "_Qp_cmp");
        symbol(&_Qp_feq, "_Qp_feq");
        symbol(&_Qp_fne, "_Qp_fne");
        symbol(&_Qp_flt, "_Qp_flt");
        symbol(&_Qp_fle, "_Qp_fle");
        symbol(&_Qp_fgt, "_Qp_fgt");
        symbol(&_Qp_fge, "_Qp_fge");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&_Q_cmp, "_Q_cmp");
        symbol(&_Q_feq, "_Q_feq");
        symbol(&_Q_fne, "_Q_fne");
        symbol(&_Q_flt, "_Q_flt");
        symbol(&_Q_fle, "_Q_fle");
        symbol(&_Q_fgt, "_Q_fgt");
        symbol(&_Q_fge, "_Q_fge");
    } else {
        symbol(&__cmptf2, "__cmptf2");
        symbol(&__cmptf2, "__eqtf2");
        symbol(&__cmptf2, "__netf2");
        symbol(&__cmptf2, "__lttf2");
        symbol(&__cmptf2, "__letf2");
        symbol(&__getf2, "__gttf2");
        symbol(&__getf2, "__getf2");
        symbol(&__unordtf2, "__unordtf2");
    }
}

fn __cmphf2(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) Order {
    return cmp_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)) orelse .gt;
}
fn __gehf2(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) Order {
    return cmp_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)) orelse .lt;
}
fn __unordhf2(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) Unordered {
    return @intFromBool(unord_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)));
}
pub fn cmp_f16(a: f16, b: f16) ?Order {
    return cmpf2(f16, a, b);
}
pub fn unord_f16(a: f16, b: f16) bool {
    return unord(f16, a, b);
}

fn __cmpsf2(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) Order {
    return cmp_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)) orelse .gt;
}
fn __aeabi_fcmpeq(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f32(a, b) == .eq);
}
fn __aeabi_fcmplt(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f32(a, b) == .lt);
}
fn __aeabi_fcmple(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f32(a, b) orelse .gt != .gt);
}
fn __gesf2(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) Order {
    return cmp_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)) orelse .lt;
}
fn __aeabi_fcmpge(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f32(a, b) orelse .lt != .lt);
}
fn __aeabi_fcmpgt(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f32(a, b) == .gt);
}
fn __unordsf2(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) Unordered {
    return @intFromBool(unord_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)));
}
fn __aeabi_fcmpun(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(unord_f32(a, b));
}
pub fn cmp_f32(a: f32, b: f32) ?Order {
    return cmpf2(f32, a, b);
}
pub fn unord_f32(a: f32, b: f32) bool {
    return unord(f32, a, b);
}

fn __cmpdf2(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) Order {
    return cmp_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)) orelse .gt;
}
fn __aeabi_dcmpeq(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f64(a, b) == .eq);
}
fn __aeabi_dcmplt(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f64(a, b) == .lt);
}
fn __aeabi_dcmple(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f64(a, b) orelse .gt != .gt);
}
fn __gedf2(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) Order {
    return cmp_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)) orelse .lt;
}
fn __aeabi_dcmpge(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f64(a, b) orelse .lt != .lt);
}
fn __aeabi_dcmpgt(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(cmp_f64(a, b) == .gt);
}
fn __unorddf2(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) Unordered {
    return @intFromBool(unord_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)));
}
fn __aeabi_dcmpun(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return @intFromBool(unord_f64(a, b));
}
pub fn cmp_f64(a: f64, b: f64) ?Order {
    return cmpf2(f64, a, b);
}
pub fn unord_f64(a: f64, b: f64) bool {
    return unord(f64, a, b);
}

fn __cmpxf2(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) Order {
    return cmp_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)) orelse .gt;
}
fn __gexf2(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) Order {
    return cmp_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)) orelse .lt;
}
fn __unordxf2(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) Unordered {
    return @intFromBool(unord_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)));
}
pub fn cmp_f80(a: f80, b: f80) ?Order {
    const a_rep = std.math.F80.fromFloat(a);
    const b_rep = std.math.F80.fromFloat(b);
    const sig_bits = std.math.floatMantissaBits(f80);
    const int_bit = 0x8000000000000000;
    const sign_bit = 0x8000;
    const special_exp = 0x7FFF;

    // If either a or b is NaN, they are unordered.
    if ((a_rep.exp & special_exp == special_exp and a_rep.fraction ^ int_bit != 0) or
        (b_rep.exp & special_exp == special_exp and b_rep.fraction ^ int_bit != 0))
        return null;

    // If a and b are both zeros, they are equal.
    if ((a_rep.fraction | b_rep.fraction) | ((a_rep.exp | b_rep.exp) & special_exp) == 0)
        return .eq;

    if (@intFromBool(a_rep.exp == b_rep.exp) & @intFromBool(a_rep.fraction == b_rep.fraction) != 0) {
        return .eq;
    } else if (a_rep.exp & sign_bit != b_rep.exp & sign_bit) {
        // signs are different
        if (@as(i16, @bitCast(a_rep.exp)) < @as(i16, @bitCast(b_rep.exp))) {
            return .lt;
        } else {
            return .gt;
        }
    } else {
        const a_fraction = a_rep.fraction | (@as(u80, a_rep.exp) << sig_bits);
        const b_fraction = b_rep.fraction | (@as(u80, b_rep.exp) << sig_bits);
        if ((a_fraction < b_fraction) == (a_rep.exp & sign_bit == 0)) {
            return .lt;
        } else {
            return .gt;
        }
    }
}
pub fn unord_f80(a: f80, b: f80) bool {
    return unord(f80, a, b);
}

fn __cmptf2(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) Order {
    return cmp_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)) orelse .gt;
}
fn __getf2(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) Order {
    return cmp_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)) orelse .lt;
}
fn __unordtf2(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) Unordered {
    return @intFromBool(unord_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)));
}
fn _Qp_cmp(a: *const f128, b: *const f128) callconv(.c) SparcOrder {
    return switch (cmp_f128(a.*, b.*) orelse return .un) {
        .lt => .lt,
        .eq => .eq,
        .gt => .gt,
    };
}
fn _Qp_feq(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a.*, b.*) == .eq);
}
fn _Qp_fne(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a.*, b.*) != .eq);
}
fn _Qp_flt(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a.*, b.*) == .lt);
}
fn _Qp_fle(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool((cmp_f128(a.*, b.*) orelse .gt) != .gt);
}
fn _Qp_fgt(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a.*, b.*) == .gt);
}
fn _Qp_fge(a: *const f128, b: *const f128) callconv(.c) i32 {
    return @intFromBool((cmp_f128(a.*, b.*) orelse .lt) != .lt);
}
fn _Q_cmp(a: f128, b: f128) callconv(.c) SparcOrder {
    return switch (cmp_f128(a, b) orelse return .un) {
        .lt => .lt,
        .eq => .eq,
        .gt => .gt,
    };
}
fn _Q_feq(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a, b) == .eq);
}
fn _Q_fne(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a, b) != .eq);
}
fn _Q_flt(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a, b) == .lt);
}
fn _Q_fle(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool((cmp_f128(a, b) orelse .gt) != .gt);
}
fn _Q_fgt(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool(cmp_f128(a, b) == .gt);
}
fn _Q_fge(a: f128, b: f128) callconv(.c) i32 {
    return @intFromBool((cmp_f128(a, b) orelse .lt) != .lt);
}
pub fn cmp_f128(a: f128, b: f128) ?Order {
    return cmpf2(f128, a, b);
}
pub fn unord_f128(a: f128, b: f128) bool {
    return unord(f128, a, b);
}

inline fn cmpf2(comptime T: type, a: T, b: T) ?Order {
    const bits = @typeInfo(T).float.bits;
    const srep_t = @Int(.signed, bits);
    const rep_t = @Int(.unsigned, bits);

    const significandBits = std.math.floatMantissaBits(T);
    const exponentBits = std.math.floatExponentBits(T);
    const signBit = (@as(rep_t, 1) << (significandBits + exponentBits));
    const absMask = signBit - 1;
    const infT = comptime std.math.inf(T);
    const infRep = @as(rep_t, @bitCast(infT));

    const aInt = @as(srep_t, @bitCast(a));
    const bInt = @as(srep_t, @bitCast(b));
    const aAbs = @as(rep_t, @bitCast(aInt)) & absMask;
    const bAbs = @as(rep_t, @bitCast(bInt)) & absMask;

    // If either a or b is NaN, they are unordered.
    if (aAbs > infRep or bAbs > infRep) return null;

    // If a and b are both zeros, they are equal.
    if ((aAbs | bAbs) == 0) return .eq;

    // If at least one of a and b is positive, we get the same result comparing
    // a and b as signed integers as we would with a floating-point compare.
    if ((aInt & bInt) >= 0) {
        if (aInt < bInt) {
            return .lt;
        } else if (aInt == bInt) {
            return .eq;
        } else return .gt;
    } else {
        // Otherwise, both are negative, so we need to flip the sense of the
        // comparison to get the correct result.  (This assumes a twos- or ones-
        // complement integer representation; if integers are represented in a
        // sign-magnitude representation, then this flip is incorrect).
        if (aInt > bInt) {
            return .lt;
        } else if (aInt == bInt) {
            return .eq;
        } else return .gt;
    }
}

test cmp_f80 {
    try std.testing.expect(cmp_f80(1.0, 1.0) == .eq);
    try std.testing.expect(cmp_f80(0.0, -0.0) == .eq);
    try std.testing.expect(cmp_f80(2.0, 4.0) == .lt);
    try std.testing.expect(cmp_f80(2.0, -4.0) == .gt);
    try std.testing.expect(cmp_f80(-2.0, -4.0) == .gt);
    try std.testing.expect(cmp_f80(-2.0, 4.0) == .lt);
}

inline fn unord(comptime T: type, a: T, b: T) bool {
    const rep_t = @Int(.unsigned, @typeInfo(T).float.bits);

    const significandBits = std.math.floatMantissaBits(T);
    const exponentBits = std.math.floatExponentBits(T);
    const signBit = (@as(rep_t, 1) << (significandBits + exponentBits));
    const absMask = signBit - 1;
    const infRep = @as(rep_t, @bitCast(std.math.inf(T)));

    const aAbs: rep_t = @as(rep_t, @bitCast(a)) & absMask;
    const bAbs: rep_t = @as(rep_t, @bitCast(b)) & absMask;

    return aAbs > infRep or bAbs > infRep;
}

test {
    _ = @import("comparesf2_test.zig");
    _ = @import("comparedf2_test.zig");
}
