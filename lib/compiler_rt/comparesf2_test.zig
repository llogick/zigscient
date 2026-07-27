// Ported from:
//
// https://github.com/llvm/llvm-project/commit/d674d96bc56c0f377879d01c9d8dfdaaa7859cdb/compiler-rt/test/builtins/Unit/comparesf2_test.c

const std = @import("std");
const builtin = @import("builtin");

const compiler_rt = @import("../compiler_rt.zig");

const impl = @import("comparef.zig");
const Order = impl.Order;
const cmp_f32 = impl.cmp_f32;
const unord_f32 = impl.unord_f32;

const arguments = [_]f32{
    std.math.nan(f32),
    -std.math.inf(f32),
    -0x1.fffffep127,
    -0x1.000002p0 - 0x1.000000p0,
    -0x1.fffffep-1,
    -0x1.000000p-126,
    -0x0.fffffep-126,
    -0x0.000002p-126,
    -0.0,
    0.0,
    0x0.000002p-126,
    0x0.fffffep-126,
    0x1.000000p-126,
    0x1.fffffep-1,
    0x1.000000p0,
    0x1.000002p0,
    0x1.fffffep127,
    std.math.inf(f32),
};

test "compare f32" {
    for (arguments[0..], 0..) |arg_i, i| {
        for (arguments[0..], 0..) |arg_j, j| {
            const expected_unord = i == 0 or j == 0;
            const expected_order: ?Order = if (expected_unord) null else switch (std.math.order(
                i - @intFromBool(i >= 9),
                j - @intFromBool(j >= 9),
            )) {
                .lt => .lt,
                .eq => .eq,
                .gt => .gt,
            };
            try std.testing.expect(expected_order == cmp_f32(arg_i, arg_j));
            try std.testing.expect(expected_unord == unord_f32(arg_i, arg_j));
        }
    }
}
