// Ported from:
//
// https://github.com/llvm/llvm-project/commit/d674d96bc56c0f377879d01c9d8dfdaaa7859cdb/compiler-rt/test/builtins/Unit/divdf3_test.c

const std = @import("std");
const math = std.math;
const testing = std.testing;

const __divdf3 = @import("divdf3.zig").__divdf3;

const nanRep: u64 = @as(u64, @bitCast(math.nan(f64)));
const infRep: u64 = @as(u64, @bitCast(math.inf(f64)));
const negInfRep: u64 = @as(u64, @bitCast(-math.inf(f64)));

fn compareResultD(result: f64, expected: u64) bool {
    const rep: u64 = @bitCast(result);

    if (rep == expected) {
        return true;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == nanRep) {
        if ((rep & 0x7ff0000000000000) == 0x7ff0000000000000 and
            (rep & 0xfffffffffffff) > 0)
        {
            return true;
        }
    }
    return false;
}

fn test__divdf3(a: f64, b: f64, expected: u64) !void {
    const x = __divdf3(a, b);
    const ret = compareResultD(x, expected);
    try testing.expect(ret == true);
}

test "divdf3" {
    try test__divdf3(1.0, 3.0, 0x3fd5555555555555);
    try test__divdf3(4.450147717014403e-308, 2.0, 0x10000000000000);
    try test__divdf3(1.0, 0x1.fffffffffffffp-1, 0x3ff0000000000001);

    try test__divdf3(math.nan(f64), 1.0, nanRep);
    try test__divdf3(1.0, math.nan(f64), nanRep);

    try test__divdf3(math.inf(f64), 1.0, infRep);
    try test__divdf3(-math.inf(f64), 1.0, negInfRep);
    try test__divdf3(1.0, math.inf(f64), 0x0000000000000000);
    try test__divdf3(1.0, -math.inf(f64), 0x8000000000000000);

    try test__divdf3(math.inf(f64), math.inf(f64), nanRep);
    try test__divdf3(0.0, 0.0, nanRep);
    try test__divdf3(-0.0, 0.0, nanRep);

    try test__divdf3(0.0, 1.0, 0x0000000000000000);
    try test__divdf3(-0.0, 1.0, 0x8000000000000000);
    try test__divdf3(1.0, 0.0, infRep);
    try test__divdf3(1.0, -0.0, negInfRep);

    try test__divdf3(0x1p-1022, 0x1p52, 0x0000000000000001);
    try test__divdf3(-0x1p-1022, 0x1p52, 0x8000000000000001);
    try test__divdf3(0x1p-1022, -0x1p52, 0x8000000000000001);

    try test__divdf3(1.0, 0x1p1023, 0x0008000000000000);
    try test__divdf3(-1.0, 0x1p1023, 0x8008000000000000);
}
