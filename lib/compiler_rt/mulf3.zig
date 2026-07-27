const std = @import("std");
const math = std.math;
const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__mulhf3, "__mulhf3");
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_fmul, "__aeabi_fmul");
        symbol(&__aeabi_dmul, "__aeabi_dmul");
    } else {
        symbol(&__mulsf3, "__mulsf3");
        symbol(&__muldf3, "__muldf3");
    }
    symbol(&__mulxf3, "__mulxf3");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__multf3, "__mulkf3");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_mul, "_Qp_mul");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__multf3, "_Q_mul");
    } else {
        symbol(&__multf3, "__multf3");
    }
}

fn __mulhf3(a: compiler_rt.f16.Abi, b: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(mul_f16(compiler_rt.f16.fromAbi(a), compiler_rt.f16.fromAbi(b)));
}
pub fn mul_f16(a: f16, b: f16) f16 {
    return mulf3(f16, a, b);
}

fn __mulsf3(a: compiler_rt.f32.Abi, b: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(mul_f32(compiler_rt.f32.fromAbi(a), compiler_rt.f32.fromAbi(b)));
}
fn __aeabi_fmul(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return mul_f32(a, b);
}
pub fn mul_f32(a: f32, b: f32) f32 {
    return mulf3(f32, a, b);
}

fn __muldf3(a: compiler_rt.f64.Abi, b: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(mul_f64(compiler_rt.f64.fromAbi(a), compiler_rt.f64.fromAbi(b)));
}
fn __aeabi_dmul(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return mul_f64(a, b);
}
pub fn mul_f64(a: f64, b: f64) f64 {
    return mulf3(f64, a, b);
}

fn __mulxf3(a: compiler_rt.f80.Abi, b: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(mul_f80(compiler_rt.f80.fromAbi(a), compiler_rt.f80.fromAbi(b)));
}
pub fn mul_f80(a: f80, b: f80) f80 {
    return mulf3(f80, a, b);
}

fn __multf3(a: compiler_rt.f128.Abi, b: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(mul_f128(compiler_rt.f128.fromAbi(a), compiler_rt.f128.fromAbi(b)));
}
fn _Qp_mul(c: *f128, a: *const f128, b: *const f128) callconv(.c) void {
    c.* = mul_f128(a.*, b.*);
}
pub fn mul_f128(a: f128, b: f128) f128 {
    return mulf3(f128, a, b);
}

/// Ported from:
/// https://github.com/llvm/llvm-project/blob/2ffb1b0413efa9a24eb3c49e710e36f92e2cb50b/compiler-rt/lib/builtins/fp_mul_impl.inc
inline fn mulf3(comptime T: type, a: T, b: T) T {
    @setRuntimeSafety(compiler_rt.test_safety);
    const typeWidth = @typeInfo(T).float.bits;
    const significandBits = math.floatMantissaBits(T);
    const fractionalBits = math.floatFractionalBits(T);
    const exponentBits = math.floatExponentBits(T);

    const Z = @Int(.unsigned, typeWidth);

    // ZSignificand is large enough to contain the significand, including an explicit integer bit
    const ZSignificand = PowerOfTwoSignificandZ(T);
    const ZSignificandBits = @typeInfo(ZSignificand).int.bits;

    const roundBit = (1 << (ZSignificandBits - 1));
    const signBit = (@as(Z, 1) << (significandBits + exponentBits));
    const maxExponent = ((1 << exponentBits) - 1);
    const exponentBias = (maxExponent >> 1);

    const integerBit = (@as(ZSignificand, 1) << fractionalBits);
    const quietBit = integerBit >> 1;
    const significandMask = (@as(Z, 1) << significandBits) - 1;

    const absMask = signBit - 1;
    const qnanRep = @as(Z, @bitCast(math.nan(T))) | quietBit;
    const infRep: Z = @bitCast(math.inf(T));
    const minNormalRep: Z = @bitCast(math.floatMin(T));

    const ZExp = if (typeWidth >= 32) u32 else Z;
    const aExponent: ZExp = @truncate((@as(Z, @bitCast(a)) >> significandBits) & maxExponent);
    const bExponent: ZExp = @truncate((@as(Z, @bitCast(b)) >> significandBits) & maxExponent);
    const productSign: Z = (@as(Z, @bitCast(a)) ^ @as(Z, @bitCast(b))) & signBit;

    var aSignificand: ZSignificand = @intCast(@as(Z, @bitCast(a)) & significandMask);
    var bSignificand: ZSignificand = @intCast(@as(Z, @bitCast(b)) & significandMask);
    var scale: i32 = 0;

    // Detect if a or b is zero, denormal, infinity, or NaN.
    if (aExponent -% 1 >= maxExponent - 1 or bExponent -% 1 >= maxExponent - 1) {
        const aAbs: Z = @as(Z, @bitCast(a)) & absMask;
        const bAbs: Z = @as(Z, @bitCast(b)) & absMask;

        // NaN * anything = qNaN
        if (aAbs > infRep) return @bitCast(@as(Z, @bitCast(a)) | quietBit);
        // anything * NaN = qNaN
        if (bAbs > infRep) return @bitCast(@as(Z, @bitCast(b)) | quietBit);

        if (aAbs == infRep) {
            // infinity * non-zero = +/- infinity
            if (bAbs != 0) {
                return @bitCast(aAbs | productSign);
            } else {
                // infinity * zero = NaN
                return @bitCast(qnanRep);
            }
        }

        if (bAbs == infRep) {
            //? non-zero * infinity = +/- infinity
            if (aAbs != 0) {
                return @bitCast(bAbs | productSign);
            } else {
                // zero * infinity = NaN
                return @bitCast(qnanRep);
            }
        }

        // zero * anything = +/- zero
        if (aAbs == 0) return @bitCast(productSign);
        // anything * zero = +/- zero
        if (bAbs == 0) return @bitCast(productSign);

        // one or both of a or b is denormal, the other (if applicable) is a
        // normal number.  Renormalize one or both of a and b, and set scale to
        // include the necessary exponent adjustment.
        if (aAbs < minNormalRep) scale += normalize(T, &aSignificand);
        if (bAbs < minNormalRep) scale += normalize(T, &bSignificand);
    }

    // Or in the implicit significand bit.  (If we fell through from the
    // denormal path it was already set by normalize( ), but setting it twice
    // won't hurt anything.)
    aSignificand |= integerBit;
    bSignificand |= integerBit;

    // Get the significand of a*b.  Before multiplying the significands, shift
    // one of them left to left-align it in the field.  Thus, the product will
    // have (exponentBits + 2) integral digits, all but two of which must be
    // zero.  Normalizing this result is just a conditional left-shift by one
    // and bumping the exponent accordingly.
    var productHi: ZSignificand = undefined;
    var productLo: ZSignificand = undefined;
    const left_align_shift = ZSignificandBits - fractionalBits - 1;
    compiler_rt.wideMultiply(ZSignificand, aSignificand, bSignificand << left_align_shift, &productHi, &productLo);

    var productExponent: i32 = @as(i32, @intCast(aExponent + bExponent)) - exponentBias + scale;

    // Normalize the significand, adjust exponent if needed.
    if ((productHi & integerBit) != 0) {
        productExponent +%= 1;
    } else {
        productHi = (productHi << 1) | (productLo >> (ZSignificandBits - 1));
        productLo = productLo << 1;
    }

    // If we have overflowed the type, return +/- infinity.
    if (productExponent >= maxExponent) return @bitCast(infRep | productSign);

    var result: Z = undefined;
    if (productExponent <= 0) {
        // Result is denormal before rounding
        //
        // If the result is so small that it just underflows to zero, return
        // a zero of the appropriate sign.  Mathematically there is no need to
        // handle this case separately, but we make it a special case to
        // simplify the shift logic.
        const shift: u32 = @truncate(@as(Z, 1) -% @as(u32, @bitCast(productExponent)));
        if (shift >= ZSignificandBits) return @bitCast(productSign);

        // Otherwise, shift the significand of the result so that the round
        // bit is the high bit of productLo.
        const sticky = wideShrWithTruncation(ZSignificand, &productHi, &productLo, shift);
        productLo |= @intFromBool(sticky);
        result = productHi;

        // We include the integer bit so that rounding will carry to the exponent,
        // but it will be removed later if the result is still denormal
        if (significandBits != fractionalBits) result |= integerBit;
    } else {
        // Result is normal before rounding; insert the exponent.
        result = productHi & significandMask;
        result |= @as(Z, @intCast(productExponent)) << significandBits;
    }

    // Final rounding.  The final result may overflow to infinity, or underflow
    // to zero, but those are the correct results in those cases.  We use the
    // default IEEE-754 round-to-nearest, ties-to-even rounding mode.
    if (productLo > roundBit) result +%= 1;
    if (productLo == roundBit) result +%= result & 1;

    // Restore any explicit integer bit, if it was rounded off
    if (significandBits != fractionalBits) {
        if ((result >> significandBits) != 0) {
            result |= integerBit;
        } else {
            result &= ~integerBit;
        }
    }

    // Insert the sign of the result:
    result |= productSign;

    return @bitCast(result);
}

/// Returns `true` if the right shift is inexact (i.e. any bit shifted out is non-zero)
///
/// This is analogous to an shr version of `@shlWithOverflow`
fn wideShrWithTruncation(comptime Z: type, hi: *Z, lo: *Z, count: u32) bool {
    @setRuntimeSafety(compiler_rt.test_safety);
    const typeWidth = @typeInfo(Z).int.bits;
    var inexact = false;
    if (count < typeWidth) {
        inexact = (lo.* << @intCast(typeWidth -% count)) != 0;
        lo.* = (hi.* << @intCast(typeWidth -% count)) | (lo.* >> @intCast(count));
        hi.* = hi.* >> @intCast(count);
    } else if (count < 2 * typeWidth) {
        inexact = (hi.* << @intCast(2 * typeWidth -% count) | lo.*) != 0;
        lo.* = hi.* >> @intCast(count -% typeWidth);
        hi.* = 0;
    } else {
        inexact = (hi.* | lo.*) != 0;
        lo.* = 0;
        hi.* = 0;
    }
    return inexact;
}

fn normalize(comptime T: type, significand: *PowerOfTwoSignificandZ(T)) i32 {
    const Z = PowerOfTwoSignificandZ(T);
    const integerBit = @as(Z, 1) << math.floatFractionalBits(T);

    const shift = @clz(significand.*) - @clz(integerBit);
    significand.* <<= @intCast(shift);
    return @as(i32, 1) - shift;
}

/// Returns a power-of-two integer type that is large enough to contain
/// the significand of T, including an explicit integer bit
fn PowerOfTwoSignificandZ(comptime T: type) type {
    const bits = math.ceilPowerOfTwoAssert(u16, math.floatFractionalBits(T) + 1);
    return @Int(.unsigned, bits);
}

test {
    _ = @import("mulf3_test.zig");
}
