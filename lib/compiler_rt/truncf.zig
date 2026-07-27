const std = @import("std");

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    if (compiler_rt.want_aeabi) {
        if (compiler_rt.gnu_f16_abi) {
            symbol(&__aeabi_f2h, "__gnu_f2h_ieee");
        } else {
            symbol(&__aeabi_f2h, "__aeabi_f2h");
        }
        symbol(&__aeabi_d2h, "__aeabi_d2h");
    } else if (compiler_rt.gnu_f16_abi) {
        symbol(&__truncsfhf2, "__gnu_f2h_ieee");
    }
    symbol(&__truncsfhf2, "__truncsfhf2");
    symbol(&__truncdfhf2, "__truncdfhf2");
    symbol(&__truncxfhf2, "__truncxfhf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__trunctfhf2, "__trunckfhf2");
    } else {
        symbol(&__trunctfhf2, "__trunctfhf2");
    }

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_d2f, "__aeabi_d2f");
    } else {
        symbol(&__truncdfsf2, "__truncdfsf2");
    }
    symbol(&__truncxfsf2, "__truncxfsf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__trunctfsf2, "__trunckfsf2");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_qtos, "_Qp_qtos");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__trunctfsf2, "_Q_qtos");
    } else {
        symbol(&__trunctfsf2, "__trunctfsf2");
    }

    symbol(&__truncxfdf2, "__truncxfdf2");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__trunctfdf2, "__trunckfdf2");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_qtod, "_Qp_qtod");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__trunctfdf2, "_Q_qtod");
    } else {
        symbol(&__trunctfdf2, "__trunctfdf2");
    }

    if (compiler_rt.want_ppc_abi) {
        symbol(&__trunctfxf2, "__trunckfxf2");
    } else {
        symbol(&__trunctfxf2, "__trunctfxf2");
    }
}

fn __truncsfhf2(a: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f16Conv(f32).Abi {
    return compiler_rt.f16Conv(f32).toAbi(f16_floatCast_f32(compiler_rt.f32.fromAbi(a)));
}
fn __aeabi_f2h(a: u32) callconv(.{ .arm_aapcs = .{} }) u16 {
    return @bitCast(f16_floatCast_f32(@bitCast(a)));
}
pub fn f16_floatCast_f32(a: f32) f16 {
    return truncf(f16, f32, a);
}

fn __truncdfhf2(a: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f16Conv(f64).Abi {
    return compiler_rt.f16Conv(f64).toAbi(f16_floatCast_f64(compiler_rt.f64.fromAbi(a)));
}
fn __aeabi_d2h(a: u64) callconv(.{ .arm_aapcs = .{} }) u16 {
    return @bitCast(f16_floatCast_f64(@bitCast(a)));
}
pub fn f16_floatCast_f64(a: f64) f16 {
    return truncf(f16, f64, a);
}

fn __truncxfhf2(a: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f16Conv(f80).Abi {
    return compiler_rt.f16Conv(f80).toAbi(f16_floatCast_f80(compiler_rt.f80.fromAbi(a)));
}
pub fn f16_floatCast_f80(a: f80) f16 {
    return trunc_f80(f16, a);
}

fn __trunctfhf2(a: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f16Conv(f128).Abi {
    return compiler_rt.f16Conv(f128).toAbi(f16_floatCast_f128(compiler_rt.f128.fromAbi(a)));
}
pub fn f16_floatCast_f128(a: f128) f16 {
    return truncf(f16, f128, a);
}

fn __truncdfsf2(a: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatCast_f64(compiler_rt.f64.fromAbi(a)));
}
fn __aeabi_d2f(a: f64) callconv(.{ .arm_aapcs = .{} }) f32 {
    return f32_floatCast_f64(a);
}
pub fn f32_floatCast_f64(a: f64) f32 {
    return truncf(f32, f64, a);
}

fn __truncxfsf2(a: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatCast_f80(compiler_rt.f80.fromAbi(a)));
}
pub fn f32_floatCast_f80(a: f80) f32 {
    return trunc_f80(f32, a);
}

fn __trunctfsf2(a: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatCast_f128(compiler_rt.f128.fromAbi(a)));
}
fn _Qp_qtos(a: *const f128) callconv(.c) f32 {
    return f32_floatCast_f128(a.*);
}
pub fn f32_floatCast_f128(a: f128) f32 {
    return truncf(f32, f128, a);
}

fn __truncxfdf2(a: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatCast_f80(compiler_rt.f80.fromAbi(a)));
}
pub fn f64_floatCast_f80(a: f80) f64 {
    return trunc_f80(f64, a);
}

fn __trunctfdf2(a: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatCast_f128(compiler_rt.f128.fromAbi(a)));
}
fn _Qp_qtod(a: *const f128) callconv(.c) f64 {
    return f64_floatCast_f128(a.*);
}
pub fn f64_floatCast_f128(a: f128) f64 {
    return truncf(f64, f128, a);
}

fn __trunctfxf2(a: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatCast_f128(compiler_rt.f128.fromAbi(a)));
}
pub fn f80_floatCast_f128(a: f128) f80 {
    const src_sig_bits = std.math.floatMantissaBits(f128);
    const dst_sig_bits = std.math.floatMantissaBits(f80) - 1; // -1 for the integer bit

    // Various constants whose values follow from the type parameters.
    // Any reasonable optimizer will fold and propagate all of these.
    const src_bits = @typeInfo(f128).float.bits;
    const src_exp_bits = src_bits - src_sig_bits - 1;
    const src_inf_exp = 0x7FFF;

    const src_inf = src_inf_exp << src_sig_bits;
    const src_sign_mask = 1 << (src_sig_bits + src_exp_bits);
    const src_abs_mask = src_sign_mask - 1;
    const round_mask = (1 << (src_sig_bits - dst_sig_bits)) - 1;
    const halfway = 1 << (src_sig_bits - dst_sig_bits - 1);

    // Break a into a sign and representation of the absolute value
    const a_rep: u128 = @bitCast(a);
    const a_abs = a_rep & src_abs_mask;
    const sign: u16 = if (a_rep & src_sign_mask != 0) 0x8000 else 0;
    const integer_bit = 1 << 63;

    var res: std.math.F80 = undefined;

    if (a_abs > src_inf) {
        // a is NaN.
        // Conjure the result by beginning with infinity, setting the qNaN
        // bit and inserting the (truncated) trailing NaN field.
        res.exp = 0x7fff;
        res.fraction = 0x8000000000000000;
        res.fraction |= @as(u64, @truncate(a_abs >> (src_sig_bits - dst_sig_bits)));
    } else {
        // The exponent of a is within the range of normal numbers in the
        // destination format.  We can convert by simply right-shifting with
        // rounding, adding the explicit integer bit, and adjusting the exponent
        res.fraction = @as(u64, @truncate(a_abs >> (src_sig_bits - dst_sig_bits))) | integer_bit;
        res.exp = @truncate(a_abs >> src_sig_bits);

        const round_bits = a_abs & round_mask;
        if (round_bits > halfway) {
            // Round to nearest
            const ov = @addWithOverflow(res.fraction, 1);
            res.fraction = ov[0];
            res.exp += ov[1];
            res.fraction |= @as(u64, ov[1]) << 63; // Restore integer bit after carry
        } else if (round_bits == halfway) {
            // Ties to even
            const ov = @addWithOverflow(res.fraction, res.fraction & 1);
            res.fraction = ov[0];
            res.exp += ov[1];
            res.fraction |= @as(u64, ov[1]) << 63; // Restore integer bit after carry
        }
        if (res.exp == 0) res.fraction &= ~@as(u64, integer_bit); // Remove integer bit for de-normals
    }

    res.exp |= sign;
    return res.toFloat();
}

inline fn truncf(comptime dst_t: type, comptime src_t: type, a: src_t) dst_t {
    const src_rep_t = @Int(.unsigned, @typeInfo(src_t).float.bits);
    const dst_rep_t = @Int(.unsigned, @typeInfo(dst_t).float.bits);
    const srcSigBits = std.math.floatMantissaBits(src_t);
    const dstSigBits = std.math.floatMantissaBits(dst_t);

    // Various constants whose values follow from the type parameters.
    // Any reasonable optimizer will fold and propagate all of these.
    const srcBits = @typeInfo(src_t).float.bits;
    const srcExpBits = srcBits - srcSigBits - 1;
    const srcInfExp = (1 << srcExpBits) - 1;
    const srcExpBias = srcInfExp >> 1;

    const srcMinNormal = 1 << srcSigBits;
    const srcSignificandMask = srcMinNormal - 1;
    const srcInfinity = srcInfExp << srcSigBits;
    const srcSignMask = 1 << (srcSigBits + srcExpBits);
    const srcAbsMask = srcSignMask - 1;
    const roundMask = (1 << (srcSigBits - dstSigBits)) - 1;
    const halfway = 1 << (srcSigBits - dstSigBits - 1);
    const srcQNaN = 1 << (srcSigBits - 1);
    const srcNaNCode = srcQNaN - 1;

    const dstBits = @typeInfo(dst_t).float.bits;
    const dstExpBits = dstBits - dstSigBits - 1;
    const dstInfExp = (1 << dstExpBits) - 1;
    const dstExpBias = dstInfExp >> 1;

    const underflowExponent = srcExpBias + 1 - dstExpBias;
    const overflowExponent = srcExpBias + dstInfExp - dstExpBias;
    const underflow = underflowExponent << srcSigBits;
    const overflow = overflowExponent << srcSigBits;

    const dstQNaN = 1 << (dstSigBits - 1);
    const dstNaNCode = dstQNaN - 1;

    // Break a into a sign and representation of the absolute value
    const aRep: src_rep_t = @bitCast(a);
    const aAbs: src_rep_t = aRep & srcAbsMask;
    const sign: src_rep_t = aRep & srcSignMask;
    var absResult: dst_rep_t = undefined;

    if (aAbs -% underflow < aAbs -% overflow) {
        // The exponent of a is within the range of normal numbers in the
        // destination format.  We can convert by simply right-shifting with
        // rounding and adjusting the exponent.
        absResult = @truncate(aAbs >> (srcSigBits - dstSigBits));
        absResult -%= @as(dst_rep_t, srcExpBias - dstExpBias) << dstSigBits;

        const roundBits: src_rep_t = aAbs & roundMask;
        if (roundBits > halfway) {
            // Round to nearest
            absResult += 1;
        } else if (roundBits == halfway) {
            // Ties to even
            absResult += absResult & 1;
        }
    } else if (aAbs > srcInfinity) {
        // a is NaN.
        // Conjure the result by beginning with infinity, setting the qNaN
        // bit and inserting the (truncated) trailing NaN field.
        absResult = @as(dst_rep_t, @intCast(dstInfExp)) << dstSigBits;
        absResult |= dstQNaN;
        absResult |= @intCast(((aAbs & srcNaNCode) >> (srcSigBits - dstSigBits)) & dstNaNCode);
    } else if (aAbs >= overflow) {
        // a overflows to infinity.
        absResult = @as(dst_rep_t, @intCast(dstInfExp)) << dstSigBits;
    } else {
        // a underflows on conversion to the destination type or is an exact
        // zero.  The result may be a denormal or zero.  Extract the exponent
        // to get the shift amount for the denormalization.
        const aExp: u32 = @intCast(aAbs >> srcSigBits);
        const shift: u32 = @intCast(srcExpBias - dstExpBias - aExp + 1);

        const significand: src_rep_t = (aRep & srcSignificandMask) | srcMinNormal;

        // Right shift by the denormalization amount with sticky.
        if (shift > srcSigBits) {
            absResult = 0;
        } else {
            const sticky: src_rep_t = @intFromBool(significand << @intCast(srcBits - shift) != 0);
            const denormalizedSignificand: src_rep_t = significand >> @intCast(shift) | sticky;
            absResult = @intCast(denormalizedSignificand >> (srcSigBits - dstSigBits));
            const roundBits: src_rep_t = denormalizedSignificand & roundMask;
            if (roundBits > halfway) {
                // Round to nearest
                absResult += 1;
            } else if (roundBits == halfway) {
                // Ties to even
                absResult += absResult & 1;
            }
        }
    }

    const result: dst_rep_t align(@alignOf(dst_t)) = absResult |
        @as(dst_rep_t, @truncate(sign >> @intCast(srcBits - dstBits)));
    return @bitCast(result);
}

inline fn trunc_f80(comptime dst_t: type, a: f80) dst_t {
    const dst_rep_t = @Int(.unsigned, @typeInfo(dst_t).float.bits);
    const src_sig_bits = std.math.floatMantissaBits(f80) - 1; // -1 for the integer bit
    const dst_sig_bits = std.math.floatMantissaBits(dst_t);

    const src_exp_bias = 16383;

    const round_mask = (1 << (src_sig_bits - dst_sig_bits)) - 1;
    const halfway = 1 << (src_sig_bits - dst_sig_bits - 1);

    const dst_bits = @typeInfo(dst_t).float.bits;
    const dst_exp_bits = dst_bits - dst_sig_bits - 1;
    const dst_inf_exp = (1 << dst_exp_bits) - 1;
    const dst_exp_bias = dst_inf_exp >> 1;

    const underflow = src_exp_bias + 1 - dst_exp_bias;
    const overflow = src_exp_bias + dst_inf_exp - dst_exp_bias;

    const dst_qnan = 1 << (dst_sig_bits - 1);
    const dst_nan_mask = dst_qnan - 1;

    // Break a into a sign and representation of the absolute value
    var a_rep = std.math.F80.fromFloat(a);
    const sign = a_rep.exp & 0x8000;
    a_rep.exp &= 0x7FFF;
    a_rep.fraction &= 0x7FFFFFFFFFFFFFFF;
    var abs_result: dst_rep_t = undefined;

    if (a_rep.exp -% underflow < a_rep.exp -% overflow) {
        // The exponent of a is within the range of normal numbers in the
        // destination format.  We can convert by simply right-shifting with
        // rounding and adjusting the exponent.
        abs_result = @as(dst_rep_t, a_rep.exp) << dst_sig_bits;
        abs_result |= @truncate(a_rep.fraction >> (src_sig_bits - dst_sig_bits));
        abs_result -%= @as(dst_rep_t, src_exp_bias - dst_exp_bias) << dst_sig_bits;

        const round_bits = a_rep.fraction & round_mask;
        if (round_bits > halfway) {
            // Round to nearest
            abs_result += 1;
        } else if (round_bits == halfway) {
            // Ties to even
            abs_result += abs_result & 1;
        }
    } else if (a_rep.exp == 0x7FFF and a_rep.fraction != 0) {
        // a is NaN.
        // Conjure the result by beginning with infinity, setting the qNaN
        // bit and inserting the (truncated) trailing NaN field.
        abs_result = @as(dst_rep_t, @intCast(dst_inf_exp)) << dst_sig_bits;
        abs_result |= dst_qnan;
        abs_result |= @intCast((a_rep.fraction >> (src_sig_bits - dst_sig_bits)) & dst_nan_mask);
    } else if (a_rep.exp >= overflow) {
        // a overflows to infinity.
        abs_result = @as(dst_rep_t, @intCast(dst_inf_exp)) << dst_sig_bits;
    } else {
        // a underflows on conversion to the destination type or is an exact
        // zero.  The result may be a denormal or zero.  Extract the exponent
        // to get the shift amount for the denormalization.
        const shift = src_exp_bias - dst_exp_bias - a_rep.exp;

        // Right shift by the denormalization amount with sticky.
        if (shift > src_sig_bits) {
            abs_result = 0;
        } else {
            const sticky = @intFromBool(a_rep.fraction << @intCast(shift) != 0);
            const denormalized_significand = a_rep.fraction >> @intCast(shift) | sticky;
            abs_result = @intCast(denormalized_significand >> (src_sig_bits - dst_sig_bits));
            const round_bits = denormalized_significand & round_mask;
            if (round_bits > halfway) {
                // Round to nearest
                abs_result += 1;
            } else if (round_bits == halfway) {
                // Ties to even
                abs_result += abs_result & 1;
            }
        }
    }

    const result align(@alignOf(dst_t)) = abs_result | @as(dst_rep_t, sign) << dst_bits - 16;
    return @bitCast(result);
}

test {
    _ = @import("truncf_test.zig");
}
