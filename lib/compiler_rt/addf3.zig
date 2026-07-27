const std = @import("std");
const math = std.math;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const normalize = compiler_rt.normalize;

comptime {
    symbol(&__addhf3, "__addhf3");
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_fadd, "__aeabi_fadd");
        symbol(&__aeabi_dadd, "__aeabi_dadd");
    } else {
        symbol(&__addsf3, "__addsf3");
        symbol(&__adddf3, "__adddf3");
    }
    symbol(&__addxf3, "__addxf3");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__addtf3, "__addkf3");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_add, "_Qp_add");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__addtf3, "_Q_add");
    } else {
        symbol(&__addtf3, "__addtf3");
    }
}

fn __addhf3(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(add_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)));
}
pub fn add_f16(a: f16, b: f16) f16 {
    return addf3(f16, a, b);
}

fn __addsf3(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(add_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)));
}
fn __aeabi_fadd(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return add_f32(a, b);
}
pub fn add_f32(a: f32, b: f32) f32 {
    return addf3(f32, a, b);
}

fn __adddf3(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(add_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)));
}
fn __aeabi_dadd(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return add_f64(a, b);
}
pub fn add_f64(a: f64, b: f64) f64 {
    return addf3(f64, a, b);
}

fn __addxf3(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(add_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)));
}
pub fn add_f80(a: f80, b: f80) f80 {
    return addf3(f80, a, b);
}

fn __addtf3(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(add_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)));
}
fn _Qp_add(c: *f128, a: *f128, b: *f128) callconv(.c) void {
    c.* = add_f128(a.*, b.*);
}
pub fn add_f128(a: f128, b: f128) f128 {
    return addf3(f128, a, b);
}

comptime {
    symbol(&__subhf3, "__subhf3");
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_fsub, "__aeabi_fsub");
        symbol(&__aeabi_dsub, "__aeabi_dsub");
    } else {
        symbol(&__subsf3, "__subsf3");
        symbol(&__subdf3, "__subdf3");
    }
    symbol(&__subxf3, "__subxf3");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__subtf3, "__subkf3");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_sub, "_Qp_sub");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__subtf3, "_Q_sub");
    } else {
        symbol(&__subtf3, "__subtf3");
    }
}

fn __subhf3(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(sub_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)));
}
pub fn sub_f16(a: f16, b: f16) f16 {
    return add_f16(a, compiler_rt.fneg(b));
}

fn __subsf3(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(sub_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)));
}
fn __aeabi_fsub(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return sub_f32(a, b);
}
pub fn sub_f32(a: f32, b: f32) f32 {
    return add_f32(a, compiler_rt.fneg(b));
}

fn __subdf3(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(sub_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)));
}
fn __aeabi_dsub(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return sub_f64(a, b);
}
pub fn sub_f64(a: f64, b: f64) f64 {
    return add_f64(a, compiler_rt.fneg(b));
}

fn __subxf3(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(sub_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)));
}
pub fn sub_f80(a: f80, b: f80) f80 {
    return add_f80(a, compiler_rt.fneg(b));
}

fn __subtf3(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(sub_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)));
}
fn _Qp_sub(c: *f128, a: *const f128, b: *const f128) callconv(.c) void {
    c.* = sub_f128(a.*, b.*);
}
pub fn sub_f128(a: f128, b: f128) f128 {
    return add_f128(a, compiler_rt.fneg(b));
}

/// Ported from:
///
/// https://github.com/llvm/llvm-project/blob/02d85149a05cb1f6dc49f0ba7a2ceca53718ae17/compiler-rt/lib/builtins/fp_add_impl.inc
inline fn addf3(comptime T: type, a: T, b: T) T {
    const bits = @typeInfo(T).float.bits;
    const Z = @Int(.unsigned, bits);

    const typeWidth = bits;
    const significandBits = math.floatMantissaBits(T);
    const fractionalBits = math.floatFractionalBits(T);
    const exponentBits = math.floatExponentBits(T);

    const signBit = (@as(Z, 1) << (significandBits + exponentBits));
    const maxExponent = ((1 << exponentBits) - 1);

    const integerBit = (@as(Z, 1) << fractionalBits);
    const quietBit = integerBit >> 1;
    const significandMask = (@as(Z, 1) << significandBits) - 1;

    const absMask = signBit - 1;
    const qnanRep = @as(Z, @bitCast(math.nan(T))) | quietBit;

    var aRep: Z = @bitCast(a);
    var bRep: Z = @bitCast(b);
    const aAbs = aRep & absMask;
    const bAbs = bRep & absMask;

    const infRep: Z = @bitCast(math.inf(T));

    // Detect if a or b is zero, infinity, or NaN.
    if (aAbs -% @as(Z, 1) >= infRep - @as(Z, 1) or
        bAbs -% @as(Z, 1) >= infRep - @as(Z, 1))
    {
        // NaN + anything = qNaN
        if (aAbs > infRep) return @bitCast(@as(Z, @bitCast(a)) | quietBit);
        // anything + NaN = qNaN
        if (bAbs > infRep) return @bitCast(@as(Z, @bitCast(b)) | quietBit);

        if (aAbs == infRep) {
            // +/-infinity + -/+infinity = qNaN
            if ((@as(Z, @bitCast(a)) ^ @as(Z, @bitCast(b))) == signBit) {
                return @bitCast(qnanRep);
            }
            // +/-infinity + anything remaining = +/- infinity
            else {
                return a;
            }
        }

        // anything remaining + +/-infinity = +/-infinity
        if (bAbs == infRep) return b;

        // zero + anything = anything
        if (aAbs == 0) {
            // but we need to get the sign right for zero + zero
            if (bAbs == 0) {
                return @bitCast(@as(Z, @bitCast(a)) & @as(Z, @bitCast(b)));
            } else {
                return b;
            }
        }

        // anything + zero = anything
        if (bAbs == 0) return a;
    }

    // Swap a and b if necessary so that a has the larger absolute value.
    if (bAbs > aAbs) {
        const temp = aRep;
        aRep = bRep;
        bRep = temp;
    }

    // Extract the exponent and significand from the (possibly swapped) a and b.
    var aExponent: i32 = @intCast((aRep >> significandBits) & maxExponent);
    var bExponent: i32 = @intCast((bRep >> significandBits) & maxExponent);
    var aSignificand = aRep & significandMask;
    var bSignificand = bRep & significandMask;

    // Normalize any denormals, and adjust the exponent accordingly.
    if (aExponent == 0) aExponent = normalize(T, &aSignificand);
    if (bExponent == 0) bExponent = normalize(T, &bSignificand);

    // The sign of the result is the sign of the larger operand, a.  If they
    // have opposite signs, we are performing a subtraction; otherwise addition.
    const resultSign = aRep & signBit;
    const subtraction = (aRep ^ bRep) & signBit != 0;

    // Shift the significands to give us round, guard and sticky, and or in the
    // implicit significand bit.  (If we fell through from the denormal path it
    // was already set by normalize( ), but setting it twice won't hurt
    // anything.)
    aSignificand = (aSignificand | integerBit) << 3;
    bSignificand = (bSignificand | integerBit) << 3;

    // Shift the significand of b by the difference in exponents, with a sticky
    // bottom bit to get rounding correct.
    const @"align": u32 = @intCast(aExponent - bExponent);
    if (@"align" != 0) {
        if (@"align" < typeWidth) {
            const sticky = if (bSignificand << @intCast(typeWidth - @"align") != 0) @as(Z, 1) else 0;
            bSignificand = (bSignificand >> @truncate(@"align")) | sticky;
        } else {
            bSignificand = 1; // sticky; b is known to be non-zero.
        }
    }
    if (subtraction) {
        aSignificand -= bSignificand;
        // If a == -b, return +zero.
        if (aSignificand == 0) return @bitCast(@as(Z, 0));

        // If partial cancellation occurred, we need to left-shift the result
        // and adjust the exponent:
        if (aSignificand < integerBit << 3) {
            const shift = @as(i32, @intCast(@clz(aSignificand))) - @as(i32, @intCast(@clz(integerBit << 3)));
            aSignificand <<= @intCast(shift);
            aExponent -= shift;
        }
    } else { // addition
        aSignificand += bSignificand;

        // If the addition carried up, we need to right-shift the result and
        // adjust the exponent:
        if (aSignificand & (integerBit << 4) != 0) {
            const sticky = aSignificand & 1;
            aSignificand = aSignificand >> 1 | sticky;
            aExponent += 1;
        }
    }

    // If we have overflowed the type, return +/- infinity:
    if (aExponent >= maxExponent) return @bitCast(infRep | resultSign);

    if (aExponent <= 0) {
        // Result is denormal; the exponent and round/sticky bits are zero.
        // All we need to do is shift the significand and apply the correct sign.
        aSignificand >>= @intCast(4 - aExponent);
        return @bitCast(resultSign | aSignificand);
    }

    // Low three bits are round, guard, and sticky.
    const roundGuardSticky = aSignificand & 0x7;

    // Shift the significand into place, and mask off the integer bit, if it's implicit.
    var result = (aSignificand >> 3) & significandMask;

    // Insert the exponent and sign.
    result |= @as(Z, @intCast(aExponent)) << significandBits;
    result |= resultSign;

    // Final rounding.  The result may overflow to infinity, but that is the
    // correct result in that case.
    if (roundGuardSticky > 0x4) result += 1;
    if (roundGuardSticky == 0x4) result += result & 1;

    // Restore any explicit integer bit, if it was rounded off
    if (significandBits != fractionalBits) {
        if ((result >> significandBits) != 0) result |= integerBit;
    }

    return @bitCast(result);
}

test {
    _ = @import("addf3_test.zig");
}
