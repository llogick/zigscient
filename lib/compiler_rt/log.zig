//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/logf.c?h=2d7d05f031e014068a61d3076c6178513395d2ae
//! https://git.musl-libc.org/cgit/musl/tree/src/math/log.c?h=1b76ff0767d01df72f692806ee5adee13c67ef88

const std = @import("std");
const math = std.math;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqRel = std.testing.expectApproxEqRel;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__logh, "__logh");
    symbol(&logf, "logf");
    symbol(&log, "log");
    symbol(&__logx, "__logx");
    if (compiler_rt.want_ppc_abi) {
        symbol(&logq, "logf128");
    }
    symbol(&logq, "logq");
    symbol(&logl, "logl");
}

pub fn __logh(a: f16) callconv(.c) f16 {
    // TODO: more efficient implementation
    return @floatCast(logf(a));
}

pub fn logf(x_: f32) callconv(.c) f32 {
    const ln2_hi: f32 = 6.9313812256e-01;
    const ln2_lo: f32 = 9.0580006145e-06;
    const Lg1: f32 = 0xaaaaaa.0p-24;
    const Lg2: f32 = 0xccce13.0p-25;
    const Lg3: f32 = 0x91e9ee.0p-25;
    const Lg4: f32 = 0xf89e26.0p-26;

    var x = x_;
    var ix: u32 = @bitCast(x);
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

        // subnormal, scale x
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
    const dk: f32 = @floatFromInt(k);

    return s * (hfsq + R) + dk * ln2_lo - hfsq + f + dk * ln2_hi;
}

pub fn log(x: f64) callconv(.c) f64 {
    const poly1 = [_]f64{
        -0x1p-1,
        0x1.5555555555577p-2,
        -0x1.ffffffffffdcbp-3,
        0x1.999999995dd0cp-3,
        -0x1.55555556745a7p-3,
        0x1.24924a344de3p-3,
        -0x1.fffffa4423d65p-4,
        0x1.c7184282ad6cap-4,
        -0x1.999eb43b068ffp-4,
        0x1.78182f7afd085p-4,
        -0x1.5521375d145cdp-4,
    };

    const poly = [_]f64{
        -0x1.0000000000001p-1,
        0x1.555555551305bp-2,
        -0x1.fffffffeb459p-3,
        0x1.999b324f10111p-3,
        -0x1.55575e506c89fp-3,
    };

    const tab = [128]struct { invc: f64, logc: f64 }{
        .{ .invc = 0x1.734f0c3e0de9fp+0, .logc = -0x1.7cc7f79e69000p-2 },
        .{ .invc = 0x1.713786a2ce91fp+0, .logc = -0x1.76feec20d0000p-2 },
        .{ .invc = 0x1.6f26008fab5a0p+0, .logc = -0x1.713e31351e000p-2 },
        .{ .invc = 0x1.6d1a61f138c7dp+0, .logc = -0x1.6b85b38287800p-2 },
        .{ .invc = 0x1.6b1490bc5b4d1p+0, .logc = -0x1.65d5590807800p-2 },
        .{ .invc = 0x1.69147332f0cbap+0, .logc = -0x1.602d076180000p-2 },
        .{ .invc = 0x1.6719f18224223p+0, .logc = -0x1.5a8ca86909000p-2 },
        .{ .invc = 0x1.6524f99a51ed9p+0, .logc = -0x1.54f4356035000p-2 },
        .{ .invc = 0x1.63356aa8f24c4p+0, .logc = -0x1.4f637c36b4000p-2 },
        .{ .invc = 0x1.614b36b9ddc14p+0, .logc = -0x1.49da7fda85000p-2 },
        .{ .invc = 0x1.5f66452c65c4cp+0, .logc = -0x1.445923989a800p-2 },
        .{ .invc = 0x1.5d867b5912c4fp+0, .logc = -0x1.3edf439b0b800p-2 },
        .{ .invc = 0x1.5babccb5b90dep+0, .logc = -0x1.396ce448f7000p-2 },
        .{ .invc = 0x1.59d61f2d91a78p+0, .logc = -0x1.3401e17bda000p-2 },
        .{ .invc = 0x1.5805612465687p+0, .logc = -0x1.2e9e2ef468000p-2 },
        .{ .invc = 0x1.56397cee76bd3p+0, .logc = -0x1.2941b3830e000p-2 },
        .{ .invc = 0x1.54725e2a77f93p+0, .logc = -0x1.23ec58cda8800p-2 },
        .{ .invc = 0x1.52aff42064583p+0, .logc = -0x1.1e9e129279000p-2 },
        .{ .invc = 0x1.50f22dbb2bddfp+0, .logc = -0x1.1956d2b48f800p-2 },
        .{ .invc = 0x1.4f38f4734ded7p+0, .logc = -0x1.141679ab9f800p-2 },
        .{ .invc = 0x1.4d843cfde2840p+0, .logc = -0x1.0edd094ef9800p-2 },
        .{ .invc = 0x1.4bd3ec078a3c8p+0, .logc = -0x1.09aa518db1000p-2 },
        .{ .invc = 0x1.4a27fc3e0258ap+0, .logc = -0x1.047e65263b800p-2 },
        .{ .invc = 0x1.4880524d48434p+0, .logc = -0x1.feb224586f000p-3 },
        .{ .invc = 0x1.46dce1b192d0bp+0, .logc = -0x1.f474a7517b000p-3 },
        .{ .invc = 0x1.453d9d3391854p+0, .logc = -0x1.ea4443d103000p-3 },
        .{ .invc = 0x1.43a2744b4845ap+0, .logc = -0x1.e020d44e9b000p-3 },
        .{ .invc = 0x1.420b54115f8fbp+0, .logc = -0x1.d60a22977f000p-3 },
        .{ .invc = 0x1.40782da3ef4b1p+0, .logc = -0x1.cc00104959000p-3 },
        .{ .invc = 0x1.3ee8f5d57fe8fp+0, .logc = -0x1.c202956891000p-3 },
        .{ .invc = 0x1.3d5d9a00b4ce9p+0, .logc = -0x1.b81178d811000p-3 },
        .{ .invc = 0x1.3bd60c010c12bp+0, .logc = -0x1.ae2c9ccd3d000p-3 },
        .{ .invc = 0x1.3a5242b75dab8p+0, .logc = -0x1.a45402e129000p-3 },
        .{ .invc = 0x1.38d22cd9fd002p+0, .logc = -0x1.9a877681df000p-3 },
        .{ .invc = 0x1.3755bc5847a1cp+0, .logc = -0x1.90c6d69483000p-3 },
        .{ .invc = 0x1.35dce49ad36e2p+0, .logc = -0x1.87120a645c000p-3 },
        .{ .invc = 0x1.34679984dd440p+0, .logc = -0x1.7d68fb4143000p-3 },
        .{ .invc = 0x1.32f5cceffcb24p+0, .logc = -0x1.73cb83c627000p-3 },
        .{ .invc = 0x1.3187775a10d49p+0, .logc = -0x1.6a39a9b376000p-3 },
        .{ .invc = 0x1.301c8373e3990p+0, .logc = -0x1.60b3154b7a000p-3 },
        .{ .invc = 0x1.2eb4ebb95f841p+0, .logc = -0x1.5737d76243000p-3 },
        .{ .invc = 0x1.2d50a0219a9d1p+0, .logc = -0x1.4dc7b8fc23000p-3 },
        .{ .invc = 0x1.2bef9a8b7fd2ap+0, .logc = -0x1.4462c51d20000p-3 },
        .{ .invc = 0x1.2a91c7a0c1babp+0, .logc = -0x1.3b08abc830000p-3 },
        .{ .invc = 0x1.293726014b530p+0, .logc = -0x1.31b996b490000p-3 },
        .{ .invc = 0x1.27dfa5757a1f5p+0, .logc = -0x1.2875490a44000p-3 },
        .{ .invc = 0x1.268b39b1d3bbfp+0, .logc = -0x1.1f3b9f879a000p-3 },
        .{ .invc = 0x1.2539d838ff5bdp+0, .logc = -0x1.160c8252ca000p-3 },
        .{ .invc = 0x1.23eb7aac9083bp+0, .logc = -0x1.0ce7f57f72000p-3 },
        .{ .invc = 0x1.22a012ba940b6p+0, .logc = -0x1.03cdc49fea000p-3 },
        .{ .invc = 0x1.2157996cc4132p+0, .logc = -0x1.f57bdbc4b8000p-4 },
        .{ .invc = 0x1.201201dd2fc9bp+0, .logc = -0x1.e370896404000p-4 },
        .{ .invc = 0x1.1ecf4494d480bp+0, .logc = -0x1.d17983ef94000p-4 },
        .{ .invc = 0x1.1d8f5528f6569p+0, .logc = -0x1.bf9674ed8a000p-4 },
        .{ .invc = 0x1.1c52311577e7cp+0, .logc = -0x1.adc79202f6000p-4 },
        .{ .invc = 0x1.1b17c74cb26e9p+0, .logc = -0x1.9c0c3e7288000p-4 },
        .{ .invc = 0x1.19e010c2c1ab6p+0, .logc = -0x1.8a646b372c000p-4 },
        .{ .invc = 0x1.18ab07bb670bdp+0, .logc = -0x1.78d01b3ac0000p-4 },
        .{ .invc = 0x1.1778a25efbcb6p+0, .logc = -0x1.674f145380000p-4 },
        .{ .invc = 0x1.1648d354c31dap+0, .logc = -0x1.55e0e6d878000p-4 },
        .{ .invc = 0x1.151b990275fddp+0, .logc = -0x1.4485cdea1e000p-4 },
        .{ .invc = 0x1.13f0ea432d24cp+0, .logc = -0x1.333d94d6aa000p-4 },
        .{ .invc = 0x1.12c8b7210f9dap+0, .logc = -0x1.22079f8c56000p-4 },
        .{ .invc = 0x1.11a3028ecb531p+0, .logc = -0x1.10e4698622000p-4 },
        .{ .invc = 0x1.107fbda8434afp+0, .logc = -0x1.ffa6c6ad20000p-5 },
        .{ .invc = 0x1.0f5ee0f4e6bb3p+0, .logc = -0x1.dda8d4a774000p-5 },
        .{ .invc = 0x1.0e4065d2a9fcep+0, .logc = -0x1.bbcece4850000p-5 },
        .{ .invc = 0x1.0d244632ca521p+0, .logc = -0x1.9a1894012c000p-5 },
        .{ .invc = 0x1.0c0a77ce2981ap+0, .logc = -0x1.788583302c000p-5 },
        .{ .invc = 0x1.0af2f83c636d1p+0, .logc = -0x1.5715e67d68000p-5 },
        .{ .invc = 0x1.09ddb98a01339p+0, .logc = -0x1.35c8a49658000p-5 },
        .{ .invc = 0x1.08cabaf52e7dfp+0, .logc = -0x1.149e364154000p-5 },
        .{ .invc = 0x1.07b9f2f4e28fbp+0, .logc = -0x1.e72c082eb8000p-6 },
        .{ .invc = 0x1.06ab58c358f19p+0, .logc = -0x1.a55f152528000p-6 },
        .{ .invc = 0x1.059eea5ecf92cp+0, .logc = -0x1.63d62cf818000p-6 },
        .{ .invc = 0x1.04949cdd12c90p+0, .logc = -0x1.228fb8caa0000p-6 },
        .{ .invc = 0x1.038c6c6f0ada9p+0, .logc = -0x1.c317b20f90000p-7 },
        .{ .invc = 0x1.02865137932a9p+0, .logc = -0x1.419355daa0000p-7 },
        .{ .invc = 0x1.0182427ea7348p+0, .logc = -0x1.81203c2ec0000p-8 },
        .{ .invc = 0x1.008040614b195p+0, .logc = -0x1.0040979240000p-9 },
        .{ .invc = 0x1.fe01ff726fa1ap-1, .logc = 0x1.feff384900000p-9 },
        .{ .invc = 0x1.fa11cc261ea74p-1, .logc = 0x1.7dc41353d0000p-7 },
        .{ .invc = 0x1.f6310b081992ep-1, .logc = 0x1.3cea3c4c28000p-6 },
        .{ .invc = 0x1.f25f63ceeadcdp-1, .logc = 0x1.b9fc114890000p-6 },
        .{ .invc = 0x1.ee9c8039113e7p-1, .logc = 0x1.1b0d8ce110000p-5 },
        .{ .invc = 0x1.eae8078cbb1abp-1, .logc = 0x1.58a5bd001c000p-5 },
        .{ .invc = 0x1.e741aa29d0c9bp-1, .logc = 0x1.95c8340d88000p-5 },
        .{ .invc = 0x1.e3a91830a99b5p-1, .logc = 0x1.d276aef578000p-5 },
        .{ .invc = 0x1.e01e009609a56p-1, .logc = 0x1.07598e598c000p-4 },
        .{ .invc = 0x1.dca01e577bb98p-1, .logc = 0x1.253f5e30d2000p-4 },
        .{ .invc = 0x1.d92f20b7c9103p-1, .logc = 0x1.42edd8b380000p-4 },
        .{ .invc = 0x1.d5cac66fb5ccep-1, .logc = 0x1.606598757c000p-4 },
        .{ .invc = 0x1.d272caa5ede9dp-1, .logc = 0x1.7da76356a0000p-4 },
        .{ .invc = 0x1.cf26e3e6b2ccdp-1, .logc = 0x1.9ab434e1c6000p-4 },
        .{ .invc = 0x1.cbe6da2a77902p-1, .logc = 0x1.b78c7bb0d6000p-4 },
        .{ .invc = 0x1.c8b266d37086dp-1, .logc = 0x1.d431332e72000p-4 },
        .{ .invc = 0x1.c5894bd5d5804p-1, .logc = 0x1.f0a3171de6000p-4 },
        .{ .invc = 0x1.c26b533bb9f8cp-1, .logc = 0x1.067152b914000p-3 },
        .{ .invc = 0x1.bf583eeece73fp-1, .logc = 0x1.147858292b000p-3 },
        .{ .invc = 0x1.bc4fd75db96c1p-1, .logc = 0x1.2266ecdca3000p-3 },
        .{ .invc = 0x1.b951e0c864a28p-1, .logc = 0x1.303d7a6c55000p-3 },
        .{ .invc = 0x1.b65e2c5ef3e2cp-1, .logc = 0x1.3dfc33c331000p-3 },
        .{ .invc = 0x1.b374867c9888bp-1, .logc = 0x1.4ba366b7a8000p-3 },
        .{ .invc = 0x1.b094b211d304ap-1, .logc = 0x1.5933928d1f000p-3 },
        .{ .invc = 0x1.adbe885f2ef7ep-1, .logc = 0x1.66acd2418f000p-3 },
        .{ .invc = 0x1.aaf1d31603da2p-1, .logc = 0x1.740f8ec669000p-3 },
        .{ .invc = 0x1.a82e63fd358a7p-1, .logc = 0x1.815c0f51af000p-3 },
        .{ .invc = 0x1.a5740ef09738bp-1, .logc = 0x1.8e92954f68000p-3 },
        .{ .invc = 0x1.a2c2a90ab4b27p-1, .logc = 0x1.9bb3602f84000p-3 },
        .{ .invc = 0x1.a01a01393f2d1p-1, .logc = 0x1.a8bed1c2c0000p-3 },
        .{ .invc = 0x1.9d79f24db3c1bp-1, .logc = 0x1.b5b515c01d000p-3 },
        .{ .invc = 0x1.9ae2505c7b190p-1, .logc = 0x1.c2967ccbcc000p-3 },
        .{ .invc = 0x1.9852ef297ce2fp-1, .logc = 0x1.cf635d5486000p-3 },
        .{ .invc = 0x1.95cbaeea44b75p-1, .logc = 0x1.dc1bd3446c000p-3 },
        .{ .invc = 0x1.934c69de74838p-1, .logc = 0x1.e8c01b8cfe000p-3 },
        .{ .invc = 0x1.90d4f2f6752e6p-1, .logc = 0x1.f5509c0179000p-3 },
        .{ .invc = 0x1.8e6528effd79dp-1, .logc = 0x1.00e6c121fb800p-2 },
        .{ .invc = 0x1.8bfce9fcc007cp-1, .logc = 0x1.071b80e93d000p-2 },
        .{ .invc = 0x1.899c0dabec30ep-1, .logc = 0x1.0d46b9e867000p-2 },
        .{ .invc = 0x1.87427aa2317fbp-1, .logc = 0x1.13687334bd000p-2 },
        .{ .invc = 0x1.84f00acb39a08p-1, .logc = 0x1.1980d67234800p-2 },
        .{ .invc = 0x1.82a49e8653e55p-1, .logc = 0x1.1f8ffe0cc8000p-2 },
        .{ .invc = 0x1.8060195f40260p-1, .logc = 0x1.2595fd7636800p-2 },
        .{ .invc = 0x1.7e22563e0a329p-1, .logc = 0x1.2b9300914a800p-2 },
        .{ .invc = 0x1.7beb377dcb5adp-1, .logc = 0x1.3187210436000p-2 },
        .{ .invc = 0x1.79baa679725c2p-1, .logc = 0x1.377266dec1800p-2 },
        .{ .invc = 0x1.77907f2170657p-1, .logc = 0x1.3d54ffbaf3000p-2 },
        .{ .invc = 0x1.756cadbd6130cp-1, .logc = 0x1.432eee32fe000p-2 },
    };

    const tab2 = [128]struct { chi: f64, clo: f64 }{
        .{ .chi = 0x1.61000014fb66bp-1, .clo = 0x1.e026c91425b3cp-56 },
        .{ .chi = 0x1.63000034db495p-1, .clo = 0x1.dbfea48005d41p-55 },
        .{ .chi = 0x1.650000d94d478p-1, .clo = 0x1.e7fa786d6a5b7p-55 },
        .{ .chi = 0x1.67000074e6fadp-1, .clo = 0x1.1fcea6b54254cp-57 },
        .{ .chi = 0x1.68ffffedf0faep-1, .clo = -0x1.c7e274c590efdp-56 },
        .{ .chi = 0x1.6b0000763c5bcp-1, .clo = -0x1.ac16848dcda01p-55 },
        .{ .chi = 0x1.6d0001e5cc1f6p-1, .clo = 0x1.33f1c9d499311p-55 },
        .{ .chi = 0x1.6efffeb05f63ep-1, .clo = -0x1.e80041ae22d53p-56 },
        .{ .chi = 0x1.710000e86978p-1, .clo = 0x1.bff6671097952p-56 },
        .{ .chi = 0x1.72ffffc67e912p-1, .clo = 0x1.c00e226bd8724p-55 },
        .{ .chi = 0x1.74fffdf81116ap-1, .clo = -0x1.e02916ef101d2p-57 },
        .{ .chi = 0x1.770000f679c9p-1, .clo = -0x1.7fc71cd549c74p-57 },
        .{ .chi = 0x1.78ffffa7ec835p-1, .clo = 0x1.1bec19ef50483p-55 },
        .{ .chi = 0x1.7affffe20c2e6p-1, .clo = -0x1.07e1729cc6465p-56 },
        .{ .chi = 0x1.7cfffed3fc9p-1, .clo = -0x1.08072087b8b1cp-55 },
        .{ .chi = 0x1.7efffe9261a76p-1, .clo = 0x1.dc0286d9df9aep-55 },
        .{ .chi = 0x1.81000049ca3e8p-1, .clo = 0x1.97fd251e54c33p-55 },
        .{ .chi = 0x1.8300017932c8fp-1, .clo = -0x1.afee9b630f381p-55 },
        .{ .chi = 0x1.850000633739cp-1, .clo = 0x1.9bfbf6b6535bcp-55 },
        .{ .chi = 0x1.87000204289c6p-1, .clo = -0x1.bbf65f3117b75p-55 },
        .{ .chi = 0x1.88fffebf57904p-1, .clo = -0x1.9006ea23dcb57p-55 },
        .{ .chi = 0x1.8b00022bc04dfp-1, .clo = -0x1.d00df38e04b0ap-56 },
        .{ .chi = 0x1.8cfffe50c1b8ap-1, .clo = -0x1.8007146ff9f05p-55 },
        .{ .chi = 0x1.8effffc918e43p-1, .clo = 0x1.3817bd07a7038p-55 },
        .{ .chi = 0x1.910001efa5fc7p-1, .clo = 0x1.93e9176dfb403p-55 },
        .{ .chi = 0x1.9300013467bb9p-1, .clo = 0x1.f804e4b980276p-56 },
        .{ .chi = 0x1.94fffe6ee076fp-1, .clo = -0x1.f7ef0d9ff622ep-55 },
        .{ .chi = 0x1.96fffde3c12d1p-1, .clo = -0x1.082aa962638bap-56 },
        .{ .chi = 0x1.98ffff4458a0dp-1, .clo = -0x1.7801b9164a8efp-55 },
        .{ .chi = 0x1.9afffdd982e3ep-1, .clo = -0x1.740e08a5a9337p-55 },
        .{ .chi = 0x1.9cfffed49fb66p-1, .clo = 0x1.fce08c19bep-60 },
        .{ .chi = 0x1.9f00020f19c51p-1, .clo = -0x1.a3faa27885b0ap-55 },
        .{ .chi = 0x1.a10001145b006p-1, .clo = 0x1.4ff489958da56p-56 },
        .{ .chi = 0x1.a300007bbf6fap-1, .clo = 0x1.cbeab8a2b6d18p-55 },
        .{ .chi = 0x1.a500010971d79p-1, .clo = 0x1.8fecadd78793p-55 },
        .{ .chi = 0x1.a70001df52e48p-1, .clo = -0x1.f41763dd8abdbp-55 },
        .{ .chi = 0x1.a90001c593352p-1, .clo = -0x1.ebf0284c27612p-55 },
        .{ .chi = 0x1.ab0002a4f3e4bp-1, .clo = -0x1.9fd043cff3f5fp-57 },
        .{ .chi = 0x1.acfffd7ae1ed1p-1, .clo = -0x1.23ee7129070b4p-55 },
        .{ .chi = 0x1.aefffee510478p-1, .clo = 0x1.a063ee00edea3p-57 },
        .{ .chi = 0x1.b0fffdb650d5bp-1, .clo = 0x1.a06c8381f0ab9p-58 },
        .{ .chi = 0x1.b2ffffeaaca57p-1, .clo = -0x1.9011e74233c1dp-56 },
        .{ .chi = 0x1.b4fffd995badcp-1, .clo = -0x1.9ff1068862a9fp-56 },
        .{ .chi = 0x1.b7000249e659cp-1, .clo = 0x1.aff45d0864f3ep-55 },
        .{ .chi = 0x1.b8ffff987164p-1, .clo = 0x1.cfe7796c2c3f9p-56 },
        .{ .chi = 0x1.bafffd204cb4fp-1, .clo = -0x1.3ff27eef22bc4p-57 },
        .{ .chi = 0x1.bcfffd2415c45p-1, .clo = -0x1.cffb7ee3bea21p-57 },
        .{ .chi = 0x1.beffff86309dfp-1, .clo = -0x1.14103972e0b5cp-55 },
        .{ .chi = 0x1.c0fffe1b57653p-1, .clo = 0x1.bc16494b76a19p-55 },
        .{ .chi = 0x1.c2ffff1fa57e3p-1, .clo = -0x1.4feef8d30c6edp-57 },
        .{ .chi = 0x1.c4fffdcbfe424p-1, .clo = -0x1.43f68bcec4775p-55 },
        .{ .chi = 0x1.c6fffed54b9f7p-1, .clo = 0x1.47ea3f053e0ecp-55 },
        .{ .chi = 0x1.c8fffeb998fd5p-1, .clo = 0x1.383068df992f1p-56 },
        .{ .chi = 0x1.cb0002125219ap-1, .clo = -0x1.8fd8e64180e04p-57 },
        .{ .chi = 0x1.ccfffdd94469cp-1, .clo = 0x1.e7ebe1cc7ea72p-55 },
        .{ .chi = 0x1.cefffeafdc476p-1, .clo = 0x1.ebe39ad9f88fep-55 },
        .{ .chi = 0x1.d1000169af82bp-1, .clo = 0x1.57d91a8b95a71p-56 },
        .{ .chi = 0x1.d30000d0ff71dp-1, .clo = 0x1.9c1906970c7dap-55 },
        .{ .chi = 0x1.d4fffea790fc4p-1, .clo = -0x1.80e37c558fe0cp-58 },
        .{ .chi = 0x1.d70002edc87e5p-1, .clo = -0x1.f80d64dc10f44p-56 },
        .{ .chi = 0x1.d900021dc82aap-1, .clo = -0x1.47c8f94fd5c5cp-56 },
        .{ .chi = 0x1.dafffd86b0283p-1, .clo = 0x1.c7f1dc521617ep-55 },
        .{ .chi = 0x1.dd000296c4739p-1, .clo = 0x1.8019eb2ffb153p-55 },
        .{ .chi = 0x1.defffe54490f5p-1, .clo = 0x1.e00d2c652cc89p-57 },
        .{ .chi = 0x1.e0fffcdabf694p-1, .clo = -0x1.f8340202d69d2p-56 },
        .{ .chi = 0x1.e2fffdb52c8ddp-1, .clo = 0x1.b00c1ca1b0864p-56 },
        .{ .chi = 0x1.e4ffff24216efp-1, .clo = 0x1.2ffa8b094ab51p-56 },
        .{ .chi = 0x1.e6fffe88a5e11p-1, .clo = -0x1.7f673b1efbe59p-58 },
        .{ .chi = 0x1.e9000119eff0dp-1, .clo = -0x1.4808d5e0bc801p-55 },
        .{ .chi = 0x1.eafffdfa51744p-1, .clo = 0x1.80006d54320b5p-56 },
        .{ .chi = 0x1.ed0001a127fa1p-1, .clo = -0x1.002f860565c92p-58 },
        .{ .chi = 0x1.ef00007babcc4p-1, .clo = -0x1.540445d35e611p-55 },
        .{ .chi = 0x1.f0ffff57a8d02p-1, .clo = -0x1.ffb3139ef9105p-59 },
        .{ .chi = 0x1.f30001ee58ac7p-1, .clo = 0x1.a81acf2731155p-55 },
        .{ .chi = 0x1.f4ffff5823494p-1, .clo = 0x1.a3f41d4d7c743p-55 },
        .{ .chi = 0x1.f6ffffca94c6bp-1, .clo = -0x1.202f41c987875p-57 },
        .{ .chi = 0x1.f8fffe1f9c441p-1, .clo = 0x1.77dd1f477e74bp-56 },
        .{ .chi = 0x1.fafffd2e0e37ep-1, .clo = -0x1.f01199a7ca331p-57 },
        .{ .chi = 0x1.fd0001c77e49ep-1, .clo = 0x1.181ee4bceacb1p-56 },
        .{ .chi = 0x1.feffff7e0c331p-1, .clo = -0x1.e05370170875ap-57 },
        .{ .chi = 0x1.00ffff465606ep+0, .clo = -0x1.a7ead491c0adap-55 },
        .{ .chi = 0x1.02ffff3867a58p+0, .clo = -0x1.77f69c3fcb2ep-54 },
        .{ .chi = 0x1.04ffffdfc0d17p+0, .clo = 0x1.7bffe34cb945bp-54 },
        .{ .chi = 0x1.0700003cd4d82p+0, .clo = 0x1.20083c0e456cbp-55 },
        .{ .chi = 0x1.08ffff9f2cbe8p+0, .clo = -0x1.dffdfbe37751ap-57 },
        .{ .chi = 0x1.0b000010cda65p+0, .clo = -0x1.13f7faee626ebp-54 },
        .{ .chi = 0x1.0d00001a4d338p+0, .clo = 0x1.07dfa79489ff7p-55 },
        .{ .chi = 0x1.0effffadafdfdp+0, .clo = -0x1.7040570d66bcp-56 },
        .{ .chi = 0x1.110000bbafd96p+0, .clo = 0x1.e80d4846d0b62p-55 },
        .{ .chi = 0x1.12ffffae5f45dp+0, .clo = 0x1.dbffa64fd36efp-54 },
        .{ .chi = 0x1.150000dd59ad9p+0, .clo = 0x1.a0077701250aep-54 },
        .{ .chi = 0x1.170000f21559ap+0, .clo = 0x1.dfdf9e2e3deeep-55 },
        .{ .chi = 0x1.18ffffc275426p+0, .clo = 0x1.10030dc3b7273p-54 },
        .{ .chi = 0x1.1b000123d3c59p+0, .clo = 0x1.97f7980030188p-54 },
        .{ .chi = 0x1.1cffff8299eb7p+0, .clo = -0x1.5f932ab9f8c67p-57 },
        .{ .chi = 0x1.1effff48ad4p+0, .clo = 0x1.37fbf9da75bebp-54 },
        .{ .chi = 0x1.210000c8b86a4p+0, .clo = 0x1.f806b91fd5b22p-54 },
        .{ .chi = 0x1.2300003854303p+0, .clo = 0x1.3ffc2eb9fbf33p-54 },
        .{ .chi = 0x1.24fffffbcf684p+0, .clo = 0x1.601e77e2e2e72p-56 },
        .{ .chi = 0x1.26ffff52921d9p+0, .clo = 0x1.ffcbb767f0c61p-56 },
        .{ .chi = 0x1.2900014933a3cp+0, .clo = -0x1.202ca3c02412bp-56 },
        .{ .chi = 0x1.2b00014556313p+0, .clo = -0x1.2808233f21f02p-54 },
        .{ .chi = 0x1.2cfffebfe523bp+0, .clo = -0x1.8ff7e384fdcf2p-55 },
        .{ .chi = 0x1.2f0000bb8ad96p+0, .clo = -0x1.5ff51503041c5p-55 },
        .{ .chi = 0x1.30ffffb7ae2afp+0, .clo = -0x1.10071885e289dp-55 },
        .{ .chi = 0x1.32ffffeac5f7fp+0, .clo = -0x1.1ff5d3fb7b715p-54 },
        .{ .chi = 0x1.350000ca66756p+0, .clo = 0x1.57f82228b82bdp-54 },
        .{ .chi = 0x1.3700011fbf721p+0, .clo = 0x1.000bac40dd5ccp-55 },
        .{ .chi = 0x1.38ffff9592fb9p+0, .clo = -0x1.43f9d2db2a751p-54 },
        .{ .chi = 0x1.3b00004ddd242p+0, .clo = 0x1.57f6b707638e1p-55 },
        .{ .chi = 0x1.3cffff5b2c957p+0, .clo = 0x1.a023a10bf1231p-56 },
        .{ .chi = 0x1.3efffeab0b418p+0, .clo = 0x1.87f6d66b152bp-54 },
        .{ .chi = 0x1.410001532aff4p+0, .clo = 0x1.7f8375f198524p-57 },
        .{ .chi = 0x1.4300017478b29p+0, .clo = 0x1.301e672dc5143p-55 },
        .{ .chi = 0x1.44fffe795b463p+0, .clo = 0x1.9ff69b8b2895ap-55 },
        .{ .chi = 0x1.46fffe80475ep+0, .clo = -0x1.5c0b19bc2f254p-54 },
        .{ .chi = 0x1.48fffef6fc1e7p+0, .clo = 0x1.b4009f23a2a72p-54 },
        .{ .chi = 0x1.4afffe5bea704p+0, .clo = -0x1.4ffb7bf0d7d45p-54 },
        .{ .chi = 0x1.4d000171027dep+0, .clo = -0x1.9c06471dc6a3dp-54 },
        .{ .chi = 0x1.4f0000ff03ee2p+0, .clo = 0x1.77f890b85531cp-54 },
        .{ .chi = 0x1.5100012dc4bd1p+0, .clo = 0x1.004657166a436p-57 },
        .{ .chi = 0x1.530001605277ap+0, .clo = -0x1.6bfcece233209p-54 },
        .{ .chi = 0x1.54fffecdb704cp+0, .clo = -0x1.902720505a1d7p-55 },
        .{ .chi = 0x1.56fffef5f54a9p+0, .clo = 0x1.bbfe60ec96412p-54 },
        .{ .chi = 0x1.5900017e61012p+0, .clo = 0x1.87ec581afef9p-55 },
        .{ .chi = 0x1.5b00003c93e92p+0, .clo = -0x1.f41080abf0ccp-54 },
        .{ .chi = 0x1.5d0001d4919bcp+0, .clo = -0x1.8812afb254729p-54 },
        .{ .chi = 0x1.5efffe7b87a89p+0, .clo = -0x1.47eb780ed6904p-54 },
    };

    var ix: i64 = @bitCast(x);

    const LO: i64 = @bitCast(@as(f64, 1.0 - 0x1p-4));
    const HI: i64 = @bitCast(@as(f64, 1.0 + 0x1.09p-4));
    if (LO <= ix and ix < HI) {
        @branchHint(.unlikely);
        if (ix == @as(i64, @bitCast(@as(f64, 1)))) {
            @branchHint(.unlikely);
            return 0;
        }

        const r = x - 1;
        const r2 = r * r;
        const r3 = r * r2;

        const y = r3 * (poly1[1] + r * poly1[2] + r2 * poly1[3] +
            r3 * (poly1[4] + r * poly1[5] + r2 * poly1[6] +
                r3 * (poly1[7] + r * poly1[8] + r2 * poly1[9] + r3 * poly1[10])));

        var w = r * 0x1p27;
        const rhi = r + w - w;
        const rlo = r - rhi;
        w = rhi * rhi * poly1[0];
        const hi = r + w;
        const lo = r - hi + w + poly1[0] * rlo * (rhi + r);
        return y + lo + hi;
    }
    const top = @as(u64, @bitCast(ix)) >> 48;
    if (top < 0x0010 or 0x7ff0 <= top) {
        @branchHint(.unlikely);

        if (ix << 1 == 0)
            return if (compiler_rt.want_float_exceptions) -1 / (x * x) else -std.math.inf(f64);

        if (ix == @as(i64, @bitCast(std.math.inf(f64))))
            return x;

        if (top & 0x8000 != 0 or top & 0x7ff0 == 0x7ff0)
            return if (compiler_rt.want_float_exceptions) (x - x) / 0.0 else math.nan(f64);

        ix = @as(i64, @bitCast(x * 0x1p52)) - (52 << 52);
    }

    const tmp: packed struct(i64) { unused: u45, i: u7, k: i12 } = @bitCast(ix - 0x3fe6000000000000);
    const i = tmp.i;
    const k = tmp.k;
    const iz = ix - (@as(i64, tmp.k) << 52);
    const invc = tab[i].invc;
    const logc = tab[i].logc;
    const z: f64 = @bitCast(iz);

    // maybe use fma as musl does
    const r = (z - tab2[i].chi - tab2[i].clo) * invc;

    const kd: f64 = k;
    const w = kd * 0x1.62e42fefa3800p-1 + logc;
    const hi = w + r;
    const lo = w - hi + r + kd * 0x1.ef35793c76730p-45;

    const r2 = r * r;

    const y = lo + r2 * poly[0] + r * r2 * (poly[1] + r * poly[2] + r2 * (poly[3] + r * poly[4])) + hi;
    return @bitCast(y);
}

pub fn __logx(a: f80) callconv(.c) f80 {
    // TODO: more efficient implementation
    return @floatCast(logq(a));
}

/// Implementation of "Table-driven implementation of the logarithm function in IEEE floating-point arithmetic"
/// by PTP Tang in ACM Transactions on Mathematical Software (TOMS), 1990
///
/// https://dl.acm.org/doi/pdf/10.1145/98267.98294
///
/// Adapted to work for f128 by Christophe Delage.
///
/// Accuracy on 100 million random numbers in [0, inf) (exponent uniformly random)
/// <= 0.5 ulp: 99.99%, worst case <= 0.530 ulp
///
/// Accuracy on 10 million random numbers near x = 1 (testing the proc2 case):
/// <= 0.5 ulp: 99.96%, worst case <= 0.528 ulp
pub fn logq(x: f128) callconv(.c) f128 {
    const impl = @import("log_f128.zig");

    if (impl.specialCases(x)) |y|
        return y;

    if (impl.Proc2.lo < x and x < impl.Proc2.hi) {
        // Polynomial approximation of log((1 + u / 2) / (1 - u / 2))
        // in [2 * a / (2 + a), 2 * b / (2 + b)]
        // where a = exp(-1 / 16) - 1 and b = exp(1 / 16) - 1
        const poly: impl.Proc2.Poly = .{
            .b1_hi = 1.0,
            .b1_lo = 0.0,
            .b3 = 8.333333333333333333333333333333581e-2,
            .b5 = 1.249999999999999999999999997455655e-2,
            .b7 = 2.2321428571428571428572328745789477e-3,
            .b9 = 4.340277777777777776216500817402857e-4,
            .b11 = 8.87784090909092440759545734146088e-5,
            .b13 = 1.8780048076832339308077858301484127e-5,
            .b15 = 4.069010449774280288178309893970754e-6,
            .b17 = 8.97568550755477160981619052649713e-7,
            .b19 = 2.0165671588771827537210411918018159e-7,
        };
        return impl.proc2(.{ .poly = poly }, x);
    }

    // Polynomial approximation of log(1 + 2 * u / (2 - u))
    // in [-(2 * fmax) / (2 + fmax), (2 * fmax) / (2 - fmax)]
    // where fmax = 0.5 / size
    const poly: impl.Proc1.Poly = .{
        .a1 = 1.0,
        .a3 = 8.333333333333333333333333333372414e-2,
        .a5 = 1.249999999999999999999963839743372e-2,
        .a7 = 2.2321428571428572515097318595359542e-3,
        .a9 = 4.340277777635300605611118803507141e-4,
        .a11 = 8.877925718782769769445565656611838e-5,
    };

    // tab[j].hi = 2^-n * round-to-integer(2^n * l)
    // tab[j].lo = round-to-nearest-f128(l - tab[j].hi)
    // where n = 97 and l = log(1 + j / size)
    const tab = [impl.size + 1]impl.Proc1.HiLo{
        .{ .hi = 0, .lo = 0 },
        .{ .hi = 0x1.fe02a6b106788fc3769039p-8, .lo = 0x1.dc282d2b3db2c3ef9a073a876702p-100 },
        .{ .hi = 0x1.fc0a8b0fc03e3cf9eda74d4p-7, .lo = -0x1.0a8552414fc416fc223acca2ebfp-100 },
        .{ .hi = 0x1.7b91b07d5b11aa927f54c72p-6, .lo = -0x1.287fc46561dfab5bc5cceecb4882p-99 },
        .{ .hi = 0x1.f829b0e7833004cf8fc13c8p-6, .lo = -0x1.0dd605151051eb3220ca52e20939p-100 },
        .{ .hi = 0x1.39e87b9febd5fa9015b202bp-5, .lo = -0x1.1bac6e550a3c3dc859cfe2e178a8p-99 },
        .{ .hi = 0x1.77458f632dcfc4634f2a1eep-5, .lo = 0x1.2960b1e4dfb80d9544ec6583eb3ap-99 },
        .{ .hi = 0x1.b42dd711971bec28d14c7dap-5, .lo = -0x1.2645ad50c7672fc0eb08d862221dp-102 },
        .{ .hi = 0x1.f0a30c01162a6617cc9716fp-5, .lo = -0x1.4cd0ece597165991495b4d31cf5cp-101 },
        .{ .hi = 0x1.16536eea37ae0e8625c173ep-4, .lo = -0x1.66d0dc92deb7d2ccbd2caa9640cap-99 },
        .{ .hi = 0x1.341d7961bd1d092998376108p-4, .lo = -0x1.976457ef2f89ad243dcc3578cf7ep-99 },
        .{ .hi = 0x1.51b073f06183f69278e686ap-4, .lo = 0x1.7c8ac25e4e3f04de1f086f5cb4b1p-99 },
        .{ .hi = 0x1.6f0d28ae56b4b9be499b9edp-4, .lo = 0x1.9b640ce50c1ef65087fdf23812f4p-100 },
        .{ .hi = 0x1.8c345d6319b20f5acb42a66p-4, .lo = -0x1.254bca8fd9fc1bf283b3b4b8662dp-100 },
        .{ .hi = 0x1.a926d3a4ad563650bd22a9cp-4, .lo = 0x1.d5263cd4fb3f11769cc680ef5589p-99 },
        .{ .hi = 0x1.c5e548f5bc74315d617ef818p-4, .lo = -0x1.e4e896269950723c88d353ee9c18p-100 },
        .{ .hi = 0x1.e27076e2af2e5e9ea87ffe2p-4, .lo = -0x1.61eaa246b143bfe80906a822f768p-104 },
        .{ .hi = 0x1.fec9131dbeabaaa2e5199f9p-4, .lo = 0x1.9271dff48f15d409017630a93931p-99 },
        .{ .hi = 0x1.0d77e7cd08e596697717a40cp-3, .lo = 0x1.574712132d3f6340e183be2031c6p-102 },
        .{ .hi = 0x1.1b72ad52f67a029060468e58p-3, .lo = 0x1.ae73f3bc7ec84ca997609536a037p-99 },
        .{ .hi = 0x1.29552f81ff5234c05dc7102p-3, .lo = -0x1.20b2ef60436f8f081d60452c9fc1p-100 },
        .{ .hi = 0x1.371fc201e8f743bcd96c55e4p-3, .lo = -0x1.d80d17e0cd92558ad6fcd608bb1bp-100 },
        .{ .hi = 0x1.44d2b6ccb7d1e67d3d950f88p-3, .lo = -0x1.e1f3be9a83374584faad83fa4fecp-103 },
        .{ .hi = 0x1.526e5e3a1b437a2e401d6e3cp-3, .lo = 0x1.6334db798c76a888aa87317b14f8p-100 },
        .{ .hi = 0x1.5ff3070a793d3c873e20a074p-3, .lo = -0x1.edc45019551c65501060ce71fa98p-99 },
        .{ .hi = 0x1.6d60fe719d21c8d54765c4ccp-3, .lo = -0x1.790e412e6d3ed18e4a7c22362e49p-101 },
        .{ .hi = 0x1.7ab890210d9091be36b2d6ap-3, .lo = 0x1.820191ff8525362042cad5d8c597p-101 },
        .{ .hi = 0x1.87fa06520c910902009017dcp-3, .lo = 0x1.32ef5a55704b6b7eb4ebea28a6cdp-100 },
        .{ .hi = 0x1.9525a9cf456b47641307538cp-3, .lo = -0x1.da62766be8258611d132d71d84acp-101 },
        .{ .hi = 0x1.a23bc1fe2b563193711b07a8p-3, .lo = 0x1.98c27e3f1b66d8b32de61c04cf95p-99 },
        .{ .hi = 0x1.af3c94e80bff2d8ce601937cp-3, .lo = 0x1.9eb976769b8b9a5d50ca14a7622fp-100 },
        .{ .hi = 0x1.bc286742d8cd629f9ce890ep-3, .lo = 0x1.ea9e1e2c3dca46c83cd6d19e5e9bp-99 },
        .{ .hi = 0x1.c8ff7c79a9a21ac25d81ef3p-3, .lo = -0x1.1976d471342b17dca47c9d1e1d98p-105 },
        .{ .hi = 0x1.d5c216b4fbb915b910d65f94p-3, .lo = -0x1.5ff1e1c98c2ed4063968ad2332f8p-100 },
        .{ .hi = 0x1.e27076e2af2e5e9ea87ffe2p-3, .lo = -0x1.61eaa246b143bfe80906a822f768p-103 },
        .{ .hi = 0x1.ef0adcbdc59365218de5437p-3, .lo = 0x1.06429f5a5098683a47c3a3ca5835p-100 },
        .{ .hi = 0x1.fb9186d5e3e2a8d55466c378p-3, .lo = 0x1.4d2ca09202c222ad91640bd8b2fcp-99 },
        .{ .hi = 0x1.0402594b4d040dae27bd0b6p-2, .lo = -0x1.16a1bbb899f343f105ee37cafa25p-100 },
        .{ .hi = 0x1.0a324e27390e35f73f7a0188p-2, .lo = -0x1.fe78eb90fe52820fb4690e4910e3p-99 },
        .{ .hi = 0x1.1058bf9ae4ad5189fa0ab4ccp-2, .lo = -0x1.9c60f598d3a32076376a5960e735p-99 },
        .{ .hi = 0x1.1675cababa60e039cc7d571p-2, .lo = 0x1.b8b823f067d04a43c19f534c3c8ep-100 },
        .{ .hi = 0x1.1c898c16999fafbc68e75404p-2, .lo = -0x1.c443cc477d114a1350a26c9b5535p-100 },
        .{ .hi = 0x1.22941fbcf7965a242853da76p-2, .lo = -0x1.5e685a2caa590b0f13a31703b136p-101 },
        .{ .hi = 0x1.2895a13de86a35eb49304fc2p-2, .lo = -0x1.f8d3a52b8aa6834f50a903b31253p-99 },
        .{ .hi = 0x1.2e8e2bae11d309c2cc91a85p-2, .lo = 0x1.03679bdbbd6b7d91378a909a6793p-99 },
        .{ .hi = 0x1.347dd9a987d54d645674fedcp-2, .lo = 0x1.821ee510a580b3b30ef57f83ca28p-99 },
        .{ .hi = 0x1.3a64c556945e9c72f35cd74p-2, .lo = 0x1.a11beb7a3cee7e029e46e1334dfep-99 },
        .{ .hi = 0x1.404308686a7e3bd0c127df4cp-2, .lo = 0x1.92985641827d9d91a2da0d4f2207p-100 },
        .{ .hi = 0x1.4618bc21c5ec27d0b7b37b34p-2, .lo = -0x1.c65df511a65b67fe9778d8694229p-101 },
        .{ .hi = 0x1.4be5f957778a0db4c9949f7p-2, .lo = -0x1.3cdc28d5974f3185a1f581529353p-101 },
        .{ .hi = 0x1.51aad872df82d09c93d60cfap-2, .lo = 0x1.5e311d4f4f357cbfae095f10fcd3p-99 },
        .{ .hi = 0x1.5767717455a6c549ab6ca0dap-2, .lo = -0x1.f42ff0747cbcce6c0841fd7ceb87p-100 },
        .{ .hi = 0x1.5d1bdbf5809ca508d8e0f72p-2, .lo = -0x1.eea60c7f4b594bd65b44f6b20634p-104 },
        .{ .hi = 0x1.62c82f2b9c7952f6f5f22a6p-2, .lo = 0x1.ca2e7226c55dd257f44b5002c8cdp-102 },
        .{ .hi = 0x1.686c81e9b14aec442be1014ep-2, .lo = 0x1.c34b25bdbda38672b32ca47f535dp-101 },
        .{ .hi = 0x1.6e08eaa2ba1e38c139318d72p-2, .lo = -0x1.07a1f9d2a3058cd3f047b933d485p-99 },
        .{ .hi = 0x1.739d7f6bbd0069ce24c53faep-2, .lo = -0x1.8210d2a910f7918ad34542221b6cp-99 },
        .{ .hi = 0x1.792a55fdd47a27c15da47fa8p-2, .lo = -0x1.297ea603cd10e7c702842a1590aep-100 },
        .{ .hi = 0x1.7eaf83b82afc364b3a5e7b4ap-2, .lo = 0x1.50437160cbfcbf71ee8d4b3cd067p-100 },
        .{ .hi = 0x1.842d1da1e8b17493b1465e12p-2, .lo = -0x1.899770fb9eb8e0c7f06a12cd88c3p-100 },
        .{ .hi = 0x1.89a3386c1425ab5a71881104p-2, .lo = -0x1.f549800739afc97f5d4b9c15fc12p-101 },
        .{ .hi = 0x1.8f11e873662c77e1769d5698p-2, .lo = 0x1.a29979cbfcbc0e45410ee8ca0d17p-100 },
        .{ .hi = 0x1.947941c2116faba4cdd147d2p-2, .lo = -0x1.f22a2b6b19ed11af82f2c0e6730ep-99 },
        .{ .hi = 0x1.99d958117e08acba92eec478p-2, .lo = 0x1.8dfba4bb71c95f44a3225b5d8f8fp-101 },
        .{ .hi = 0x1.9f323ecbf984bf2b68d766f4p-2, .lo = 0x1.4886067d20ffb34547d7c2b38ad8p-104 },
        .{ .hi = 0x1.a484090e5bb0a2bfca6b70ecp-2, .lo = -0x1.62da6c6290af3949ca12eb97e6bbp-99 },
        .{ .hi = 0x1.a9cec9a9a08498d484ff52f2p-2, .lo = 0x1.50d7be11fc8ee26768c44e9f35aap-100 },
        .{ .hi = 0x1.af1293247786b1133844a15ep-2, .lo = -0x1.ebf9e3b2fb68378f9b7aa0ef6685p-101 },
        .{ .hi = 0x1.b44f77bcc8f628cbeedaae98p-2, .lo = 0x1.c3c779029d5a684301e7888d5449p-99 },
        .{ .hi = 0x1.b9858969310fb598fb14f88ep-2, .lo = 0x1.e1cf79039d5a31010282d8264afap-99 },
        .{ .hi = 0x1.beb4d9da71b7bf7861d37abcp-2, .lo = -0x1.f29b495a7c83dffb9899ad6da116p-101 },
        .{ .hi = 0x1.c3dd7a7cdad4d73b3c14b7aap-2, .lo = -0x1.649f44ae71a827ebf6601862d429p-100 },
        .{ .hi = 0x1.c8ff7c79a9a21ac25d81ef3p-2, .lo = -0x1.1976d471342b17dca47c9d1e1d98p-104 },
        .{ .hi = 0x1.ce1af0b85f3eb7b7d2bcaadp-2, .lo = 0x1.33a4e218c8c00b2f6f2b23998791p-99 },
        .{ .hi = 0x1.d32fe7e00ebd561dec8cbebep-2, .lo = 0x1.1b7e8c55a6ffaf7eb72c1ff893cdp-99 },
        .{ .hi = 0x1.d83e7258a2f3e50515ba2ecap-2, .lo = -0x1.7778ad7b599f3edc40a13fe57cp-99 },
        .{ .hi = 0x1.dd46a04c1c4a0bee626a49d2p-2, .lo = -0x1.23c02c15f2f66328a06054db5e01p-101 },
        .{ .hi = 0x1.e24881a7c6c261cbd8f45954p-2, .lo = 0x1.48c6c5403df1764e1ed219643a85p-99 },
        .{ .hi = 0x1.e744261d68787e37da36f3ccp-2, .lo = -0x1.2e44bfb5e71d55a11feaedf56a94p-100 },
        .{ .hi = 0x1.ec399d2468cc0175cee53f36p-2, .lo = -0x1.8d2027bb4681af8a138d77633327p-99 },
        .{ .hi = 0x1.f128f5faf06ecb35c83b1132p-2, .lo = -0x1.851461536ddd17ac271709c2b464p-101 },
        .{ .hi = 0x1.f6123fa7028ac61456c3cb6cp-2, .lo = 0x1.a0a432a2414cc0b049c0fb73b4dep-99 },
        .{ .hi = 0x1.faf588f78f31ed9afb3e4ea8p-2, .lo = 0x1.afec6d4cde2ef184dc7b6e634ba1p-100 },
        .{ .hi = 0x1.ffd2e0857f4985597d0364c8p-2, .lo = 0x1.af246e3379d3ea68e29866b3b38bp-100 },
        .{ .hi = 0x1.02552a5a5d0fec69c695d7eep-1, .lo = 0x1.fff1a3725c5c6261a75dc4f512adp-99 },
        .{ .hi = 0x1.04bdf9da926d265fcc1008b2p-1, .lo = 0x1.df6a6d08e4470f10c7053f04f1ep-99 },
        .{ .hi = 0x1.0723e5c1cdf404e579638911p-1, .lo = 0x1.baad95bd2eba9089087bae740509p-99 },
        .{ .hi = 0x1.0986f4f573520b91fda94ff4p-1, .lo = 0x1.fe038113f135a26389f13c4bde3ap-100 },
        .{ .hi = 0x1.0be72e4252a82b69897bb33ep-1, .lo = -0x1.9649bc990440ca2c12ee56f6c90bp-108 },
        .{ .hi = 0x1.0e44985d1cc8bf6eae5de969p-1, .lo = 0x1.8f8d1fbacf70a2da185e84859e36p-99 },
        .{ .hi = 0x1.109f39e2d4c96fde3ec9b0b8p-1, .lo = -0x1.b9d06df4e0c8337c0da8f63aefc7p-99 },
        .{ .hi = 0x1.12f719593efbc53012319c7dp-1, .lo = 0x1.a96893b2757f50123379aecd147cp-102 },
        .{ .hi = 0x1.154c3d2f4d5e9a98f33a3966p-1, .lo = -0x1.d7f56258b99e197c61c0a23b2403p-101 },
        .{ .hi = 0x1.179eabbd899a0bfc60e6fa08p-1, .lo = -0x1.68f2a71c8279b89eb8392b7a41ep-100 },
        .{ .hi = 0x1.19ee6b467c96ecc5cbdd7782p-1, .lo = -0x1.0c2a8ef8715f93d3c8e2c9016713p-100 },
        .{ .hi = 0x1.1c3b81f713c24bc94f8ecdfcp-1, .lo = -0x1.d103880b3dc864d107231c87eaa7p-100 },
        .{ .hi = 0x1.1e85f5e7040d03dec59a5f3ep-1, .lo = 0x1.e35f2e7ca4f4817696ad39f9a4b2p-100 },
        .{ .hi = 0x1.20cdcd192ab6d93503d0f75cp-1, .lo = -0x1.3db0bb5bf2b76be256c1a2a08a8p-103 },
        .{ .hi = 0x1.23130d7bebf4282de368722dp-1, .lo = -0x1.6dfadc7219019f05279c9cfd2b08p-99 },
        .{ .hi = 0x1.2555bce98f7cb3c043adad1p-1, .lo = 0x1.e71084750a06eb301ae8308feca1p-100 },
        .{ .hi = 0x1.2795e1289b11aeb783f3db97p-1, .lo = -0x1.e3801fe56c1467b5e622105c5e41p-99 },
        .{ .hi = 0x1.29d37fec2b08ac85cd6cba5dp-1, .lo = -0x1.824a2f303e0aa6995ef5598cc5b7p-100 },
        .{ .hi = 0x1.2c0e9ed448e8bb97a9c31ba3p-1, .lo = -0x1.8676adfad5c83dea45d7349693e3p-99 },
        .{ .hi = 0x1.2e47436e4026840542186922p-1, .lo = 0x1.ab1252cf29452c88ebc5ce2f36f2p-101 },
        .{ .hi = 0x1.307d7334f10be1fb590a1f56p-1, .lo = 0x1.b66f70c05b80999c08cdd48a021p-99 },
        .{ .hi = 0x1.32b1339121d71320556b67b2p-1, .lo = 0x1.6b06715ba133462ddf94bde6b3a5p-100 },
        .{ .hi = 0x1.34e289d9ce1d316eb92d885dp-1, .lo = -0x1.b151b59c44058fa92837dec71351p-101 },
        .{ .hi = 0x1.37117b54747b5c5dd024844ep-1, .lo = -0x1.037076a726793d7e93c9b2f3eef6p-100 },
        .{ .hi = 0x1.393e0d3562a19a9c4426036ep-1, .lo = -0x1.cf1c277a3a0d863fefb367ef8616p-102 },
        .{ .hi = 0x1.3b68449fffc22af8edec1859p-1, .lo = 0x1.b341d6de6d9b9591a54790d29adcp-100 },
        .{ .hi = 0x1.3d9026a7156faa404263d0adp-1, .lo = 0x1.3cf6b809d96954adf1ff9360bd04p-100 },
        .{ .hi = 0x1.3fb5b84d16f425b4e9d505cbp-1, .lo = -0x1.110c9bd8986629a5a46a5834774cp-99 },
        .{ .hi = 0x1.41d8fe84672ae6464bcc2f46p-1, .lo = 0x1.779538890dd44eadeb32e848f817p-105 },
        .{ .hi = 0x1.43f9fe2f9ce677a727b9b60fp-1, .lo = -0x1.e6927c891167a0306333dca3b8a4p-101 },
        .{ .hi = 0x1.4618bc21c5ec27d0b7b37b34p-1, .lo = -0x1.c65df511a65b67fe9778d8694229p-100 },
        .{ .hi = 0x1.48353d1ea88df73d5e8bb302p-1, .lo = -0x1.7b4f3e104187cc8aca358d9263f9p-104 },
        .{ .hi = 0x1.4a4f85db03ebb0227bf47a6fp-1, .lo = -0x1.e49ce91908e6e2750b818bba40e6p-100 },
        .{ .hi = 0x1.4c679afccee39b168ecdd318p-1, .lo = 0x1.bf619db0d889bbe38f559618dbd3p-99 },
        .{ .hi = 0x1.4e7d811b75bb09cb09856458p-1, .lo = 0x1.5770d0c5ebca2047bba2c9ee4f52p-99 },
        .{ .hi = 0x1.50913cc01686b4bcb3a5b0b5p-1, .lo = 0x1.b0f69791cf6c54c4e5d96f1d584fp-99 },
        .{ .hi = 0x1.52a2d265bc5aaee77c8af15bp-1, .lo = 0x1.7aea7bed0920f6a4c39b31ea388bp-100 },
        .{ .hi = 0x1.54b2467999497a915428b43ep-1, .lo = -0x1.f434bb5d154a84758a2a5033748cp-99 },
        .{ .hi = 0x1.56bf9d5b3f399411c6217364p-1, .lo = -0x1.a6323ea9ce40a3caf6baebad2c64p-104 },
        .{ .hi = 0x1.58cadb5cd79893092f25d931p-1, .lo = -0x1.d3d5761cff2a6a51ddc9c241881cp-99 },
        .{ .hi = 0x1.5ad404c359f2cfb29aaa5f02p-1, .lo = 0x1.cd40845839e04578161ccf77753bp-100 },
        .{ .hi = 0x1.5cdb1dc6c17648cf6e3c5d71p-1, .lo = -0x1.f3a84fed7a8e6b8a7923783c6bf7p-99 },
        .{ .hi = 0x1.5ee02a924167570d6095fd24p-1, .lo = 0x1.03ef4c629f04ae4e7a29309e6688p-100 },
        .{ .hi = 0x1.60e32f44788d8ca7c895a0b5p-1, .lo = -0x1.3557995d063914a66aa81ead3fdbp-101 },
        .{ .hi = 0x1.62e42fefa39ef35793c7673p-1, .lo = 0x1.f97b57a079a193394c5b16c5068cp-103 },
    };
    return impl.proc1(.{ .poly = poly, .tab = tab }, x);
}

pub fn logl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return log(x),
        80 => return __logx(x),
        128 => return logq(x),
        else => @compileError("unreachable"),
    }
}

test "logf() special" {
    try expectEqual(logf(0.0), -math.inf(f32));
    try expectEqual(logf(-0.0), -math.inf(f32));
    try expect(math.isPositiveZero(logf(1.0)));
    try expectEqual(logf(math.e), 1.0);
    try expectEqual(logf(math.inf(f32)), math.inf(f32));
    try expect(math.isNan(logf(-1.0)));
    try expect(math.isNan(logf(-math.inf(f32))));
    try expect(math.isNan(logf(math.nan(f32))));
    try expect(math.isNan(logf(math.snan(f32))));
}

test "logf() sanity" {
    try expect(math.isNan(logf(-0x1.0223a0p+3)));
    try expectEqual(logf(0x1.161868p+2), 0x1.7815b0p+0);
    try expect(math.isNan(logf(-0x1.0c34b4p+3)));
    try expect(math.isNan(logf(-0x1.a206f0p+2)));
    try expectEqual(logf(0x1.288bbcp+3), 0x1.1cfcd6p+1);
    try expectEqual(logf(0x1.52efd0p-1), -0x1.a6694cp-2);
    try expect(math.isNan(logf(-0x1.a05cc8p-2)));
    try expectEqual(logf(0x1.1f9efap-1), -0x1.2742bap-1);
    try expectEqual(logf(0x1.8c5db0p-1), -0x1.062160p-2);
    try expect(math.isNan(logf(-0x1.5b86eap-1)));
}

test "logf() boundary" {
    try expectEqual(logf(0x1.fffffep+127), 0x1.62e430p+6); // Max input value
    try expectEqual(logf(0x1p-149), -0x1.9d1da0p+6); // Min positive input value
    try expect(math.isNan(logf(-0x1p-149))); // Min negative input value
    try expectEqual(logf(0x1.000002p+0), 0x1.fffffep-24); // Last value before result reaches +0
    try expectEqual(logf(0x1.fffffep-1), -0x1p-24); // Last value before result reaches -0
    try expectEqual(logf(0x1p-126), -0x1.5d58a0p+6); // First subnormal
    try expect(math.isNan(logf(-0x1p-126))); // First negative subnormal
}

test "log() special" {
    try expectEqual(log(0.0), -math.inf(f64));
    try expectEqual(log(-0.0), -math.inf(f64));
    try expect(math.isPositiveZero(log(1.0)));
    try expectEqual(log(math.e), 1.0);
    try expectEqual(log(math.inf(f64)), math.inf(f64));
    try expect(math.isNan(log(-1.0)));
    try expect(math.isNan(log(-math.inf(f64))));
    try expect(math.isNan(log(math.nan(f64))));
    try expect(math.isNan(log(math.snan(f64))));
}

test "log() sanity" {
    try expect(math.isNan(log(-0x1.02239f3c6a8f1p+3)));
    try expectEqual(log(0x1.161868e18bc67p+2), 0x1.7815b08f99c65p+0);
    try expect(math.isNan(log(-0x1.0c34b3e01e6e7p+3)));
    try expect(math.isNan(log(-0x1.a206f0a19dcc4p+2)));
    try expectEqual(log(0x1.288bbb0d6a1e6p+3), 0x1.1cfcd53d72604p+1);
    try expectEqual(log(0x1.52efd0cd80497p-1), -0x1.a6694a4a85621p-2);
    try expect(math.isNan(log(-0x1.a05cc754481d1p-2)));
    try expectEqual(log(0x1.1f9ef934745cbp-1), -0x1.2742bc03d02ddp-1);
    try expectEqual(log(0x1.8c5db097f7442p-1), -0x1.06215de4a3f92p-2);
    try expect(math.isNan(log(-0x1.5b86ea8118a0ep-1)));
}

test "log() boundary" {
    try expectEqual(log(0x1.fffffffffffffp+1023), 0x1.62e42fefa39efp+9); // Max input value
    try expectEqual(log(0x1p-1074), -0x1.74385446d71c3p+9); // Min positive input value
    try expect(math.isNan(log(-0x1p-1074))); // Min negative input value
    try expectEqual(log(0x1.0000000000001p+0), 0x1.fffffffffffffp-53); // Last value before result reaches +0
    try expectEqual(log(0x1.fffffffffffffp-1), -0x1p-53); // Last value before result reaches -0
    try expectEqual(log(0x1p-1022), -0x1.6232bdd7abcd2p+9); // First subnormal
    try expect(math.isNan(log(-0x1p-1022))); // First negative subnormal
}

test "logq() special" {
    try expectEqual(logq(0.0), -math.inf(f128));
    try expectEqual(logq(-0.0), -math.inf(f128));
    try expect(math.isPositiveZero(logq(1.0)));
    // Sadly, the rounding gods decided that 0.9999999999999999999999999999999999
    // is the correctly rounded value of logq(math.e)
    try expectApproxEqRel(logq(math.e), 1.0, math.floatEpsAt(f128, 1.0));
    try expectEqual(logq(math.inf(f128)), math.inf(f128));
    try expect(math.isNan(logq(-1.0)));
    try expect(math.isNan(logq(-math.inf(f128))));
    try expect(math.isNan(logq(math.nan(f128))));
    try expect(math.isNan(logq(math.snan(f128))));
}

test "logq() boundary" {
    try expectEqual(logq(0x1.ffffffffffffffffffffffffffffp16383), 0x1.62e42fefa39ef35793c7673007e6p13); // Max input value
    try expectEqual(logq(0x1p-16494), -0x1.6546282207802c89d24d65e96274p13); // Min positive input value
    try expect(math.isNan(logq(-0x1p-16494))); // Min negative input value
    try expectEqual(logq(0x1.0000000000000000000000000001p0), 0x1.ffffffffffffffffffffffffffffp-113); // Last value before result reaches +0
    try expectEqual(logq(0x1.ffffffffffffffffffffffffffffp-1), -0x1p-113); // Last value before result reaches -0
    try expectEqual(logq(0x1p-16382), -0x1.62d918ce2421d65ff90ac8f4ce66p13); // First subnormal
    try expect(math.isNan(logq(-0x1p-16382))); // First negative subnormal
}

test "logq() sanity" {
    try expectEqual(logq(4.151135979023751199079583784623537e-4), -7.7869583453055243113993340258295346e0);
    try expectEqual(logq(9.614234245933828353176667689130293e-14), -2.9972946567656004014786271559909435e1);
    try expectEqual(logq(1.012889803704721484375e13), 2.9946413646144315985379677542014356e1);
    try expectEqual(logq(2.397741857206453154086912e24), 5.613656963346284538829358703465392e1);
    try expectEqual(logq(3.442377567808290806386655232e27), 6.3405959896920645453203836625419693e1);
    try expectEqual(logq(1.0689155158234028407981544637594257e-8), -1.835403614606774451014272772421113e1);
    try expectEqual(logq(1.4813913545768791536741499811327596e-10), -2.263286917934202003739900705050399e1);
    try expectEqual(logq(4.518948965781299591064453125e10), 2.453413036705097282892685629562292e1);
    try expectEqual(logq(1.200355637363589375e14), 3.2418809179272977400408325788186897e1);
    try expectEqual(logq(6.6145398293682003021240234375e9), 2.261253606737223221601998075023261e1);
    try expectEqual(logq(5.16179116383965741056e20), 4.7692985503915646405875629300054525e1);
    // testing near 1
    try expectEqual(logq(1.026586845186097528392910049888087e0), 2.6239557099466251374193777672800004e-2);
    try expectEqual(logq(9.878220373715243107115568932385941e-1), -1.2252721576456821219120474521538944e-2);
    try expectEqual(logq(9.417921077517196685541245315675951e-1), -5.997072116986790367958922503195352e-2);
    try expectEqual(logq(1.043095786320424537962914257605007e0), 4.219300911769055080390811808602425e-2);
    try expectEqual(logq(1.019043049323190694932517175175235e0), 1.8863999985309781522599012445793722e-2);
}
