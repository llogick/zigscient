// Ported from:
//
// https://github.com/llvm/llvm-project/commit/d674d96bc56c0f377879d01c9d8dfdaaa7859cdb/compiler-rt/test/builtins/Unit/divsf3_test.c

const std = @import("std");
const math = std.math;
const testing = std.testing;

const __divsf3 = @import("divsf3.zig").__divsf3;

const nanRep: u32 = @as(u32, @bitCast(math.nan(f32)));
const infRep: u32 = @as(u32, @bitCast(math.inf(f32)));
const negInfRep: u32 = @as(u32, @bitCast(-math.inf(f32)));

fn compareResultF(result: f32, expected: u32) bool {
    const rep: u32 = @bitCast(result);

    if (rep == expected) {
        return true;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == nanRep) {
        if ((rep & 0x7f800000) == 0x7f800000 and
            (rep & 0x7fffff) > 0)
        {
            return true;
        }
    }
    return false;
}

fn test__divsf3(a: f32, b: f32, expected: u32) !void {
    const x = __divsf3(a, b);
    const ret = compareResultF(x, expected);
    try testing.expect(ret == true);
}

test "divsf3" {
    try test__divsf3(1.0, 3.0, 0x3EAAAAAB);
    try test__divsf3(2.3509887e-38, 2.0, 0x00800000);
    try test__divsf3(1.0, 0x1.fffffep-1, 0x3f800001);

    try test__divsf3(math.nan(f32), 1.0, nanRep);
    try test__divsf3(1.0, math.nan(f32), nanRep);

    try test__divsf3(math.inf(f32), 1.0, infRep);
    try test__divsf3(-math.inf(f32), 1.0, negInfRep);
    try test__divsf3(1.0, math.inf(f32), 0x00000000);
    try test__divsf3(1.0, -math.inf(f32), 0x80000000);

    try test__divsf3(math.inf(f32), math.inf(f32), nanRep);
    try test__divsf3(0.0, 0.0, nanRep);
    try test__divsf3(-0.0, 0.0, nanRep);

    try test__divsf3(0.0, 1.0, 0x00000000);
    try test__divsf3(-0.0, 1.0, 0x80000000);
    try test__divsf3(1.0, 0.0, infRep);
    try test__divsf3(1.0, -0.0, negInfRep);

    try test__divsf3(0x1p-126, 0x1p23, 0x00000001);
    try test__divsf3(-0x1p-126, 0x1p23, 0x80000001);
    try test__divsf3(0x1p-126, -0x1p23, 0x80000001);

    try test__divsf3(1.0, 0x1p127, 0x00400000);
    try test__divsf3(-1.0, 0x1p127, 0x80400000);
}
