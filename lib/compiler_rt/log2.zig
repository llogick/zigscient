//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/log2f.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/log2.c

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const maxInt = std.math.maxInt;
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__log2h, "__log2h");
    symbol(&log2f, "log2f");
    symbol(&log2, "log2");
    symbol(&__log2x, "__log2x");
    if (compiler_rt.want_ppc_abi) {
        symbol(&log2q, "log2f128");
    }
    symbol(&log2q, "log2q");
    symbol(&log2l, "log2l");
}

pub fn __log2h(a: f16) callconv(.c) f16 {
    // TODO: more efficient implementation
    return @floatCast(log2f(a));
}

pub fn log2f(x_: f32) callconv(.c) f32 {
    const ivln2hi: f32 = 1.4428710938e+00;
    const ivln2lo: f32 = -1.7605285393e-04;
    const Lg1: f32 = 0xaaaaaa.0p-24;
    const Lg2: f32 = 0xccce13.0p-25;
    const Lg3: f32 = 0x91e9ee.0p-25;
    const Lg4: f32 = 0xf89e26.0p-26;

    var x = x_;
    var u: u32 = @bitCast(x);
    var ix = u;
    var k: i32 = 0;

    // x < 2^(-126)
    if (ix < 0x00800000 or ix >> 31 != 0) {
        // log(+-0) = -inf
        if (ix << 1 == 0) {
            return if (compiler_rt.want_float_exceptions) -1 / (x * x) else -std.math.inf(f64);
        }
        // log(-#) = nan
        if (ix >> 31 != 0) {
            return if (compiler_rt.want_float_exceptions) (x - x) / 0.0 else math.nan(f64);
        }

        k -= 25;
        x *= 0x1.0p25;
        ix = @bitCast(x);
    } else if (ix >= 0x7F800000) {
        return x;
    } else if (ix == 0x3F800000) {
        return 0;
    }

    // x into [sqrt(2) / 2, sqrt(2)]
    ix += 0x3F800000 - 0x3F3504F3;
    k += @as(i32, @intCast(ix >> 23)) - 0x7F;
    ix = (ix & 0x007FFFFF) + 0x3F3504F3;
    x = @bitCast(ix);

    const f = x - 1.0;
    const s = f / (2.0 + f);
    const z = s * s;
    const w = z * z;
    const t1 = w * (Lg2 + w * Lg4);
    const t2 = z * (Lg1 + w * Lg3);
    const R = t2 + t1;
    const hfsq = 0.5 * f * f;

    var hi = f - hfsq;
    u = @bitCast(hi);
    u &= 0xFFFFF000;
    hi = @bitCast(u);
    const lo = f - hi - hfsq + s * (hfsq + R);
    return (lo + hi) * ivln2lo + lo * ivln2hi + hi * ivln2hi + @as(f32, @floatFromInt(k));
}

pub fn log2(x_: f64) callconv(.c) f64 {
    const ivln2hi: f64 = 1.44269504072144627571e+00;
    const ivln2lo: f64 = 1.67517131648865118353e-10;
    const Lg1: f64 = 6.666666666666735130e-01;
    const Lg2: f64 = 3.999999999940941908e-01;
    const Lg3: f64 = 2.857142874366239149e-01;
    const Lg4: f64 = 2.222219843214978396e-01;
    const Lg5: f64 = 1.818357216161805012e-01;
    const Lg6: f64 = 1.531383769920937332e-01;
    const Lg7: f64 = 1.479819860511658591e-01;

    var x = x_;
    var ix: u64 = @bitCast(x);
    var hx: u32 = @intCast(ix >> 32);
    var k: i32 = 0;

    if (hx < 0x00100000 or hx >> 31 != 0) {
        // log(+-0) = -inf
        if (ix << 1 == 0) {
            return if (compiler_rt.want_float_exceptions) -1 / (x * x) else -std.math.inf(f64);
        }
        // log(-#) = nan
        if (hx >> 31 != 0) {
            return if (compiler_rt.want_float_exceptions) (x - x) / 0.0 else math.nan(f64);
        }

        // subnormal, scale x
        k -= 54;
        x *= 0x1.0p54;
        hx = @intCast(@as(u64, @bitCast(x)) >> 32);
    } else if (hx >= 0x7FF00000) {
        return x;
    } else if (hx == 0x3FF00000 and ix << 32 == 0) {
        return 0;
    }

    // x into [sqrt(2) / 2, sqrt(2)]
    hx += 0x3FF00000 - 0x3FE6A09E;
    k += @as(i32, @intCast(hx >> 20)) - 0x3FF;
    hx = (hx & 0x000FFFFF) + 0x3FE6A09E;
    ix = (@as(u64, hx) << 32) | (ix & 0xFFFFFFFF);
    x = @bitCast(ix);

    const f = x - 1.0;
    const hfsq = 0.5 * f * f;
    const s = f / (2.0 + f);
    const z = s * s;
    const w = z * z;
    const t1 = w * (Lg2 + w * (Lg4 + w * Lg6));
    const t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
    const R = t2 + t1;

    // hi + lo = f - hfsq + s * (hfsq + R) ~ log(1 + f)
    var hi = f - hfsq;
    var hii = @as(u64, @bitCast(hi));
    hii &= @as(u64, maxInt(u64)) << 32;
    hi = @bitCast(hii);
    const lo = f - hi - hfsq + s * (hfsq + R);

    var val_hi = hi * ivln2hi;
    var val_lo = (lo + hi) * ivln2lo + lo * ivln2hi;

    // spadd(val_hi, val_lo, y)
    const y: f64 = @floatFromInt(k);
    const ww = y + val_hi;
    val_lo += (y - ww) + val_hi;
    val_hi = ww;

    return val_lo + val_hi;
}

pub fn __log2x(a: f80) callconv(.c) f80 {
    // TODO: more efficient implementation
    return @floatCast(log2q(a));
}

/// Implementation of "Table-driven implementation of the logarithm function in IEEE floating-point arithmetic"
/// by PTP Tang in ACM Transactions on Mathematical Software (TOMS), 1990
///
/// https://dl.acm.org/doi/pdf/10.1145/98267.98294
///
/// Adapted to work for f128 and base 2 by Christophe Delage.
///
/// Accuracy on 100 million random numbers in [0, inf) (exponent uniformly random)
/// <= 0.5 ulp: 99.99%, worst case <= 0.594 ulp
///
/// Accuracy on 10 million random numbers near x = 1 (testing the proc2 case):
/// <= 0.5 ulp: 99.86%, worst case <= 0.546 ulp
pub fn log2q(x: f128) callconv(.c) f128 {
    const impl = @import("log_f128.zig");

    if (impl.specialCases(x)) |y|
        return y;

    if (impl.Proc2.lo < x and x < impl.Proc2.hi) {
        // Polynomial approximation of log2((1 + u / 2) / (1 - u / 2))
        // in [2 * a / (2 + a), 2 * b / (2 + b)]
        // where a = exp(-1 / 16) - 1 and b = exp(1 / 16) - 1
        const poly: impl.Proc2.Poly = .{
            .b1_hi = 0x1.71547652b82fep0,
            .b1_lo = 0x1.777d0ffda0d23a7d11d6aef551bbp-56,
            .b3 = 0.12022458674074695061332705675016125,
            .b5 = 1.8033688011112042591999058475816515e-2,
            .b7 = 3.2203014305557218914285331735164364e-3,
            .b9 = 6.261697226080570342191671010883619e-4,
            .b11 = 1.280801705334664325639770412440281e-4,
            .b13 = 2.7093882228102330360125035037716968e-5,
            .b15 = 5.870341197214724685339102193694838e-6,
            .b17 = 1.294917697032820750200161813672143e-6,
            .b19 = 2.909291439731657940692470637735429e-7,
        };
        return impl.proc2(.{ .poly = poly }, x);
    }

    // Polynomial approximation of log2(1 + 2 * u / (2 - u))
    // in [-(2 * fmax) / (2 + fmax), (2 * fmax) / (2 - fmax)]
    // where fmax = 0.5 / size
    const poly: impl.Proc1.Poly = .{
        .a1 = 1.442695040888963407359924681001892,
        .a3 = 0.12022458674074695061332705675072149,
        .a5 = 1.8033688011112042591998536830294507e-2,
        .a7 = 3.22030143055572204818095463930704e-3,
        .a9 = 6.261697225875019234719395591078697e-4,
        .a11 = 1.280813940786848788109850061222256e-4,
    };
    // tab[j].hi = 2^-n * round-to-integer(2^n * l)
    // tab[j].lo = round-to-nearest-f128(l - tab[j].hi)
    // where n = 97 and l = log2(1 + j / size)
    const tab = [impl.size + 1]impl.Proc1.HiLo{
        .{ .hi = 0, .lo = 0 },
        .{ .hi = 0x1.6fe50b6ef08517f8e37bp-7, .lo = 0x1.794f4441ccdf648f265a41e57d75p-99 },
        .{ .hi = 0x1.6e79685c2d2298a6e27e212p-6, .lo = -0x1.fbd41ae7d5a2434912ad3fe21cfbp-100 },
        .{ .hi = 0x1.11cd1d5133412ed814504fbp-5, .lo = -0x1.b2e2b43254008aeb4167a3359577p-99 },
        .{ .hi = 0x1.6bad3758efd87313606f097p-5, .lo = -0x1.20fbdb7ce4c86d28e4be331fce17p-99 },
        .{ .hi = 0x1.c4dfab90aab5ef4f8f869e6p-5, .lo = 0x1.dc4142bd2b182fdaac375356fc29p-100 },
        .{ .hi = 0x1.0eb389fa29f9ab3cf74bab98p-4, .lo = 0x1.9217066b9150f3c7ddd223517be7p-100 },
        .{ .hi = 0x1.3aa2fdd27f1c2d804d1121b8p-4, .lo = -0x1.acec4ac95b97a0e1d121d0222ba5p-99 },
        .{ .hi = 0x1.663f6fac913167ccc5382618p-4, .lo = -0x1.dd4529e1ad7c182a716c033db6dep-99 },
        .{ .hi = 0x1.918a16e46335aae7232494d8p-4, .lo = 0x1.9d1d19046b227370f7cb86bd9e3ep-99 },
        .{ .hi = 0x1.bc84240adabba63b2c5a6e5p-4, .lo = 0x1.97ab879641c50810e3b820ca9aap-100 },
        .{ .hi = 0x1.e72ec117fa5b21cbdb5d9dcp-4, .lo = 0x1.4f902752a1dc5b384b68c4f1e669p-99 },
        .{ .hi = 0x1.08c588cda79e39627bc6fd0cp-3, .lo = -0x1.aad7542b0c4015f8fdff17d7ea79p-99 },
        .{ .hi = 0x1.1dcd197552b7b5ea45430784p-3, .lo = -0x1.a7aa295e08add52f96d8aaf3b8edp-101 },
        .{ .hi = 0x1.32ae9e278ae1a1f51f2c075cp-3, .lo = -0x1.8b459b26ac0ed3b39116e44d50c8p-99 },
        .{ .hi = 0x1.476a9f983f74d3138e941644p-3, .lo = -0x1.27d822a49870762eeaffdcde52bdp-104 },
        .{ .hi = 0x1.5c01a39fbd6879fa00b120ap-3, .lo = 0x1.a2eb74493cf9a8e8966c101ef964p-101 },
        .{ .hi = 0x1.70742d4ef027f29c01cfad78p-3, .lo = -0x1.8495d6ca3b2dcc7941a5df4c8decp-103 },
        .{ .hi = 0x1.84c2bd02f03b2fdd2248ee78p-3, .lo = -0x1.c56a8f0829344b50240232cdb09ep-99 },
        .{ .hi = 0x1.98edd077e70df02face8ca9p-3, .lo = 0x1.72b7f2fcb409899d29e3feaf9c8fp-99 },
        .{ .hi = 0x1.acf5e2db4ec93efe11ecbcp-3, .lo = 0x1.83634b52082beea143f1178aaf62p-99 },
        .{ .hi = 0x1.c0db6cdd94dee40e26d9899cp-3, .lo = 0x1.fde86bd82482b9b4a45aa674cc1bp-100 },
        .{ .hi = 0x1.d49ee4c32596fc8f4b565024p-3, .lo = -0x1.7eaef901f52d2d54011ca95ecca1p-101 },
        .{ .hi = 0x1.e840be74e6a4cc7c9f3d51ep-3, .lo = -0x1.03c7c0d8554c2c17f944fa1f93cfp-99 },
        .{ .hi = 0x1.fbc16b902680a23a8d998a78p-3, .lo = 0x1.3bcd7c933d5bb6b52a41ad567d8ep-101 },
        .{ .hi = 0x1.0790adbb030096f031a699d6p-2, .lo = -0x1.748a4ccf5e3dadf04bd0ff35f885p-99 },
        .{ .hi = 0x1.11307dad30b75cb09705a796p-2, .lo = -0x1.6c580f988c64f00bd800ed9b9d24p-100 },
        .{ .hi = 0x1.1ac05b291f070528c7386df8p-2, .lo = 0x1.94340c3b639a4e5a59fded67fcb7p-99 },
        .{ .hi = 0x1.24407ab0e07398245b94ba44p-2, .lo = 0x1.8077f77a0f4353b19301384099dap-99 },
        .{ .hi = 0x1.2db10fc4d9aaf6f137a3d8c6p-2, .lo = 0x1.e79b8ee38b380b8be44e090558d7p-99 },
        .{ .hi = 0x1.37124cea4cdecd991336c96p-2, .lo = 0x1.fb9186e41376f4612d4b0b9a507dp-100 },
        .{ .hi = 0x1.406463b1b044975b2f344252p-2, .lo = 0x1.9a92f79c803c5151cb25af73b143p-101 },
        .{ .hi = 0x1.49a784bcd1b8afe492bf6ff4p-2, .lo = 0x1.b5fb699b2d8abfc6f675a9d236d6p-99 },
        .{ .hi = 0x1.52dbdfc4c96b37dcf60e61fcp-2, .lo = 0x1.36a5977bbf78792b6a99ccb74cd5p-99 },
        .{ .hi = 0x1.5c01a39fbd6879fa00b120ap-2, .lo = 0x1.a2eb74493cf9a8e8966c101ef964p-100 },
        .{ .hi = 0x1.6518fe4677ba6e52278edc8ap-2, .lo = -0x1.6778b4ba074a8ce60972502c7262p-102 },
        .{ .hi = 0x1.6e221cd9d0cde578d520b45p-2, .lo = -0x1.1f87779b03b7d7e6bd0493f2e147p-99 },
        .{ .hi = 0x1.771d2ba7efb3be46fecd5122p-2, .lo = 0x1.29ff1c3c9184a53c236eed64d17ep-100 },
        .{ .hi = 0x1.800a563161c5432aeb609f4ep-2, .lo = -0x1.0a6ee4f4272036db2b8f6963d1c4p-103 },
        .{ .hi = 0x1.88e9c72e0b225a4b664a4c8ep-2, .lo = -0x1.59153bc13892380cd03989062763p-100 },
        .{ .hi = 0x1.91bba891f1708b4b2b5056b8p-2, .lo = 0x1.a7156185dba8beba3cb180b37bbbp-100 },
        .{ .hi = 0x1.9a802391e232f34bb6d0e43ap-2, .lo = -0x1.67caee1e30b7c2d6ff9893868aa6p-99 },
        .{ .hi = 0x1.a33760a7f60509d7c40d797ap-2, .lo = -0x1.3a4e0233ff8ac31bd7b2cb5c0041p-102 },
        .{ .hi = 0x1.abe18797f1f48e1a4725558cp-2, .lo = 0x1.6f5c786e3d2aafcee056debabb79p-100 },
        .{ .hi = 0x1.b47ebf73882a0a4146ef8fd8p-2, .lo = 0x1.44f1d5b8a5402f72138cbfe19e49p-99 },
        .{ .hi = 0x1.bd0f2e9e79030ab442ce3202p-2, .lo = -0x1.d27aeb2ddd02924cf83def704a7bp-99 },
        .{ .hi = 0x1.c592fad295b567e7ee54aefp-2, .lo = -0x1.99e7587ea99e677177c285c32088p-99 },
        .{ .hi = 0x1.ce0a4923a587cc95d0a2ee7ap-2, .lo = 0x1.6482ae04295539bf0ed23f498b8ap-104 },
        .{ .hi = 0x1.d6753e032ea0efe3ebe19906p-2, .lo = -0x1.55594a060c67a245f78bb523ad43p-99 },
        .{ .hi = 0x1.ded3fd442364c4ebb196116p-2, .lo = -0x1.df9689b34ee848b0b7818878492cp-99 },
        .{ .hi = 0x1.e726aa1e754d20c519e12f48p-2, .lo = -0x1.dd99950bae450ac5754344a16faep-99 },
        .{ .hi = 0x1.ef6d67328e2207d1e01a839p-2, .lo = 0x1.04907f9ccddb53ed88c47c7d794cp-100 },
        .{ .hi = 0x1.f7a8568cb06cece193180046p-2, .lo = -0x1.e149b9528336d5fee3ef52260ad1p-99 },
        .{ .hi = 0x1.ffd799a83ff9ab9cc7f342f8p-2, .lo = 0x1.70c458bda55b08c8c8668867736bp-99 },
        .{ .hi = 0x1.03fda8b97997f33943464056p-1, .lo = 0x1.eb47cb2aadd948d48bbef492995ep-99 },
        .{ .hi = 0x1.0809cf27f703d525b3c1d158p-1, .lo = 0x1.f51e170ccb0f7761e5ff9b93854ep-100 },
        .{ .hi = 0x1.0c10500d63aa6588257529b6p-1, .lo = 0x1.2ef0aa83f2869dd6be1d1cc2dc47p-100 },
        .{ .hi = 0x1.10113b153c8ea7b1cddae6fbp-1, .lo = -0x1.8d4296259492a32f8b327d46339p-100 },
        .{ .hi = 0x1.140c9faa1e5439e15a52a316p-1, .lo = 0x1.29611295daec3b07655c599a50e7p-103 },
        .{ .hi = 0x1.18028cf72976a4eb8e97d145p-1, .lo = 0x1.9ac318308c388b1f2e108f3d37bep-100 },
        .{ .hi = 0x1.1bf311e95d00de3b513a9dcdp-1, .lo = -0x1.3c8ff1c1539554d1f10759819adp-100 },
        .{ .hi = 0x1.1fde3d30e812642415d47384p-1, .lo = 0x1.3c458dd53d12c99743f3c4617c37p-99 },
        .{ .hi = 0x1.23c41d42727c8080ecc61a99p-1, .lo = -0x1.fb113740031e528bbef9ead829c7p-99 },
        .{ .hi = 0x1.27a4c0585cbf805784ee0e3bp-1, .lo = -0x1.60c515c0f4b1772f673312a17eep-101 },
        .{ .hi = 0x1.2b803473f7ad0f3f40162414p-1, .lo = 0x1.a2eb74493cf9a8e8966c101ef964p-102 },
        .{ .hi = 0x1.2f56875eb3f2614278cd1699p-1, .lo = 0x1.88c5d320344f129c318704371e3dp-100 },
        .{ .hi = 0x1.3327c6ab49ca6c86b9205fa4p-1, .lo = 0x1.1010939e6edc060bf80459dd880dp-100 },
        .{ .hi = 0x1.36f3ffb6d9162404772a151dp-1, .lo = -0x1.93193dd58663d90eed123bda5ea2p-100 },
        .{ .hi = 0x1.3abb3faa02166cccab240e9p-1, .lo = 0x1.3e5a84738c6a548017167cabbd62p-99 },
        .{ .hi = 0x1.3e7d9379f70166ae2a7ada55p-1, .lo = 0x1.6369ad81817bfeddee4a96320fd3p-100 },
        .{ .hi = 0x1.423b07e986aa9670761d14abp-1, .lo = -0x1.d93cd9e77a527017a3e16237ddd4p-100 },
        .{ .hi = 0x1.45f3a98a20738a4d7ffe0267p-1, .lo = 0x1.75541c775be89f0841ae8379c6adp-100 },
        .{ .hi = 0x1.49a784bcd1b8afe492bf6ff5p-1, .lo = -0x1.2812599349d500e4262958b724aap-100 },
        .{ .hi = 0x1.4d56a5b33cec44a6deff9987p-1, .lo = 0x1.fad1e37de08f5e02036d27593a4p-100 },
        .{ .hi = 0x1.510118708a8f8dde949378b2p-1, .lo = 0x1.348f1454e8c939a60252b34c6c66p-100 },
        .{ .hi = 0x1.54a6e8ca5438db1b0ca63aacp-1, .lo = -0x1.2f1784ce0b08724e7f04c9712103p-99 },
        .{ .hi = 0x1.5848226989d33c38d8bd28d7p-1, .lo = -0x1.a8e7bb5885dce30d5e9e8139d7b1p-99 },
        .{ .hi = 0x1.5be4d0cb51434aaeb3f01222p-1, .lo = 0x1.2ce7e40053a5cfc072e22bbeab1dp-100 },
        .{ .hi = 0x1.5f7cff41e09aeb8cb1ac05cdp-1, .lo = -0x1.4fb2c4a0dc9f7b2e29701f76805bp-100 },
        .{ .hi = 0x1.6310b8f553048406a5a171dep-1, .lo = 0x1.003332544881b92584a992692c7dp-99 },
        .{ .hi = 0x1.66a008e4788cbcd2edb4390ep-1, .lo = 0x1.4c1a88f0e7a41e948033b63cbaadp-99 },
        .{ .hi = 0x1.6a2af9e5a0f0a08099572f21p-1, .lo = -0x1.0665eae13d10b498acfb49ce0dep-99 },
        .{ .hi = 0x1.6db196a761949d97df07e357p-1, .lo = -0x1.7679e5a1e4a0e0dbeb3195d40b4dp-99 },
        .{ .hi = 0x1.7133e9b156c7be5167fbdc81p-1, .lo = 0x1.b935e716c7cb214a0b718fc30587p-100 },
        .{ .hi = 0x1.74b1fd64e0753c6e5783fd15p-1, .lo = 0x1.923a7aefc37ef9baffdf4ec86923p-102 },
        .{ .hi = 0x1.782bdbfdda6577bc87e125ebp-1, .lo = -0x1.56e82c9d846f9e967e496249719bp-99 },
        .{ .hi = 0x1.7ba18f93502e409eab77f21ap-1, .lo = -0x1.c097ea4900b7ca9ea124a56a0c75p-100 },
        .{ .hi = 0x1.7f1322182cf15d12ecd77fe7p-1, .lo = -0x1.0512c0ac2d3510c6f5fd964c2ae2p-99 },
        .{ .hi = 0x1.82809d5be7072dbdc0426c3cp-1, .lo = 0x1.3a309736edbb3eae70d10c173b0bp-100 },
        .{ .hi = 0x1.85ea0b0b27b261086fce864ap-1, .lo = 0x1.f5979367f112e34dbc4e07ae924cp-101 },
        .{ .hi = 0x1.894f74b06ef8b406ea2c7d92p-1, .lo = -0x1.54ede83a0018a21469a1f11911aep-99 },
        .{ .hi = 0x1.8cb0e3b4b3bbdb3688a85fb2p-1, .lo = -0x1.910d207f019516331134b0c9d172p-99 },
        .{ .hi = 0x1.900e6160002ccfe43f50847dp-1, .lo = 0x1.82887e54848c7603fba7d2ba264ap-101 },
        .{ .hi = 0x1.9367f6da0ab2e9cc865b3dd1p-1, .lo = -0x1.225541e18baff32be2709a01f861p-100 },
        .{ .hi = 0x1.96bdad2acb5f5efec4915314p-1, .lo = 0x1.b7c0b9db2fcb23be56be998e8e8fp-99 },
        .{ .hi = 0x1.9a0f8d3b0e04fde95734abd3p-1, .lo = -0x1.9f19ce27d2dca3979bbb0ca9365fp-104 },
        .{ .hi = 0x1.9d5d9fd5010b366655920748p-1, .lo = 0x1.3e5a84738c6a548017167cabbd62p-100 },
        .{ .hi = 0x1.a0a7eda4c112ce6312ebb81dp-1, .lo = -0x1.5a727dbaad60b1bf6bcd429e9fdfp-102 },
        .{ .hi = 0x1.a3ee7f38e181ed0798d1aa21p-1, .lo = 0x1.a51584c9dc5627ac1ab989c42834p-99 },
        .{ .hi = 0x1.a7315d02f20c7bd560a3fee1p-1, .lo = -0x1.dacbac02cace034400340f2319ddp-99 },
        .{ .hi = 0x1.aa708f58014d37cde37c86b2p-1, .lo = 0x1.06a19b5bedec4594babbdab2fd2p-100 },
        .{ .hi = 0x1.adac1e711c832d1562d61af7p-1, .lo = 0x1.fbfa94970bb9fab077c80ac91e28p-100 },
        .{ .hi = 0x1.b0e4126bcc86bd7a6ed4e1b1p-1, .lo = -0x1.b28c4122d931f14daa7bc7cc5b07p-99 },
        .{ .hi = 0x1.b418734a9008bd978b98f7dfp-1, .lo = -0x1.039d32863d2685d1b265e993decbp-100 },
        .{ .hi = 0x1.b74948f5532da4b4b7143364p-1, .lo = -0x1.ce44c707d13d9c8e8a9007c6ffb4p-99 },
        .{ .hi = 0x1.ba769b39e49640ef87ede14bp-1, .lo = -0x1.735f3571b2e44add58e787eb935ep-101 },
        .{ .hi = 0x1.bda071cc67e6db516de08136p-1, .lo = 0x1.b4d5660336e288cea5ceba447906p-99 },
        .{ .hi = 0x1.c0c6d447c5dd362d9a9a55c7p-1, .lo = 0x1.17b370ba83c0155dfdf1fd11696ep-99 },
        .{ .hi = 0x1.c3e9ca2e1a05533698b4e49bp-1, .lo = 0x1.ec0c07c38978823235b0f583d7a7p-99 },
        .{ .hi = 0x1.c7095ae91e1c760bc9b188c4p-1, .lo = 0x1.322631fb315aaf4da97307d1076bp-99 },
        .{ .hi = 0x1.ca258dca9331635fee390c0bp-1, .lo = -0x1.3e17e7a7e746edea65e0c4e7d82dp-99 },
        .{ .hi = 0x1.cd3e6a0ca8906c243749114cp-1, .lo = 0x1.2bbae931e8daa670e214b298ab12p-99 },
        .{ .hi = 0x1.d053f6d2608967318975dc0ep-1, .lo = 0x1.ea58d8245529f4e409432bd61602p-99 },
        .{ .hi = 0x1.d3663b27f31d5297837adb4bp-1, .lo = -0x1.38daa2d672ec54842668a312854dp-100 },
        .{ .hi = 0x1.d6753e032ea0efe3ebe19905p-1, .lo = 0x1.554d6bf3e730bb7410e895b8a57ap-99 },
        .{ .hi = 0x1.d9810643d6614c3c406eb464p-1, .lo = 0x1.05d328adc61c09915e038a135bdfp-99 },
        .{ .hi = 0x1.dc899ab3ff56c5e673abad44p-1, .lo = 0x1.8c6339fa7bd10d27c064978bc6f5p-100 },
        .{ .hi = 0x1.df8f02086af2c4bef483c68bp-1, .lo = -0x1.0baa11f1460aebb8f273d9820bc8p-99 },
        .{ .hi = 0x1.e29142e0e01401fbaaa67e3cp-1, .lo = -0x1.d6541223b8314593546e23de0435p-100 },
        .{ .hi = 0x1.e59063c8822ce561911a9bacp-1, .lo = 0x1.9b0de815b6fb0c41cac421925a11p-99 },
        .{ .hi = 0x1.e88c6b3626a72aa21a3c7f02p-1, .lo = -0x1.0e3aeafe4f838b64e3bde351d0f1p-102 },
        .{ .hi = 0x1.eb855f8ca88fb0d4b5c673bbp-1, .lo = 0x1.1db401cf29698d7b00a45b6d1082p-102 },
        .{ .hi = 0x1.ee7b471b3a9507d6dc1f27efp-1, .lo = 0x1.21f23cd188a03f54e360fd76a481p-99 },
        .{ .hi = 0x1.f16e281db76303b21928c216p-1, .lo = -0x1.2854f795db443461c5e7233e545fp-102 },
        .{ .hi = 0x1.f45e08bcf06554e4d5be4f7p-1, .lo = 0x1.07e81f4c1573947a3126425d9d0ap-99 },
        .{ .hi = 0x1.f74aef0efafadd7a1b65f639p-1, .lo = -0x1.7bc1e9882648a6b530fa4d847e3fp-100 },
        .{ .hi = 0x1.fa34e1177c23362928b9ed75p-1, .lo = -0x1.856dc2b529ad698bfda1e41b89bdp-101 },
        .{ .hi = 0x1.fd1be4c7f2af942b221ce0d1p-1, .lo = 0x1.a275c854f5bb9732fae5130be48bp-104 },
        .{ .hi = 0x1p0, .lo = 0 },
    };
    return impl.proc1(.{ .poly = poly, .tab = tab }, x);
}

pub fn log2l(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return log2(x),
        80 => return __log2x(x),
        128 => return log2q(x),
        else => @compileError("unreachable"),
    }
}

test "log2f() special" {
    try expectEqual(log2f(0.0), -math.inf(f32));
    try expectEqual(log2f(-0.0), -math.inf(f32));
    try expect(math.isPositiveZero(log2f(1.0)));
    try expectEqual(log2f(2.0), 1.0);
    try expectEqual(log2f(math.inf(f32)), math.inf(f32));
    try expect(math.isNan(log2f(-1.0)));
    try expect(math.isNan(log2f(-math.inf(f32))));
    try expect(math.isNan(log2f(math.nan(f32))));
    try expect(math.isNan(log2f(math.snan(f32))));
}

test "log2f() sanity" {
    try expect(math.isNan(log2f(-0x1.0223a0p+3)));
    try expectEqual(log2f(0x1.161868p+2), 0x1.0f49acp+1);
    try expect(math.isNan(log2f(-0x1.0c34b4p+3)));
    try expect(math.isNan(log2f(-0x1.a206f0p+2)));
    try expectEqual(log2f(0x1.288bbcp+3), 0x1.9b2676p+1);
    try expectEqual(log2f(0x1.52efd0p-1), -0x1.30b494p-1); // Disagrees with GCC in last bit
    try expect(math.isNan(log2f(-0x1.a05cc8p-2)));
    try expectEqual(log2f(0x1.1f9efap-1), -0x1.a9f89ap-1);
    try expectEqual(log2f(0x1.8c5db0p-1), -0x1.7a2c96p-2);
    try expect(math.isNan(log2f(-0x1.5b86eap-1)));
}

test "log2f() boundary" {
    try expectEqual(log2f(0x1.fffffep+127), 0x1p+7); // Max input value
    try expectEqual(log2f(0x1p-149), -0x1.2ap+7); // Min positive input value
    try expect(math.isNan(log2f(-0x1p-149))); // Min negative input value
    try expectEqual(log2f(0x1.000002p+0), 0x1.715474p-23); // Last value before result reaches +0
    try expectEqual(log2f(0x1.fffffep-1), -0x1.715478p-24); // Last value before result reaches -0
    try expectEqual(log2f(0x1p-126), -0x1.f8p+6); // First subnormal
    try expect(math.isNan(log2f(-0x1p-126))); // First negative subnormal

}

test "log2() special" {
    try expectEqual(log2(0.0), -math.inf(f64));
    try expectEqual(log2(-0.0), -math.inf(f64));
    try expect(math.isPositiveZero(log2(1.0)));
    try expectEqual(log2(2.0), 1.0);
    try expectEqual(log2(math.inf(f64)), math.inf(f64));
    try expect(math.isNan(log2(-1.0)));
    try expect(math.isNan(log2(-math.inf(f64))));
    try expect(math.isNan(log2(math.nan(f64))));
    try expect(math.isNan(log2(math.snan(f64))));
}

test "log2() sanity" {
    try expect(math.isNan(log2(-0x1.02239f3c6a8f1p+3)));
    try expectEqual(log2(0x1.161868e18bc67p+2), 0x1.0f49ac3838580p+1);
    try expect(math.isNan(log2(-0x1.0c34b3e01e6e7p+3)));
    try expect(math.isNan(log2(-0x1.a206f0a19dcc4p+2)));
    try expectEqual(log2(0x1.288bbb0d6a1e6p+3), 0x1.9b26760c2a57ep+1);
    try expectEqual(log2(0x1.52efd0cd80497p-1), -0x1.30b490ef684c7p-1);
    try expect(math.isNan(log2(-0x1.a05cc754481d1p-2)));
    try expectEqual(log2(0x1.1f9ef934745cbp-1), -0x1.a9f89b5f5acb8p-1);
    try expectEqual(log2(0x1.8c5db097f7442p-1), -0x1.7a2c947173f06p-2);
    try expect(math.isNan(log2(-0x1.5b86ea8118a0ep-1)));
}

test "log2() boundary" {
    try expectEqual(log2(0x1.fffffffffffffp+1023), 0x1p+10); // Max input value
    try expectEqual(log2(0x1p-1074), -0x1.0c8p+10); // Min positive input value
    try expect(math.isNan(log2(-0x1p-1074))); // Min negative input value
    try expectEqual(log2(0x1.0000000000001p+0), 0x1.71547652b82fdp-52); // Last value before result reaches +0
    try expectEqual(log2(0x1.fffffffffffffp-1), -0x1.71547652b82fep-53); // Last value before result reaches -0
    try expectEqual(log2(0x1p-1022), -0x1.ffp+9); // First subnormal
    try expect(math.isNan(log2(-0x1p-1022))); // First negative subnormal
}

test "log2q() special" {
    try expectEqual(log2q(0.0), -math.inf(f128));
    try expectEqual(log2q(-0.0), -math.inf(f128));
    try expect(math.isPositiveZero(log2q(1.0)));
    try expectEqual(log2q(2.0), 1.0);
    try expectEqual(log2q(math.inf(f128)), math.inf(f128));
    try expect(math.isNan(log2q(-1.0)));
    try expect(math.isNan(log2q(-math.inf(f128))));
    try expect(math.isNan(log2q(math.nan(f128))));
    try expect(math.isNan(log2q(math.snan(f128))));
}

test "log2q() boundary" {
    try expectEqual(log2q(0x1.ffffffffffffffffffffffffffffp16383), 0x1p14); // Max input value
    try expectEqual(log2q(0x1p-16494), -0x1.01b8p14); // Min positive input value
    try expect(math.isNan(log2q(-0x1p-16494))); // Min negative input value
    try expectEqual(log2q(0x1.0000000000000000000000000001p0), 0x1.71547652b82fe1777d0ffda0d23ap-112); // Last value before result reaches +0
    try expectEqual(log2q(0x1.ffffffffffffffffffffffffffffp-1), -0x1.71547652b82fe1777d0ffda0d23bp-113); // Last value before result reaches -0
    try expectEqual(log2q(0x1p-16382), -0x1.fffp13); // First subnormal
    try expect(math.isNan(log2q(-0x1p-16382))); // First negative subnormal
}

test "log2q() sanity" {
    try expectEqual(log2q(8.0965013884643408203125e11), 3.955850767769801288865582596068254e1);
    try expectEqual(log2q(8.346531942223744e15), 5.28900982928636641107356163006646e1);
    try expectEqual(log2q(9.707809913413123613777865431464565e-20), -6.315941603809020445822192336703809e1);
    try expectEqual(log2q(1.9179565888043380306021427656243352e-24), -7.878670421065570557450089031998522e1);
    try expectEqual(log2q(2.5260048200126556877075044745936796e-25), -8.17113449801679676275805009400338e1);
    try expectEqual(log2q(3.1170134002568967640399932861328125e7), 2.489366102143423848582774267206741e1);
    // test near 1
    try expectEqual(log2q(1.026586845186097528392910049888087e0), 3.7855678902522753591699367969189364e-2);
    try expectEqual(log2q(1.0005582850578053877743656130405725e0), 8.052103367568488432896147152682078e-4);
    try expectEqual(log2q(1.0370174103591254835765589348284266e0), 5.244011558596899945639244281954306e-2);
    try expectEqual(log2q(1.0429996503525671713075162472250667e0), 6.073867421942172944687194557176633e-2);
    try expectEqual(log2q(1.0383384027961064621892184334228659e0), 5.4276706191956281784022630732940314e-2);
}
