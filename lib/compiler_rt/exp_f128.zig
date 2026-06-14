/// Implementation of f128 exp and exp2 based on:
///
/// * "Table-Driven Implementation of the Exponential Function in IEEE Floating-Point Arithmetic"
///   ACM Transactions on Mathematical Software (TOMS), Volume 15, Issue 2 pp. 144-157
///
/// and
///
/// * "Table-driven implementation of the Expm1 function in IEEE floating-point arithmetic"
///   ACM Transactions on Mathematical Software (TOMS), Volume 18, Issue 2 pp. 211-222
///
/// Both by Ping Tak Peter Tang.
///
/// Adapted by Christophe Delage to work with 128 bit floats and with base 2 and 10.
///
/// Accuracy tested on 100 million uniformly distributed random values:
///
/// exp:
///     when result is normal:    <= 0.5 ulp: 99.83%, worst case: 0.512
///     when result is subnormal: <= 0.5 ulp: 99.80%, worst case: 0.628
/// exp2:
///     when result is normal:    <= 0.5 ulp: 99.82%, worst case: 0.514
///     when result is subnormal: <= 0.5 ulp: 99.56%, worst case: 0.752
///
const exp_f128 = @This();

const std = @import("std");
const math = std.math;

pub fn exp(x: f128) callconv(.c) f128 {
    if (!math.isFinite(x)) {
        if (math.isNan(x)) {
            if (math.isSignalNan(x)) math.raiseInvalid();
            return math.nan(f128);
        }
        return if (math.signbit(x)) 0 else x;
    }
    if (@abs(x) > 12000) {
        if (math.signbit(x)) {
            math.raiseUnderflow();
            return 0;
        } else {
            math.raiseOverflow();
            return math.inf(f128);
        }
    }

    if (@abs(x) < 0x1p-114)
        return 1 + x;

    return proc1(cfg_e, x);
}

const cfg_e: Config = .{
    .inv_log_size = 92.33248261689365807103517958412109,
    .log_size_hi = 1.0830424696249145459644251897780967e-2,
    .neg_log_size_lo = -3.0422579568449217993561868333332404e-33,
    .poly = expPoly,
    .finalize = expFinalize,
};

/// Approximates e^(r_hi + r_lo) - 1.
fn expPoly(r_hi: f128, r_lo: f128) f128 {
    const a2: f128 = 0.5000000000000000000000000000000001;
    const a3: f128 = 0.16666666666666666666666666666666673;
    const a4: f128 = 4.16666666666666666666666665159063e-2;
    const a5: f128 = 8.333333333333333333333333293907277e-3;
    const a6: f128 = 1.3888888888888888889300177029864553e-3;
    const a7: f128 = 1.984126984126984127049928848046117e-4;
    const a8: f64 = 2.4801587301583374475925191558926944e-5;
    const a9: f64 = 2.7557319223981316410138550193306495e-6;
    const a10: f64 = 2.75573345290144319034653394989056e-7;
    const a11: f64 = 2.5052122512857680160207187885276378e-8;

    const r = r_hi + r_lo;
    const s: f64 = @floatCast(r);
    const rr = r * r;
    const ss = s * s;

    // Do the upper degree computation in f64 and try to get better ILP
    // by deviating from Horner's method. This does not measurably hurt
    // accuracy.
    const a10_11 = a10 + s * a11;
    const a8_9 = a8 + s * a9;
    const a8_11 = a8_9 + ss * a10_11;
    const a6_7 = a6 + r * a7;
    const a4_5 = a4 + r * a5;
    const a2_3 = a2 + r * a3;
    const a2_11 = a2_3 + rr * (a4_5 + rr * (a6_7 + rr * a8_11));

    return r_hi + (r_lo + rr * a2_11);
}

/// Computes 2^x
pub fn exp2(x: f128) callconv(.c) f128 {
    if (!math.isFinite(x)) {
        if (math.isNan(x)) {
            if (math.isSignalNan(x)) math.raiseInvalid();
            return math.nan(f128);
        }
        return if (math.signbit(x)) 0 else x;
    }
    if (@abs(x) > 17000) {
        if (math.signbit(x)) {
            math.raiseUnderflow();
            return 0;
        } else {
            math.raiseOverflow();
            return math.inf(f128);
        }
    }
    if (@abs(x) < 0x1p-114 * math.log2e)
        return 1 + x;

    return proc1(cfg_2, x);
}

/// Compute a^`x` or a^`x` - 1, depending on `cfg`.
fn proc1(comptime cfg: Config, x: f128) f128 {
    // Argument reduction: x = r * 2^(j / size + m)
    // with r in [-log_a(2) / 2 / size, log_a(2) / 2 / size].
    //
    // r computed as r_hi + r_lo to simulate higher precision.
    const n = @round(x * cfg.inv_log_size);
    const ni: i32 = @intFromFloat(n);
    const n2 = @mod(ni, size);
    const n1 = ni - n2;
    const m = @divExact(n1, size);
    const j: usize = @intCast(n2);

    const r_hi = x - n * cfg.log_size_hi;
    const r_lo = n * cfg.neg_log_size_lo;

    const pr = cfg.poly(r_hi, r_lo);

    return cfg.finalize(pr, j, m);
}

const cfg_2: Config = .{
    .inv_log_size = 64,
    .log_size_hi = 1.5625e-2,
    .neg_log_size_lo = 0,
    .poly = exp2Poly,
    .finalize = expFinalize,
};

/// Approximates 2^(r_hi + r_lo) - 1.
fn exp2Poly(r_hi: f128, r_lo: f128) f128 {
    const a1: f128 = 0.6931471805599453094172321214581766;
    const a2: f128 = 0.24022650695910071233355126316333273;
    const a3: f128 = 5.5504108664821579953142263768621824e-2;
    const a4: f128 = 9.618129107628477161979071497097137e-3;
    const a5: f128 = 1.3333558146428443423412221872998745e-3;
    const a6: f128 = 1.5403530393381609955139554247429082e-4;
    const a7: f128 = 1.5252733804059840280740292411812167e-5;
    const a8: f64 = 1.321548679014167884759296382063556e-6;
    const a9: f64 = 1.0178086009237659848870888288504849e-7;
    const a10: f64 = 7.0549159308426003613013130647805315e-9;
    const a11: f64 = 4.445540987582123304209680731453203e-10;

    const r = r_hi + r_lo;
    const s: f64 = @floatCast(r);
    const rr = r * r;
    const ss = s * s;

    // Do the upper degree computation in f64 and try to get better ILP
    // by deviating from Horner's method. This does not measurably hurt
    // accuracy.
    const a10_11 = a10 + s * a11;
    const a8_9 = a8 + s * a9;
    const a8_11 = a8_9 + ss * a10_11;
    const a6_7 = a6 + r * a7;
    const a4_5 = a4 + r * a5;
    const a2_3 = a2 + r * a3;
    const a2_11 = a2_3 + rr * (a4_5 + rr * (a6_7 + rr * a8_11));

    return r * (a1 + r * a2_11);
}

/// Configuration for computing a^x, a in {e, 2, 10}, or e^x - 1.
const Config = struct {
    /// size / log(a)
    inv_log_size: f128,

    // High bits of log(a) / size, with the 12 last bits set to 0
    log_size_hi: f128,
    // Low bits of log(a) / size, negated
    neg_log_size_lo: f128,

    /// Approximates a^(r_hi + r_lo) - 1.
    poly: fn (f128, f128) f128,

    /// Compute the final value, a^x or e^x - 1.
    finalize: fn (pr: f128, j: usize, m: i32) f128,
};

/// computes (1 + pr) * 2^(j / 32) * 2^m.
fn expFinalize(pr: f128, j: usize, m: i32) f128 {
    const sj_hi = exp2_tab[j].hi;
    const sj_lo = exp2_tab[j].lo;
    const sj = sj_hi + sj_lo;

    const x = sj_hi + (sj_lo + sj * pr);

    return math.ldexp(x, m);
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "expq() special" {
    try expectEqual(exp(0.0), 1.0);
    try expectEqual(exp(-0.0), 1.0);
    try expectEqual(exp(1.0), math.e);
    try expectEqual(exp(math.ln2), 2.0);
    try expect(math.isPositiveInf(exp(math.inf(f128))));
    try expect(math.isPositiveZero(exp(-math.inf(f128))));
    try expect(math.isNan(exp(math.nan(f128))));
    try expect(math.isNan(exp(math.snan(f128))));
}

test "expq() sanity" {
    try expectEqual(exp(0x1.161ba065182111ea1cf73db026b2p12), 0x1.83a48fa990038d5b6aebb7cac716p6419);
    try expectEqual(exp(-0x1.49ce1b7b0e51027f6db3fe83bff7p9), 0x1.4dfac2418bdadddd6cf1fa1fefddp-952);
    try expectEqual(exp(0x1.35395ecd9c471cb5a122e54421ap8), 0x1.1572fcd2d80a52183b1bc955dcb7p446);
    try expectEqual(exp(0x1.2dfaba39016894e707847c6440b4p13), 0x1.314a408dab5852acfb4370713cdbp13941);
    try expectEqual(exp(0x1.101337475539dd36e833c7d40d91p11), 0x1.2029e18fbabc334f851f14221089p3140);
    try expectEqual(exp(0x1.2df2675a752767aa05874af1118cp13), 0x1.af6cbcf21a569f825eaa6879d87dp13939);
    try expectEqual(exp(-0x1.c9900887871caf097d99f8398542p12), 0x1.04c39baa5c766f3de6233e8f07dp-10562);
    try expectEqual(exp(0x1.9bc48fe7bfa2ac7128ebbd4939e9p12), 0x1.d931cb3d966a597631fde3c69694p9504);
    try expectEqual(exp(-0x1.8868d9a1dd219debf76c9f0fb392p12), 0x1.f2dfb4906d3071c2df3e80934569p-9059);
    try expectEqual(exp(0x1.5f41cc1bcb930c61a05f067fc442p13), 0x1.296ca19217f05a510f9811aa0e9cp16216);
    try expectEqual(exp(0x1.35e8dfcc0cde6a334b9038fa98e6p13), 0x1.498de58f228e3c83d7e47400d686p14307);
    try expectEqual(exp(0x1.ffea26d2e6e91cd9f621e730bbd2p12), 0x1.80bdb34340cb9136969a18505dd6p11816);
    try expectEqual(exp(0x1.afc460feee0dc9db39bf49d3c112p11), 0x1.33d9f1d36aa9a75ecb5223a08282p4983);
    try expectEqual(exp(-0x1.15511240004039de7beb770b122p13), 0x1.42058fe87c73fe2eed08e91eb0ccp-12803);
    try expectEqual(exp(-0x1.a5e28048748f388fefc535e90fafp6), 0x1.c95ffed3eae71936b30ebdc29bfp-153);
    try expectEqual(exp(0x1.3110993e3603ad8aea31e268ee83p12), 0x1.ccf37b60dd3e26bb7fb6b5d9f8cdp7041);
    try expectEqual(exp(-0x1.a11e9d8a913df7ab8dcdef2179c4p12), 0x1.7e3089dc5ff6b84df2d1e042564cp-9629);
    try expectEqual(exp(-0x1.4bcbe608a6526310c7fc13922e9p13), 0x1.26d226f1f40ab0e96bf9a717535p-15318);
    try expectEqual(exp(0x1.410cb56d92bc5ae8986384c4299p13), 0x1.93300e94463e8e934eaff7563284p14821);
    try expectEqual(exp(-0x1.f78f1935bf343246826d6769415fp11), 0x1.1ace810ef509fd05b4870388788ap-5812);
}

test "expq() boundary" {
    // largest value before the result is infinite
    try expectEqual(exp(0x1.62e42fefa39ef35793c7673007e5p13), 0x1.ffffffffffffffffffffffffc4a8p16383);
    // first value that gives inf
    try expect(math.isPositiveInf(exp(0x1.62e42fefa39ef35793c7673007e6p13)));
    try expect(math.isPositiveInf(exp(math.floatMax(f128))));
    try expectEqual(exp(0x1p-16494), 1.0);
    try expectEqual(exp(-0x1p-16494), 1.0);
    try expectEqual(exp(0x1p-16382), 1.0);
    try expectEqual(exp(-0x1p-16382), 1.0);
    try expectEqual(exp(-0x1.654bb3b2c73ebb059fabb506ff33p13), 0x1p-16494);
    try expectEqual(exp(-0x1.654bb3b2c73ebb059fabb506ff34p13), 0);
    try expectEqual(exp(-0x1.62d918ce2421d65ff90ac8f4ce65p13), 0x1.00000000000000000000000015c6p-16382);
    try expectEqual(exp(-0x1.62d918ce2421d65ff90ac8f4ce66p13), 0x1.ffffffffffffffffffffffffeb8cp-16383);
}

test "exp2q() special" {
    try expectEqual(exp2(0.0), 1.0);
    try expectEqual(exp2(-0.0), 1.0);
    try expectEqual(exp2(1.0), 2.0);
    try expectEqual(exp2(-1.0), 0.5);
    try expectEqual(exp2(math.inf(f128)), math.inf(f128));
    try expect(math.isPositiveZero(exp2(-math.inf(f128))));
    try expect(math.isNan(exp2(math.nan(f128))));
    try expect(math.isNan(exp2(math.snan(f128))));
}

test "exp2q() boundary" {
    try expectEqual(exp2(0x1.ffffffffffffffffffffffffffffp13), 0x1.ffffffffffffffffffffffffd3a3p16383);
    try expect(math.isPositiveInf(exp2(0x1p14)));
    try expect(math.isPositiveInf(exp2(math.floatMax(f128))));
    try expectEqual(exp2(-0x1.01bcp14), 0);
    try expectEqual(exp2(-0x1.01bbffffffffffffffffffffffffp14), 0x1p-16494);
    try expectEqual(exp2(-0x1.fff0000000000000000000000001p13), 0x1.ffffffffffffffffffffffffd3a4p-16383);
    try expectEqual(exp2(-0x1.fffp13), 0x1p-16382);
    try expectEqual(exp2(0x1p-16494), 1.0);
    try expectEqual(exp2(-0x1p-16494), 1.0);
    try expectEqual(exp2(0x1p-16382), 1.0);
    try expectEqual(exp2(-0x1p-16382), 1.0);
}

test "exp2q() sanity" {
    try expectEqual(exp2(0x1.89e197c1a4509481147ae147ae16p12), 0x1.1249d5e676aa9feec3a5953b7c02p6302);
    try expectEqual(exp2(-0x1.b411f0cfad25fc1b5c28f5c28f57p9), 0x1.d09909ac25bf2b1e11958781a70ap-873);
    try expectEqual(exp2(0x1.e83de574e1a8b96e147ae147ae2p8), 0x1.2eb5386c57c57bc388716eaccd12p488);
    try expectEqual(exp2(0x1.a9b613bed67b5f363d70a3d70a3ep13), 0x1.b16d037cd2c9626236091147b746p13622);
    try expectEqual(exp2(0x1.84c9c52432be7a8a28f5c28f5c2bp11), 0x1.3c5614f7f1ddbadb57dc669669e2p3110);
    try expectEqual(exp2(0x1.a9aa63b33e07e2bd23d70a3d70a5p13), 0x1.3ae2967925b501adb329d3bdc999p13621);
    try expectEqual(exp2(-0x1.3f8d7f1b5b5ad15a028f5c28f5c2p13), 0x1.3e02ffbf66c581bd049af0ba1014p-10226);
    try expectEqual(exp2(0x1.22c788348289d077a3d70a3d70a4p13), 0x1.eba8052f961ea5fb455eb7fd72c5p9304);
    try expectEqual(exp2(-0x1.11cf846583d5645a628f5c28f5c2p13), 0x1.0aefc431a531a66384b8682fd26p-8762);
    try expectEqual(exp2(0x1.eee7707f597161b90a3d70a3d70bp13), 0x1.e7ba24db2ff207c89727d80fca5dp15836);
    try expectEqual(exp2(0x1.b4d8b18ce858fe773d70a3d70a3ep13), 0x1.0fdaed7d8d2bd78a08575b84b9edp13979);
    try expectEqual(exp2(0x1.6916f408801b3f7ebd70a3d70a3ep13), 0x1.d39bbbe66e1288441ef91fb6c4f8p11554);
    try expectEqual(exp2(0x1.32826286d5689c66147ae147ae15p12), 0x1.1bdd18f576fffb40d7a7c4600473p4904);
    try expectEqual(exp2(-0x1.83b40cdd8603c81b65c28f5c28f6p13), 0x1.687736e6ce5610f434444b20f2a5p-12407);
    try expectEqual(exp2(-0x1.7832ea6506b0b2f47ae147ae144dp6), 0x1.eea794ee31522277606ff7a2c8ep-95);
    try expectEqual(exp2(0x1.afbb8b6830cac8c2e147ae147ae2p12), 0x1.a620a1f8a46335e10818a504693cp6907);
    try expectEqual(exp2(-0x1.2328a820e1db0e1b028f5c28f5c2p13), 0x1.e3add1a5b805ac7fa39b1ecf7a2ap-9318);
    try expectEqual(exp2(-0x1.d03363f43eb86051c5c28f5c28f6p13), 0x1.7dac5a9d06f845523a229370d6fbp-14855);
    try expectEqual(exp2(0x1.c47d13ba4001d5d6a3d70a3d70a5p13), 0x1.8d7369b8ad7bd5aace25ccb030dbp14479);
    try expectEqual(exp2(-0x1.5e280f18074b0b38d1eb851eb851p12), 0x1.691d77d02a99bab87b9bd0aeb82ep-5603);
}

const size = 64;

/// exp2_tab[j].hi + exp2_tab[j].lo ~= 2^(j / size)
/// where exp2_tab[j].hi has its 30 trailing bits set to 0
const exp2_tab = [size]struct { hi: f128, lo: f128 }{
    .{ .hi = 1, .lo = 0 },
    .{ .hi = 1.0108892860517004600204097572469746, .lo = 3.331488596564031210563288051982794e-26 },
    .{ .hi = 1.0218971486541166782344800872427626, .lo = 4.754053684121973789288755464722138e-26 },
    .{ .hi = 1.0330248790212284225001081883964135, .lo = 9.557404741840277960546616586298063e-26 },
    .{ .hi = 1.044273782427413840321966300719135, .lo = 1.7802079401409229639033486606835582e-25 },
    .{ .hi = 1.0556451783605571588083412749313592, .lo = 5.022157947196508429749069389839003e-26 },
    .{ .hi = 1.0671404006768236181695209696174248, .lo = 1.5137538440721428405259778473587436e-25 },
    .{ .hi = 1.0787607977571197937406800254939246, .lo = 1.1944558390181437089024030105545753e-26 },
    .{ .hi = 1.0905077326652576592070106394193907, .lo = 1.6341317298466358429137337862221883e-26 },
    .{ .hi = 1.1023825833078409435564140763781162, .lo = 1.3304753063524778951752027959085558e-25 },
    .{ .hi = 1.1143867425958925363088128257407598, .lo = 1.3117884324019192923687629273175252e-25 },
    .{ .hi = 1.1265216186082418997947985102919192, .lo = 1.3349511554260129942233288245148925e-25 },
    .{ .hi = 1.1387886347566916537038301230733987, .lo = 1.6076811251744575806878211946090158e-25 },
    .{ .hi = 1.1511892299529827058177595055860644, .lo = 1.296159181480888798344830542672908e-25 },
    .{ .hi = 1.1637248587775775138135734257915416, .lo = 1.7330064367522746277589854745025186e-25 },
    .{ .hi = 1.1763969916502812762846455513693297, .lo = 1.771145189358715817500494171124228e-25 },
    .{ .hi = 1.1892071150027210667174999505630234, .lo = 1.9997452525989289056308227410382985e-26 },
    .{ .hi = 1.2021567314527031420963969135940365, .lo = 4.39037293484801126250674148724549e-26 },
    .{ .hi = 1.2152473599804688781165200985991755, .lo = 1.527396229646477709981006835952422e-25 },
    .{ .hi = 1.228480536106870005694008874178169, .lo = 8.361461276961479852265822764365295e-26 },
    .{ .hi = 1.2418578120734840485936772681433546, .lo = 2.0058324097379166931165857504486515e-25 },
    .{ .hi = 1.2553807570246910895793906081957795, .lo = 4.924652165836275746251690393601314e-26 },
    .{ .hi = 1.2690509571917332225544190491370338, .lo = 3.189530418840927873154659237729416e-26 },
    .{ .hi = 1.2828700160787782807266696484653204, .lo = 1.3255619363013763369194141036415331e-25 },
    .{ .hi = 1.2968395546510096659337539149835045, .lo = 2.02808946708216061939618255479545e-25 },
    .{ .hi = 1.310961211524764341922991651706552, .lo = 1.346242038813654021913487031222685e-25 },
    .{ .hi = 1.3252366431597412946295370636866045, .lo = 3.1812117152957157712136370198427476e-26 },
    .{ .hi = 1.3396675240533030053600306458323573, .lo = 2.3891995273689563530726030193400994e-26 },
    .{ .hi = 1.3542555469368927282980146833689865, .lo = 5.67717163322109547382357648078323e-26 },
    .{ .hi = 1.3690024229745906119296010288577105, .lo = 1.0412448235463674573152224239700108e-25 },
    .{ .hi = 1.3839098819638319548726593727386685, .lo = 1.5452652430918943949928858324045516e-25 },
    .{ .hi = 1.3989796725383111402095280019026587, .lo = 1.3481253628381644220060758348040214e-25 },
    .{ .hi = 1.4142135623730950488016886615184001, .lo = 6.269129796655816816448098260436884e-26 },
    .{ .hi = 1.4296133383919700112350655775923445, .lo = 2.0068279541703738029999633782788845e-25 },
    .{ .hi = 1.445180806977046620037006089799907, .lo = 1.5167176381672076760972768074093684e-25 },
    .{ .hi = 1.4609177941806469886513027234439021, .lo = 1.6686671941792611979901360149296145e-25 },
    .{ .hi = 1.4768261459394993113869072754361651, .lo = 2.0493788478634531656455008519536741e-25 },
    .{ .hi = 1.49290772829126484920064342375234, .lo = 1.0773433350993147906480285567163657e-25 },
    .{ .hi = 1.5091644275934227397660193613621397, .lo = 1.8967105384997666454575618820074827e-25 },
    .{ .hi = 1.5255981507445383068512536547525588, .lo = 3.4764382194065807351168306319041174e-26 },
    .{ .hi = 1.5422108254079408236122917536092588, .lo = 1.0848147603849114107703141658063051e-25 },
    .{ .hi = 1.5590044002378369670337279975513864, .lo = 9.192347150259542397065645937482374e-26 },
    .{ .hi = 1.5759808451078864864552699975624628, .lo = 1.6261944219083569434254919427993836e-25 },
    .{ .hi = 1.5931421513422668979372484585565874, .lo = 1.8456248131371918402429861736678934e-25 },
    .{ .hi = 1.6104903319492543081795206443457414, .lo = 2.3011659157684786972918492411493627e-26 },
    .{ .hi = 1.6280274218573477668482183385098177, .lo = 1.835041970102208063150895447921664e-25 },
    .{ .hi = 1.64575547815396484451875663203744, .lo = 9.268838235051047071258544486384168e-26 },
    .{ .hi = 1.6636765803267364350463362566524458, .lo = 2.0032394462130729047106824908094624e-25 },
    .{ .hi = 1.6817928305074290860622508766963224, .lo = 7.577010737594502271619933404428869e-26 },
    .{ .hi = 1.7001063537185234695013623801157575, .lo = 1.933817448612744754580708784271012e-25 },
    .{ .hi = 1.718619298122477915629344290158266, .lo = 8.62980464213340198403279699525989e-26 },
    .{ .hi = 1.7373338352737062489942020634467155, .lo = 1.8425451283271326141972376758637252e-26 },
    .{ .hi = 1.7562521603732994831121604835510348, .lo = 1.3582427846847187375106521297188138e-25 },
    .{ .hi = 1.7753764925265212525505591418467304, .lo = 5.835259276799184480900795848675494e-26 },
    .{ .hi = 1.7947090750031071864277031433167551, .lo = 9.881102667288512774484945809680091e-26 },
    .{ .hi = 1.8142521755003987562498344916971016, .lo = 1.0866523870529919822788296235287719e-25 },
    .{ .hi = 1.8340080864093424634870830493492878, .lo = 1.4023900106308197217404351420134241e-25 },
    .{ .hi = 1.8539791250833855683924529817164416, .lo = 8.862125500492644219109133612513259e-26 },
    .{ .hi = 1.874167634110299901329998762784126, .lo = 1.8717032055831336786703352406163195e-25 },
    .{ .hi = 1.89457598158696564134021858484563, .lo = 6.858129468658742940783256569996436e-26 },
    .{ .hi = 1.915206561397147293872611189644507, .lo = 8.065132397713481068247895691781549e-26 },
    .{ .hi = 1.9360617934922944505980557715120804, .lo = 1.3305461113869976975105134936816773e-25 },
    .{ .hi = 1.9571441241754002690183220766337223, .lo = 1.749931492273774722940602643722382e-25 },
    .{ .hi = 1.9784560263879509682582497478585111, .lo = 1.702726561957295469933280686411065e-25 },
};
