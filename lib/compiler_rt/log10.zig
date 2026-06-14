//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/log10f.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/log10.c

const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const maxInt = std.math.maxInt;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__log10h, "__log10h");
    symbol(&log10f, "log10f");
    symbol(&log10, "log10");
    symbol(&__log10x, "__log10x");
    if (compiler_rt.want_ppc_abi) {
        symbol(&log10q, "log10f128");
    }
    symbol(&log10q, "log10q");
    symbol(&log10l, "log10l");
}

pub fn __log10h(a: f16) callconv(.c) f16 {
    // TODO: more efficient implementation
    return @floatCast(log10f(a));
}

pub fn log10f(x_: f32) callconv(.c) f32 {
    const ivln10hi: f32 = 4.3432617188e-01;
    const ivln10lo: f32 = -3.1689971365e-05;
    const log10_2hi: f32 = 3.0102920532e-01;
    const log10_2lo: f32 = 7.9034151668e-07;
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
    const dk: f32 = @floatFromInt(k);

    return dk * log10_2lo + (lo + hi) * ivln10lo + lo * ivln10hi + hi * ivln10hi + dk * log10_2hi;
}

pub fn log10(x_: f64) callconv(.c) f64 {
    const ivln10hi: f64 = 4.34294481878168880939e-01;
    const ivln10lo: f64 = 2.50829467116452752298e-11;
    const log10_2hi: f64 = 3.01029995663611771306e-01;
    const log10_2lo: f64 = 3.69423907715893078616e-13;
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
    var hii: u64 = @bitCast(hi);
    hii &= @as(u64, maxInt(u64)) << 32;
    hi = @bitCast(hii);
    const lo = f - hi - hfsq + s * (hfsq + R);

    // val_hi + val_lo ~ log10(1 + f) + k * log10(2)
    var val_hi = hi * ivln10hi;
    const dk: f64 = @floatFromInt(k);
    const y = dk * log10_2hi;
    var val_lo = dk * log10_2lo + (lo + hi) * ivln10lo + lo * ivln10hi;

    // Extra precision multiplication
    const ww = y + val_hi;
    val_lo += (y - ww) + val_hi;
    val_hi = ww;

    return val_lo + val_hi;
}

pub fn __log10x(a: f80) callconv(.c) f80 {
    // TODO: more efficient implementation
    return @floatCast(log10q(a));
}

/// Implementation of "Table-driven implementation of the logarithm function in IEEE floating-point arithmetic"
/// by PTP Tang in ACM Transactions on Mathematical Software (TOMS), 1990
///
/// https://dl.acm.org/doi/pdf/10.1145/98267.98294
///
/// Adapted to work for f128 and base 10 by Christophe Delage.
///
/// Accuracy on 100 million random numbers in [0, inf) (exponent uniformly random)
/// <= 0.5 ulp: 99.99%, worst case 0.591 <= ulp
///
/// Accuracy on 10 million random numbers near x = 1 (testing the proc2 case):
/// <= 0.5 ulp: 99.96%, worst case <= 0.565 ulp
pub fn log10q(x: f128) callconv(.c) f128 {
    const impl = @import("log_f128.zig");

    if (impl.specialCases(x)) |y|
        return y;

    if (impl.Proc2.lo < x and x < impl.Proc2.hi) {
        // Polynomial approximation of log10((1 + u / 2) / (1 - u / 2))
        // in [2 * a / (2 + a), 2 * b / (2 + b)]
        // where a = exp(-1 / 16) - 1 and b = exp(1 / 16) - 1
        const poly: impl.Proc2.Poly = .{
            .b1_hi = 0x1.bcb7b1526e50ep-2,
            .b1_lo = 0x1.95355baaafad33dc323ee3460246p-57,
            .b3 = 3.619120682527098563759407657638483e-2,
            .b5 = 5.428681023790647845639111475407614e-3,
            .b7 = 9.694073256769014010070232880860484e-4,
            .b9 = 1.8849586888161971679466375197398104e-4,
            .b11 = 3.855597318033137224139238937796866e-5,
            .b13 = 8.156071249646061672592451832809541e-6,
            .b15 = 1.7671487851436387503930903139882346e-6,
            .b17 = 3.898090687230025454479255130305971e-7,
            .b19 = 8.757839894876785986064901881670424e-8,
        };
        return impl.proc2(.{ .poly = poly }, x);
    }

    // Polynomial approximation of log10(1 + 2 * u / (2 - u))
    // in [-(2 * fmax) / (2 + fmax), (2 * fmax) / (2 - fmax)]
    // where fmax = 0.5 / size
    const poly: impl.Proc1.Poly = .{
        .a1 = 0.4342944819032518276511289189166051,
        .a3 = 3.619120682527098563759407657655348e-2,
        .a5 = 5.428681023790647845638954444458386e-3,
        .a7 = 9.694073256769014481942040422515466e-4,
        .a9 = 1.884958688754320118955531917460363e-4,
        .a11 = 3.8556341504143175800053507804546873e-5,
    };

    // log1p_tab[j].hi = 2^-n * round-to-integer(2^n * l)
    // log1p_tab[j].lo = round-to-nearest-f128(l - log1p_tab[j].hi)
    // where n = 97 and l = log10(1 + j / size)
    const tab = [impl.size + 1]impl.Proc1.HiLo{
        .{ .hi = 0, .lo = 0 },
        .{ .hi = 0x1.bafd47221ed2665c1ba949p-9, .lo = -0x1.eb6f20a90ad48515635f3b8a1d22p-104 },
        .{ .hi = 0x1.b9476a4fcd10ed89b5a417p-8, .lo = 0x1.0b153c94bfd2527c3dce31e5e226p-100 },
        .{ .hi = 0x1.49b0851443683ce1bf0b26p-7, .lo = -0x1.a16199f2b1be9a7a84e03b9c38c2p-99 },
        .{ .hi = 0x1.b5e908eb137900f974ff1b4p-7, .lo = -0x1.6bbc5e42b470cbc0ccc513d93932p-102 },
        .{ .hi = 0x1.10a83a8446c77a1180aaf6p-6, .lo = -0x1.09ecab3c0cf83110cf07e44c289fp-101 },
        .{ .hi = 0x1.45f4f5acb8be07769e25e96p-6, .lo = -0x1.0a58d59387d112136c57591afc6cp-99 },
        .{ .hi = 0x1.7adc3df3b1ff81b980714c6p-6, .lo = -0x1.a572fb60daf72fbfab402e472463p-100 },
        .{ .hi = 0x1.af5f92b00e60fa6de0a6da8p-6, .lo = -0x1.8335cd731aa841e5f6959299c961p-100 },
        .{ .hi = 0x1.e3806acbd058f0d79f59da2p-6, .lo = 0x1.9ab1b88f11b4d4ea94e47e000ae6p-102 },
        .{ .hi = 0x1.0ba01a81700002be3a8a48ap-5, .lo = -0x1.792eb9b5df590083e09dc0929a7p-101 },
        .{ .hi = 0x1.25502c0fc314b801dad7dedp-5, .lo = 0x1.197c6c848f1b1ad18fd42fe32cb2p-99 },
        .{ .hi = 0x1.3ed1199a5e425037527d748p-5, .lo = -0x1.c78118e73744326912f10c802895p-100 },
        .{ .hi = 0x1.58238eeb353da7bf5153dfbp-5, .lo = -0x1.9663eec734789fdf5fb0469aa7eep-99 },
        .{ .hi = 0x1.71483427d2a98ce1e11006p-5, .lo = 0x1.c4ea21ef8f4a97aa1e6e70df2d95p-101 },
        .{ .hi = 0x1.8a3fadeb847f393aed3e7b6p-5, .lo = 0x1.098634c8ec2a09971ad607875b6ep-99 },
        .{ .hi = 0x1.a30a9d609efe9c281982d7ep-5, .lo = -0x1.0a32db4c5564f07600c430a0057dp-102 },
        .{ .hi = 0x1.bba9a058dfd841a9796c345p-5, .lo = -0x1.d9dd77e08e9e5f8d9f32d76bef47p-99 },
        .{ .hi = 0x1.d41d5164facb3a0188eb21p-5, .lo = 0x1.0128f682aeb0fa34321a7e97187fp-101 },
        .{ .hi = 0x1.ec6647eb5880847d0188c2dp-5, .lo = -0x1.5afb00d01e071acf1f55342436abp-100 },
        .{ .hi = 0x1.02428c1f08015ea6bc2bc8cp-4, .lo = 0x1.5daed7d59e78eef0247b7ffb956ep-99 },
        .{ .hi = 0x1.0e3d29d81165e62559618f2p-4, .lo = 0x1.9e819128f90a0d3db1dc752ed073p-99 },
        .{ .hi = 0x1.1a23445501815c0cde7a7f08p-4, .lo = -0x1.3b49f3e8b2ed4310435ef8820defp-99 },
        .{ .hi = 0x1.25f5215eb5949df2a5fb46b8p-4, .lo = 0x1.6f0f6ab32f3e61f26e9b3ac1bf9cp-101 },
        .{ .hi = 0x1.31b3055c4711801b420b9b2p-4, .lo = 0x1.76e9002c845c3b127df25ba8db5bp-103 },
        .{ .hi = 0x1.3d5d335c53178caf84eb229p-4, .lo = -0x1.c5c2844630017e0376c69ec1cacp-100 },
        .{ .hi = 0x1.48f3ed1df48fb5e08483b68p-4, .lo = -0x1.7f13d7d43d84e36e36265eaea7bcp-101 },
        .{ .hi = 0x1.5477731973e848790c13ee28p-4, .lo = -0x1.ebaaf88383e9199df31ecf871835p-99 },
        .{ .hi = 0x1.5fe80488af4fca9254c0c638p-4, .lo = 0x1.15b76527b80b8500745623ee81e5p-99 },
        .{ .hi = 0x1.6b45df6f3e2c9590e0d54c78p-4, .lo = -0x1.c495b5c030bcef16e4f8bb12e196p-100 },
        .{ .hi = 0x1.769140a2526fc94ecf23d47p-4, .lo = 0x1.f1841f017a7f6e08b6413b02da64p-101 },
        .{ .hi = 0x1.81ca63d05a449827184d3fd8p-4, .lo = -0x1.073284788f12d4768b8aae8dcde3p-99 },
        .{ .hi = 0x1.8cf183886480c9b28b1f97ep-4, .lo = -0x1.13ada343a03c927e5baecee4f8dap-100 },
        .{ .hi = 0x1.9806d9414a2097207328f768p-4, .lo = -0x1.213231346152bf08d830caaa52cap-100 },
        .{ .hi = 0x1.a30a9d609efe9c281982d7ep-4, .lo = -0x1.0a32db4c5564f07600c430a0057dp-101 },
        .{ .hi = 0x1.adfd07416be06fd76ea69ee8p-4, .lo = -0x1.2f27508996b3721df510fce30125p-101 },
        .{ .hi = 0x1.b8de4d3ab3d97f5dc97fa3e8p-4, .lo = 0x1.94aec3c479e9b616ea5d5f658c63p-99 },
        .{ .hi = 0x1.c3aea4a5c6efe9d1b9bf7b48p-4, .lo = -0x1.6e9cbad44d58c56e8ee013db4727p-100 },
        .{ .hi = 0x1.ce6e41e463da4f487cfe37bp-4, .lo = 0x1.79fd0d2e29710fa19cd9b24bc4a6p-99 },
        .{ .hi = 0x1.d91d5866aa99b8c5ecd85448p-4, .lo = -0x1.bcfa9ad8f74e8fb09b3e2aa21032p-101 },
        .{ .hi = 0x1.e3bc1ab0e19fe3d562a53f08p-4, .lo = -0x1.4e4f16590dfef5c8d025ed120de1p-101 },
        .{ .hi = 0x1.ee4aba610f2047109cc02088p-4, .lo = -0x1.b34ada47053c57f0573b320efb86p-99 },
        .{ .hi = 0x1.f8c968346819084e03494e8p-4, .lo = -0x1.4b71b85b5d726a32292230bf611dp-99 },
        .{ .hi = 0x1.019c2a064b486717a7668388p-3, .lo = -0x1.3af96cd84cdb4bb3072c0b2e5f3fp-104 },
        .{ .hi = 0x1.06cbd67a6c3b65458c50fd8p-3, .lo = 0x1.840d79fca5a0c693c952fc0c42bap-103 },
        .{ .hi = 0x1.0bf3d0937c41c3c2f40d06dcp-3, .lo = -0x1.27324307eb41430185683c421ffap-100 },
        .{ .hi = 0x1.11142f0811356e473b0e4f78p-3, .lo = -0x1.49b0b103367c03cb49c3cc705e75p-99 },
        .{ .hi = 0x1.162d082ac9d0f8e71a2f291p-3, .lo = -0x1.6d975e156bc06273b74fedb290b8p-99 },
        .{ .hi = 0x1.1b3e71ec94f7abbbb3324a1p-3, .lo = -0x1.76cec8d0f75a398c7a1e37848466p-105 },
        .{ .hi = 0x1.204881dee8777552c136a76p-3, .lo = -0x1.267ee5ddb2e8b583793d15630abcp-102 },
        .{ .hi = 0x1.254b4d35e7d3c1d7958ffee8p-3, .lo = -0x1.aa823ea433ce74aca4dce2431023p-100 },
        .{ .hi = 0x1.2a46e8ca7ba29955cdd7839p-3, .lo = -0x1.7eb9688bc0de799a1f9e3e37c715p-99 },
        .{ .hi = 0x1.2f3b691c5a000be34bf081e8p-3, .lo = -0x1.563a5a16b595ce9bdbdfdb0cfa3ap-100 },
        .{ .hi = 0x1.3428e2540096d3b633e04614p-3, .lo = 0x1.f1625e245d85bd4c99622577f507p-99 },
        .{ .hi = 0x1.390f6844a0b83029d5524ca8p-3, .lo = 0x1.c6d3f5f5fe70cb3a00ca5d7bfe39p-100 },
        .{ .hi = 0x1.3def0e6dfdf84ea10095aeacp-3, .lo = -0x1.7ddc01913fed4a930dc964e19d64p-99 },
        .{ .hi = 0x1.42c7e7fe3fc01c5baa84ea84p-3, .lo = -0x1.b57aee43292c7c7883ba343c8c3bp-102 },
        .{ .hi = 0x1.479a07d3b641142ca3a5b05p-3, .lo = 0x1.a7b00c679cb54b61ed4831123201p-100 },
        .{ .hi = 0x1.4c65807e9333821962bd3978p-3, .lo = -0x1.5b7e31a62bc6bddb9dafc48b8763p-99 },
        .{ .hi = 0x1.512a644296c3cb096f47256p-3, .lo = -0x1.8eec43b9a26313b25a668455ed84p-100 },
        .{ .hi = 0x1.55e8c518b10f859bf0375048p-3, .lo = -0x1.6ec79e2221c7ef4d78001cfd92d9p-99 },
        .{ .hi = 0x1.5aa0b4b0988f98f4b7b3557cp-3, .lo = -0x1.d36883ff38b16e03d088056210ap-101 },
        .{ .hi = 0x1.5f52447255c924e6e695998p-3, .lo = -0x1.c9a1067c1f62163817e106dfbadep-101 },
        .{ .hi = 0x1.63fd857fc49baa7c0cd1066cp-3, .lo = 0x1.4bef4a4a1c2f253a333d0447df04p-99 },
        .{ .hi = 0x1.68a288b60b7fc2b622430e54p-3, .lo = 0x1.957d4ee20104a0c9e5e8e2451944p-105 },
        .{ .hi = 0x1.6d415eaf0906a9ea9d132f18p-3, .lo = 0x1.c7e96850691a6d0789a335fcf1f2p-100 },
        .{ .hi = 0x1.71da17c2b7e7fea4e079fe8p-3, .lo = -0x1.47eea7b2200159b5df6c05428549p-101 },
        .{ .hi = 0x1.766cc40889e84a226ff02f0cp-3, .lo = 0x1.17c1270bcfda77828cfd78f80afp-100 },
        .{ .hi = 0x1.7af97358b9e03ccb5c44891p-3, .lo = -0x1.0bc25f85f8a5b9ab4ff4e0ea0c82p-100 },
        .{ .hi = 0x1.7f80354d9529f92f3616977cp-3, .lo = 0x1.c73d68ec26da004f63fb3e4ca71dp-99 },
        .{ .hi = 0x1.84011944bcb752c5b9930008p-3, .lo = -0x1.390cb466745037a79007f790960ap-102 },
        .{ .hi = 0x1.887c2e605e1189c603f25d9p-3, .lo = -0x1.3a2bdea0dd3c942f3b7415d59507p-99 },
        .{ .hi = 0x1.8cf183886480c9b28b1f97ep-3, .lo = -0x1.13ada343a03c927e5baecee4f8dap-99 },
        .{ .hi = 0x1.9161276ba29783a4f607cb8p-3, .lo = -0x1.0402e057ffccff9044bfb591e807p-99 },
        .{ .hi = 0x1.95cb2880f45ba6eadb35485p-3, .lo = 0x1.cdd9e9ad6d4f6c05d3a33d86f1a8p-102 },
        .{ .hi = 0x1.9a2f95085a45b927e6003904p-3, .lo = -0x1.7bfe1b2fef4f232ebdb4c1a0e13ep-99 },
        .{ .hi = 0x1.9e8e7b0c0d4be203de57e9a4p-3, .lo = -0x1.7689e2fc0aa01cdfa7664b87a096p-100 },
        .{ .hi = 0x1.a2e7e8618c2d24882a4f9de4p-3, .lo = 0x1.0ad7f222a9cb6cd7bc85f7f30ff5p-99 },
        .{ .hi = 0x1.a73beaaaa22f38e04a37a21cp-3, .lo = 0x1.6fed007694a60b3a89d53c8a6096p-100 },
        .{ .hi = 0x1.ab8a8f56677fc365b0e5a07cp-3, .lo = -0x1.5fd6e4c7bf48b677423f326e48dcp-101 },
        .{ .hi = 0x1.afd3e3a23b6800f54642bb78p-3, .lo = 0x1.3d53b5cccabc35925c064d8b96fap-99 },
        .{ .hi = 0x1.b417f49ab8806bc9543817ap-3, .lo = 0x1.19354df84685acaf5f6acdc7ba41p-103 },
        .{ .hi = 0x1.b856cf1ca31056c3f6e26b74p-3, .lo = -0x1.bad52e70273c0d62c3c1c56dffcbp-100 },
        .{ .hi = 0x1.bc907fd5d1c4069339ff22ep-3, .lo = 0x1.55d384963ee98afc3078d3044017p-99 },
        .{ .hi = 0x1.c0c5134610e267bfa808f848p-3, .lo = -0x1.bf2c67a6f8c447c947b509e1719ep-100 },
        .{ .hi = 0x1.c4f495c0002a25ee9a870fd4p-3, .lo = 0x1.de41f6ddaf5ae1b6bcccff037f29p-101 },
        .{ .hi = 0x1.c91f1369eb7c9ad8af7db3a4p-3, .lo = -0x1.75624a957be051fcc1561cb35d19p-101 },
        .{ .hi = 0x1.cd44983e9e7bca1ed1e0c97p-3, .lo = -0x1.c657e8081710f357c508dec6e106p-101 },
        .{ .hi = 0x1.d165300e333f69c028a3c44cp-3, .lo = -0x1.af0662e02a88b8b9880e28aec4a9p-103 },
        .{ .hi = 0x1.d580e67edc43ccfa0daf2304p-3, .lo = -0x1.8dcb9bd2e499dd3f11a0b9bc0a2bp-99 },
        .{ .hi = 0x1.d997c70da9b46857c60d08e4p-3, .lo = -0x1.416b471cfcc11bbf284b644ffe95p-104 },
        .{ .hi = 0x1.dda9dd0f4a329136847dd694p-3, .lo = 0x1.1a80cb70cec14440d0790cbb6a14p-101 },
        .{ .hi = 0x1.e1b733b0c7381094f8c216p-3, .lo = -0x1.1f64198a27f7644abf7fc0a11cfep-100 },
        .{ .hi = 0x1.e5bfd5f83d342043025796c8p-3, .lo = 0x1.eee33c4cf5a0527d82ee10fac926p-101 },
        .{ .hi = 0x1.e9c3cec58f8072098058f2b4p-3, .lo = 0x1.6404cd11267d01734c132384a9d3p-99 },
        .{ .hi = 0x1.edc328d3184af1cba1b7464cp-3, .lo = 0x1.aee952dcd721c2bd1b9abe8a0fc4p-99 },
        .{ .hi = 0x1.f1bdeeb654900d96cd34f7ep-3, .lo = -0x1.5fbba7898678670262ca8d3b731dp-102 },
        .{ .hi = 0x1.f5b42ae08c4070bc91804dd8p-3, .lo = -0x1.34f3fead2ae9308d1bc754f8f98ap-99 },
        .{ .hi = 0x1.f9a5e79f76ac491748bb64p-3, .lo = 0x1.46fc084fcb735851dd511e9ab6fap-99 },
        .{ .hi = 0x1.fd932f1ddb4d5f2e278b32c8p-3, .lo = -0x1.f7fe463a5a2fd566ad5e27e0cd8p-100 },
        .{ .hi = 0x1.00be05b217844161e1a46df2p-2, .lo = 0x1.dc4853e5049d6344f76c943a21abp-103 },
        .{ .hi = 0x1.02b0432c96ff0694c1c8d108p-2, .lo = -0x1.25d66fcf4861577bb9fd14424be7p-101 },
        .{ .hi = 0x1.04a054e13900409a780a5b3ap-2, .lo = -0x1.810c5ed46a87b19c7c9d5bf41be9p-100 },
        .{ .hi = 0x1.068e3fa282e3ced3324274cap-2, .lo = -0x1.65bc02e61d74996197c7d08a5628p-101 },
        .{ .hi = 0x1.087a0832fa7ac4f9ab7853eap-2, .lo = -0x1.2214605e23cb53396213a2d34961p-99 },
        .{ .hi = 0x1.0a63b3456c818f3ddb757cccp-2, .lo = -0x1.10d47a8504490cf7c88c75d66fcp-99 },
        .{ .hi = 0x1.0c4b457d3193d3ffa651b8b8p-2, .lo = 0x1.1c0d5a63400f97839bedc777964ap-99 },
        .{ .hi = 0x1.0e30c36e71a7f53a9ae38e1cp-2, .lo = -0x1.f89e6fc3f1e6388ca5d784700f47p-99 },
        .{ .hi = 0x1.1014319e661bc87f6e8c7fdep-2, .lo = 0x1.6639f4ae29ccf0bc44437859de9bp-106 },
        .{ .hi = 0x1.11f594839a5bd3aec4ea7c46p-2, .lo = 0x1.056df9f7cd47dc0aaa4fe49395fcp-100 },
        .{ .hi = 0x1.13d4f0862b2e167244a4e998p-2, .lo = -0x1.db24b7557c465ba68f4835e8a628p-100 },
        .{ .hi = 0x1.15b24a0004a924955aced3a4p-2, .lo = -0x1.32961e32127f178b4381d107f47dp-99 },
        .{ .hi = 0x1.178da53d1ee013c7b3e96d22p-2, .lo = -0x1.0701b8cc90346d780c7f87d2d01p-100 },
        .{ .hi = 0x1.1967067bb94b7feaa558f2f2p-2, .lo = -0x1.03e52851cf5d1510eac0efac64adp-100 },
        .{ .hi = 0x1.1b3e71ec94f7abbbb3324a1p-2, .lo = -0x1.76cec8d0f75a398c7a1e37848466p-104 },
        .{ .hi = 0x1.1d13ebb32d7f886517823d22p-2, .lo = -0x1.e1b60cbc6aa94cd2c4cb44f767d2p-102 },
        .{ .hi = 0x1.1ee777e5f0dc35268e3c0384p-2, .lo = -0x1.563fb0ec2d3c9a0126193b44884fp-99 },
        .{ .hi = 0x1.20b91a8e761050d250ea2a8p-2, .lo = -0x1.0fb80164cc712614d5d1d7e782aep-99 },
        .{ .hi = 0x1.2288d7a9b2b6413283817024p-2, .lo = 0x1.9b04b90001edc89a11f502eea0c8p-99 },
        .{ .hi = 0x1.2456b3282f78608173a44484p-2, .lo = 0x1.54c245cf9301f94383e5734624afp-99 },
        .{ .hi = 0x1.2622b0ee3b79cee2bf4fc8eap-2, .lo = -0x1.33e1e10119160d49b5ff9aee724ep-99 },
        .{ .hi = 0x1.27ecd4d41eb6752d30611516p-2, .lo = 0x1.80530269b1752224c47155d4d90bp-99 },
        .{ .hi = 0x1.29b522a64b609745e857b1e8p-2, .lo = -0x1.9d8474e5705adbbd898636577548p-99 },
        .{ .hi = 0x1.2b7b9e258e4226bf0485fabp-2, .lo = -0x1.619c76c7c7c5060bbd811063be07p-100 },
        .{ .hi = 0x1.2d404b073e27da5069cad6ecp-2, .lo = -0x1.34f7416aedeeabbc31c75eedbc4dp-101 },
        .{ .hi = 0x1.2f032cf56a5be40baedb9a4ap-2, .lo = -0x1.e454c75d4817c3aa12fdfb2d1cc8p-102 },
        .{ .hi = 0x1.30c4478f0835f6cf717bf672p-2, .lo = 0x1.aeef5062051e012dc44bd3ce1929p-99 },
        .{ .hi = 0x1.32839e681fc6236e91f3dacap-2, .lo = -0x1.451bc31fd56e57af018a8d364cb8p-99 },
        .{ .hi = 0x1.34413509f79fef311f12b358p-2, .lo = 0x1.6f922f04d5a618a87a3e69314bcep-102 },
    };
    return impl.proc1(.{ .poly = poly, .tab = tab }, x);
}

pub fn log10l(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return log10(x),
        80 => return __log10x(x),
        128 => return log10q(x),
        else => @compileError("unreachable"),
    }
}

test "log10f() special" {
    try expectEqual(log10f(0.0), -math.inf(f32));
    try expectEqual(log10f(-0.0), -math.inf(f32));
    try expect(math.isPositiveZero(log10f(1.0)));
    try expectEqual(log10f(10.0), 1.0);
    try expectEqual(log10f(0.1), -1.0);
    try expectEqual(log10f(math.inf(f32)), math.inf(f32));
    try expect(math.isNan(log10f(-1.0)));
    try expect(math.isNan(log10f(-math.inf(f32))));
    try expect(math.isNan(log10f(math.nan(f32))));
    try expect(math.isNan(log10f(math.snan(f32))));
}

test "log10f() sanity" {
    try expect(math.isNan(log10f(-0x1.0223a0p+3)));
    try expectEqual(log10f(0x1.161868p+2), 0x1.46a9bcp-1);
    try expect(math.isNan(log10f(-0x1.0c34b4p+3)));
    try expect(math.isNan(log10f(-0x1.a206f0p+2)));
    try expectEqual(log10f(0x1.288bbcp+3), 0x1.ef1300p-1);
    try expectEqual(log10f(0x1.52efd0p-1), -0x1.6ee6dcp-3); // Disagrees with GCC in last bit
    try expect(math.isNan(log10f(-0x1.a05cc8p-2)));
    try expectEqual(log10f(0x1.1f9efap-1), -0x1.0075ccp-2);
    try expectEqual(log10f(0x1.8c5db0p-1), -0x1.c75df8p-4);
    try expect(math.isNan(log10f(-0x1.5b86eap-1)));
}

test "log10f() boundary" {
    try expectEqual(log10f(0x1.fffffep+127), 0x1.344136p+5); // Max input value
    try expectEqual(log10f(0x1p-149), -0x1.66d3e8p+5); // Min positive input value
    try expect(math.isNan(log10f(-0x1p-149))); // Min negative input value
    try expectEqual(log10f(0x1.000002p+0), 0x1.bcb7b0p-25); // Last value before result reaches +0
    try expectEqual(log10f(0x1.fffffep-1), -0x1.bcb7b2p-26); // Last value before result reaches -0
    try expectEqual(log10f(0x1p-126), -0x1.2f7030p+5); // First subnormal
    try expect(math.isNan(log10f(-0x1p-126))); // First negative subnormal
}

test "log10() special" {
    try expectEqual(log10(0.0), -math.inf(f64));
    try expectEqual(log10(-0.0), -math.inf(f64));
    try expect(math.isPositiveZero(log10(1.0)));
    try expectEqual(log10(10.0), 1.0);
    try expectEqual(log10(0.1), -1.0);
    try expectEqual(log10(math.inf(f64)), math.inf(f64));
    try expect(math.isNan(log10(-1.0)));
    try expect(math.isNan(log10(-math.inf(f64))));
    try expect(math.isNan(log10(math.nan(f64))));
    try expect(math.isNan(log10(math.snan(f64))));
}

test "log10() sanity" {
    try expect(math.isNan(log10(-0x1.02239f3c6a8f1p+3)));
    try expectEqual(log10(0x1.161868e18bc67p+2), 0x1.46a9bd1d2eb87p-1);
    try expect(math.isNan(log10(-0x1.0c34b3e01e6e7p+3)));
    try expect(math.isNan(log10(-0x1.a206f0a19dcc4p+2)));
    try expectEqual(log10(0x1.288bbb0d6a1e6p+3), 0x1.ef12fff994862p-1);
    try expectEqual(log10(0x1.52efd0cd80497p-1), -0x1.6ee6db5a155cbp-3);
    try expect(math.isNan(log10(-0x1.a05cc754481d1p-2)));
    try expectEqual(log10(0x1.1f9ef934745cbp-1), -0x1.0075cda79d321p-2);
    try expectEqual(log10(0x1.8c5db097f7442p-1), -0x1.c75df6442465ap-4);
    try expect(math.isNan(log10(-0x1.5b86ea8118a0ep-1)));
}

test "log10() boundary" {
    try expectEqual(log10(0x1.fffffffffffffp+1023), 0x1.34413509f79ffp+8); // Max input value
    try expectEqual(log10(0x1p-1074), -0x1.434e6420f4374p+8); // Min positive input value
    try expect(math.isNan(log10(-0x1p-1074))); // Min negative input value
    try expectEqual(log10(0x1.0000000000001p+0), 0x1.bcb7b1526e50dp-54); // Last value before result reaches +0
    try expectEqual(log10(0x1.fffffffffffffp-1), -0x1.bcb7b1526e50fp-55); // Last value before result reaches -0
    try expectEqual(log10(0x1p-1022), -0x1.33a7146f72a42p+8); // First subnormal
    try expect(math.isNan(log10(-0x1p-1022))); // First negative subnormal
}

test "log10q() special" {
    try expectEqual(log10q(0.0), -math.inf(f128));
    try expectEqual(log10q(-0.0), -math.inf(f128));
    try expect(math.isPositiveZero(log10q(1.0)));
    try expectEqual(log10q(10.0), 1.0);
    try expectEqual(log10q(0.1), -1.0);
    try expectEqual(log10q(math.inf(f128)), math.inf(f128));
    try expect(math.isNan(log10q(-1.0)));
    try expect(math.isNan(log10q(-math.inf(f128))));
    try expect(math.isNan(log10q(math.nan(f128))));
    try expect(math.isNan(log10q(math.snan(f128))));
}

test "log10q() sanity" {
    try expectEqual(log10q(2.1744503117482705706605762784484114e1949), 1.949337349488073972035715318447419e3);
    try expectEqual(log10q(2.3695331993665660983204066767386505e2150), 2.1503746627979481420243846411400265e3);
    try expectEqual(log10q(1.8071775728314983136779370752110857e612), 6.122570008283284411311428111991705e2);
    try expectEqual(log10q(2.612170297226630737309271722008693e-2629), -2.628582998513179919647069989114319e3);
    try expectEqual(log10q(8.485091636263895897993044621224502e-3748), -3.7470713434630800881474518447042895e3);
    try expectEqual(log10q(4.3668077579803801413736022136116655e-4051), -4.0503598359268068567757367259544416e3);
    try expectEqual(log10q(2.9321353260885285826237030859036923e4830), 4.830467184010313310864606285356782e3);
    try expectEqual(log10q(6.6119754254652455408442826553161645e-1417), -1.416179668769227128601620567685071e3);
    try expectEqual(log10q(5.2459104673488555418645321788108695e4178), 4.178719820874155944446586083585479e3);
    try expectEqual(log10q(7.809812890804996586377267218360886e-418), -4.1710735937091966815220294599598215e2);
    // testing near 1
    try expectEqual(log10q(1.0291437165967803055610652052109798e0), 1.2476026819466393459130418401605807e-2);
    try expectEqual(log10q(1.043095786320424537962914257605007e0), 1.8324191034706598279642145362763252e-2);
    try expectEqual(log10q(9.900264873754467234601150948947179e-1), -4.3531860417287584780652055666513634e-3);
    try expectEqual(log10q(1.038295346547007736348611217636062e0), 1.6320907588397540309035279023485962e-2);
    try expectEqual(log10q(9.821701941230028324703038578036285e-1), -7.813249520562034832371814409278784e-3);
    try expectEqual(log10q(9.593555263530179895381522214847791e-1), -1.8020418356217558657107271163588764e-2);
}

test "log10q() boundary" {
    try expectEqual(log10q(0x1.ffffffffffffffffffffffffffffp16383), 0x1.34413509f79fef311f12b35816f9p12); // Max input value
    try expectEqual(log10q(0x1p-16494), -0x1.3653051d20c18a143b801b7c5661p12); // Min positive input value
    try expect(math.isNan(log10q(-0x1p-16494))); // Min negative input value
    try expectEqual(log10q(0x1.0000000000000000000000000001p0), 0x1.bcb7b1526e50e32a6ab7555f5a67p-114); // Last value before result reaches +0
    try expectEqual(log10q(0x1.ffffffffffffffffffffffffffffp-1), -0x1.bcb7b1526e50e32a6ab7555f5a68p-115); // Last value before result reaches -0
    try expectEqual(log10q(0x1p-16382), -0x1.343793004f503231a589bac27c38p12); // First subnormal
    try expect(math.isNan(log10q(-0x1p-16382))); // First negative subnormal
}
